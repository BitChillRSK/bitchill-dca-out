// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

/**
 * @title SaleTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager sales (selling rBTC for DOC)
 */
contract SaleTest is DcaOutTestBase {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            SINGLE SALE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSellRbtc() public {
        // User creates schedule with deposit
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute the sale
        executeSale(user, 0, scheduleId);
    }

    function testCannotSellRbtcIfNotSwapper() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Use a non-swapper address
        address nonSwapper = makeAddr("nonSwapper");
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__UnauthorizedSwapper.selector, nonSwapper));
        vm.prank(nonSwapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testCannotSellRbtcBeforePeriodElapsed() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute first sale
        executeSale(user, 0, scheduleId);

        // Try to execute before period elapsed
        uint256 lastSaleTimestamp = block.timestamp;
        uint256 currentDayStart = lastSaleTimestamp - (lastSaleTimestamp % 1 days);
        vm.warp(currentDayStart + SALE_PERIOD - 1); // One second before 00:00 UTC of the day the sale is due
        bytes memory encodedRevert = abi.encodeWithSelector(
            IDcaOutManager.DcaOutManager__SalePeriodNotElapsed.selector,
            lastSaleTimestamp,
            lastSaleTimestamp + SALE_PERIOD,
            block.timestamp
        );
        vm.expectRevert(encodedRevert);

        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testCanSellRbtcOnceTargetDayReached() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute first sale at a late time in the day (simulating bot delay)
        uint256 firstSale = _nextUtcTimestamp(20 hours);
        vm.warp(firstSale);
        executeSale(user, 0, scheduleId);

        uint256 userDocBalanceBefore = dcaOutManager.getUserDocBalance(user);

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        uint256 lastSaleTimestamp = schedule.lastSaleTimestamp;
        assertEq(lastSaleTimestamp, _utcDayStart(firstSale));

        // The exact period would be lastSaleTimestamp + SALE_PERIOD (20 hours into day 1)
        // But with day-boundary logic, we can execute as soon as we reach day 1 (at 00:00)
        uint256 nextDayStart = lastSaleTimestamp + SALE_PERIOD - (lastSaleTimestamp + SALE_PERIOD) % 1 days;
        vm.warp(nextDayStart); // Warp to 00:00 of day 1

        // This should succeed even though we haven't reached lastSaleTimestamp + SALE_PERIOD yet
        // This is the key benefit: bot can run at consistent daily time (e.g., 9 AM) without drift
        executeSale(user, 0, scheduleId);

        // Verify the sale happened
        uint256 userDocBalance = dcaOutManager.getUserDocBalance(user);
        assertEq(userDocBalance, userDocBalanceBefore * 2, "User should have received DOC from both sales");

        schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.lastSaleTimestamp, lastSaleTimestamp + SALE_PERIOD);

        // Same-day second sale after the early UTC-day buy must revert
        vm.warp(nextDayStart + 9 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDcaOutManager.DcaOutManager__SalePeriodNotElapsed.selector,
                schedule.lastSaleTimestamp,
                schedule.lastSaleTimestamp + SALE_PERIOD,
                block.timestamp
            )
        );
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testGapResumeOnDueUtcDayConsumesThatDaySlot() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        uint256 firstSale = _nextUtcTimestamp(20 hours);
        vm.warp(firstSale);
        executeSale(user, 0, scheduleId);

        // First sale day 0 20:00, resume at 00:00 UTC of the third due day
        // (2 wall-clock periods later; without the extra snap today's slot would still be due)
        uint256 thirdDueDayStart = _utcDayStart(firstSale) + 3 * SALE_PERIOD;
        vm.warp(thirdDueDayStart);
        executeSale(user, 0, scheduleId);

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.lastSaleTimestamp, _utcDayStart(firstSale) + 3 * SALE_PERIOD);

        vm.warp(thirdDueDayStart + 9 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDcaOutManager.DcaOutManager__SalePeriodNotElapsed.selector,
                schedule.lastSaleTimestamp,
                schedule.lastSaleTimestamp + SALE_PERIOD,
                block.timestamp
            )
        );
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testCannotUpdateScheduleWithSaleAmountTooHigh() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute first sale to reduce balance
        executeSale(user, 0, scheduleId);

        // Get the actual balance after the first sale
        uint256 actualBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);

        // Try to update schedule to sell more than half of available balance
        uint256 tooHighAmount = actualBalance + 1; // More than balance
        bytes memory encodedRevert = abi.encodeWithSelector(
            IDcaOutManager.DcaOutManager__CannotSetSaleAmountMoreThanBalance.selector,
            tooHighAmount,
            actualBalance,
            actualBalance
        );
        vm.expectRevert(encodedRevert);
        vm.prank(user);
        dcaOutManager.updateDcaOutSchedule(0, scheduleId, tooHighAmount, SALE_PERIOD);
    }

    function testLastSaleTimestampConsistencyWhenSchedulePausedAndResumed(uint256 timePaused) public {
        if (timePaused < SALE_PERIOD) return; // Avoid known revert in `_validatePeriodElapsed()`
        if (timePaused > 100 * 52 weeks) return; // Avoid overflows
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        executeSale(user, 0, scheduleId);
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId); // Pausing is really just to make the test realistic, but has no effect
        uint256 gridOrigin = dcaOutManager.getSchedule(user, 0).lastSaleTimestamp;
        vm.warp(block.timestamp + timePaused); // Schedule is paused for some time
        vm.prank(user);
        dcaOutManager.unpauseSchedule(0, scheduleId);
        executeSale(user, 0, scheduleId);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        uint256 expectedLast = _snappedLastSaleTimestamp(gridOrigin, SALE_PERIOD, block.timestamp);
        assertEq(schedule.lastSaleTimestamp, expectedLast);
        assertLt(schedule.lastSaleTimestamp, block.timestamp + SALE_PERIOD);
        assertGt(schedule.lastSaleTimestamp, block.timestamp - SALE_PERIOD);
    }

    /*//////////////////////////////////////////////////////////////
                            BATCH SALE TESTS
    //////////////////////////////////////////////////////////////*/

    function testBatchSellRbtc() public {
        // User 1 creates schedule
        bytes32 scheduleId1 = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // User 2 creates schedule
        bytes32 scheduleId2 = createDcaOutSchedule(user2, SALE_AMOUNT * 2, SALE_PERIOD, 2 ether);

        // Execute batch sale
        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](2);

        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = scheduleId1;
        scheduleIds[1] = scheduleId2;

        executeBatchSale(users, scheduleIndexes, scheduleIds);
    }

    /*//////////////////////////////////////////////////////////////
                               REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertSellRbtcWithArrayIndexOutOfBounds() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Try to access non-existent schedule index
        bytes memory encodedRevert =
            abi.encodeWithSelector(IDcaOutManager.DcaOutManager__InexistentScheduleIndex.selector, user, 999, 1);
        vm.expectRevert(encodedRevert);
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 999, schedule.scheduleId);
    }

    function testRevertSellRbtcWithInsufficientBalance() public {
        vm.startPrank(user);
        // Create schedule with valid sale amount
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // User2 creates a schedule so contract's balance is enough for mint
        // (so the revert doesn't happen when calling `mintDoc()`)
        vm.prank(user2);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);

        // Withdraw almost all balance to make it insufficient for the sale amount
        vm.prank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, DEPOSIT_AMOUNT - SALE_AMOUNT / 10);

        // Check balance is now insufficient
        uint256 remainingBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertLt(remainingBalance, SALE_AMOUNT, "Balance should be insufficient for sale");

        // Try to sell - should fail due to insufficient balance on user's schedule
        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)");
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);
    }

    function testRevertBatchSellRbtcWithOneArrayTooShort() public {
        vm.prank(user);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        vm.prank(user2);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);

        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](1); // Malformed array
        bytes32[] memory scheduleIds = new bytes32[](2);
        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIds[0] = dcaOutManager.getSchedule(user, 0).scheduleId;
        scheduleIds[1] = dcaOutManager.getSchedule(user2, 0).scheduleId;
        vm.expectRevert("panic: array out-of-bounds access (0x32)");
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, SALE_AMOUNT * 2);
    }

    function testRevertBatchSellRbtcWithZeroTotalRbtcToSpend() public {
        vm.prank(user);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        vm.prank(user2);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](2);
        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = dcaOutManager.getSchedule(user, 0).scheduleId;
        scheduleIds[1] = dcaOutManager.getSchedule(user2, 0).scheduleId;

        uint256 totalRbtcToSpend = 0;
        // bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__DocMintFailed.selector, totalRbtcToSpend);
        // vm.expectRevert(encodedRevert);
        vm.expectRevert(); // Actual revert differs in fork tests because mock contract is not exactly like live contract, so emtpy expectRevert is used here
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, totalRbtcToSpend);
    }

    function testCannotSellRbtcWithWrongScheduleId() public {
        // Create a schedule
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Try to sell with wrong schedule ID
        bytes32 wrongScheduleId = keccak256("wrong");
        vm.expectRevert(
            abi.encodeWithSelector(
                IDcaOutManager.DcaOutManager__ScheduleIdAndIndexMismatch.selector, wrongScheduleId, scheduleId
            )
        );
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, wrongScheduleId);
    }

    function testCannotSellRbtcWithInvalidScheduleIndex() public {
        // Try to sell with non-existent schedule index
        bytes32 fakeScheduleId = keccak256("fake");
        vm.expectRevert(
            abi.encodeWithSelector(IDcaOutManager.DcaOutManager__InexistentScheduleIndex.selector, user, 0, 0)
        );
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, fakeScheduleId);
    }

    function testCannotBatchSellRbtcWithTotalSaleAmountMismatch() public {
        vm.prank(user);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        vm.prank(user2);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](2);
        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = dcaOutManager.getSchedule(user, 0).scheduleId;
        scheduleIds[1] = dcaOutManager.getSchedule(user2, 0).scheduleId;
        vm.expectRevert(
            abi.encodeWithSelector(
                IDcaOutManager.DcaOutManager__TotalSaleAmountMismatch.selector, SALE_AMOUNT * 2, SALE_AMOUNT * 2 + 1
            )
        );
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, SALE_AMOUNT * 2 + 1);
    }

    function testMultipleSalesDoNotCauseAccountingErrors() public {
        uint256 depositAmount = 136999999999999999; // deposit amount not divisible by 5
        uint256 saleAmount = depositAmount / 5;
        bytes32 scheduleId = createDcaOutSchedule(user, saleAmount, SALE_PERIOD, depositAmount);

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        // Execute 5 sales (one per day)
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + SALE_PERIOD);
            vm.prank(swapper);
            dcaOutManager.sellRbtc(user, 0, scheduleId);

            schedule = dcaOutManager.getSchedule(user, 0);
            uint256 expectedBalance = depositAmount - (saleAmount * (i + 1));
            assertEq(schedule.rbtcBalance, expectedBalance, "Balance should decrease by exact sale amount");
        }

        // After 5 sales, balance should be 0 (or at most a few wei from integer division remainder)
        schedule = dcaOutManager.getSchedule(user, 0);
        // Note: If depositAmount is not perfectly divisible by saleAmount, there will be a small remainder
        // This is expected from integer division and is safe
        assertLe(schedule.rbtcBalance, 4, "Balance should be 0 or small remainder from integer division");
    }

    function testMultipleBatchSalesDoNotCauseAccountingErrors() public {
        // Create schedules with balances that are not perfectly divisible
        // This tests that precision errors don't accumulate across batch sales
        uint256 depositAmount = 136999999999999999; // amount not divisible by 5
        uint256 saleAmount = depositAmount / 5;
        uint256 numOfUsers = 5;
        address[] memory users = new address[](numOfUsers);
        uint256[] memory scheduleIndexes = new uint256[](numOfUsers);
        bytes32[] memory scheduleIds = new bytes32[](numOfUsers);

        for (uint256 i = 0; i < numOfUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(users[i], depositAmount);
            scheduleIndexes[i] = 0;
            scheduleIds[i] = createDcaOutSchedule(users[i], saleAmount, SALE_PERIOD, depositAmount);
        }

        // Execute batch sale - each user's balance should decrease by exactly saleAmount
        executeBatchSale(users, scheduleIndexes, scheduleIds);

        for (uint256 i = 0; i < numOfUsers; i++) {
            IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(users[i], 0);
            uint256 expectedBalance = depositAmount - saleAmount;
            assertEq(
                schedule.rbtcBalance, expectedBalance, "Balance should decrease by exactly saleAmount after batch sale"
            );
        }

        // Execute 4 more batch sales to test multiple sequential batch operations
        for (uint256 sale = 0; sale < 4; sale++) {
            vm.warp(block.timestamp + SALE_PERIOD);
            executeBatchSale(users, scheduleIndexes, scheduleIds);
        }

        // After 5 batch sales, all balances should be 0 (or small remainder from integer division)
        for (uint256 i = 0; i < numOfUsers; i++) {
            IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(users[i], 0);
            // Small remainder possible if depositAmount not perfectly divisible by 5
            assertLe(schedule.rbtcBalance, 4, "Balance should be 0 or small remainder after 5 batch sales");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSellRbtcWhenSchedulePaused() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Pause the schedule
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId);

        // Try to sell - should fail
        vm.expectRevert(
            abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIsPaused.selector, user, scheduleId)
        );
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testCannotBatchSellRbtcWhenSchedulePaused() public {
        bytes32 scheduleId1 = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        bytes32 scheduleId2 = createDcaOutSchedule(user2, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Pause user's schedule
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId1);

        // Try to batch sell - should fail because user's schedule is paused
        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](2);
        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = scheduleId1;
        scheduleIds[1] = scheduleId2;

        vm.expectRevert(
            abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIsPaused.selector, user, scheduleId1)
        );
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, SALE_AMOUNT * 2);
    }

    function testCanSellRbtcAfterUnpausingSchedule() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Pause the schedule
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId);

        // Verify we can't sell when paused
        vm.expectRevert(
            abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIsPaused.selector, user, scheduleId)
        );
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);

        // Unpause the schedule
        vm.prank(user);
        dcaOutManager.unpauseSchedule(0, scheduleId);

        // Now we should be able to sell
        executeSale(user, 0, scheduleId);
    }

    function testCanBatchSellRbtcAfterUnpausingSchedule() public {
        bytes32 scheduleId1 = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        bytes32 scheduleId2 = createDcaOutSchedule(user2, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Pause user's schedule
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId1);

        // Verify we can't batch sell when paused
        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](2);
        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = scheduleId1;
        scheduleIds[1] = scheduleId2;

        vm.expectRevert(
            abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIsPaused.selector, user, scheduleId1)
        );
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, SALE_AMOUNT * 2);

        // Unpause the schedule
        vm.prank(user);
        dcaOutManager.unpauseSchedule(0, scheduleId1);

        // Now we should be able to batch sell
        executeBatchSale(users, scheduleIndexes, scheduleIds);
    }

    function _utcDayStart(uint256 timestamp) private pure returns (uint256) {
        return timestamp - (timestamp % 1 days);
    }

    function _nextUtcTimestamp(uint256 hourOfDay) private view returns (uint256) {
        uint256 ts = block.timestamp < 1 days ? 1 days : block.timestamp;
        uint256 candidate = _utcDayStart(ts) + hourOfDay;
        if (candidate < ts) {
            candidate += 1 days;
        }
        return candidate;
    }

    function _snappedLastSaleTimestamp(uint256 lastSaleTimestamp, uint256 salePeriod, uint256 timestamp)
        private
        pure
        returns (uint256)
    {
        uint256 periodsElapsed = (timestamp - lastSaleTimestamp) / salePeriod;
        if (periodsElapsed == 0) periodsElapsed = 1;
        uint256 snapped = lastSaleTimestamp + periodsElapsed * salePeriod;
        uint256 nextSaleDayStart = _utcDayStart(snapped + salePeriod);
        if (_utcDayStart(timestamp) >= nextSaleDayStart) {
            snapped += salePeriod;
        }
        return snapped;
    }
}
