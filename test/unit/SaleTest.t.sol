// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
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
        vm.warp(block.timestamp + SALE_PERIOD - 1);
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

    function testCannotUpdateScheduleWithSaleAmountTooHigh() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute first sale to reduce balance
        executeSale(user, 0, scheduleId);

        // Get the actual balance after the first sale 
        uint256 actualBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        
        // Try to update schedule to sell more than half of available balance
        uint256 tooHighAmount = actualBalance + 1; // More than balance
        bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__CannotSetSaleAmountMoreThanBalance.selector, tooHighAmount, actualBalance, actualBalance);
        vm.expectRevert(encodedRevert);
        vm.prank(user);
        dcaOutManager.updateDcaOutSchedule(0, scheduleId, tooHighAmount, SALE_PERIOD);
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
        bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__InexistentScheduleIndex.selector, user, 999, 1);
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
        bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__DocMintFailed.selector, totalRbtcToSpend);
        vm.expectRevert(encodedRevert);
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, totalRbtcToSpend);
    }

    function testCannotSellRbtcWithWrongScheduleId() public {
        // Create a schedule
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        
        // Try to sell with wrong schedule ID
        bytes32 wrongScheduleId = keccak256("wrong");
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIdAndIndexMismatch.selector, wrongScheduleId, scheduleId));
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, wrongScheduleId);
    }

    function testCannotSellRbtcWithInvalidScheduleIndex() public {
        // Try to sell with non-existent schedule index
        bytes32 fakeScheduleId = keccak256("fake");
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__InexistentScheduleIndex.selector, user, 0, 0));
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
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__TotalSaleAmountMismatch.selector, SALE_AMOUNT * 2, SALE_AMOUNT * 2 + 1));
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, SALE_AMOUNT * 2 + 1);
    }
}
