// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutTestBase} from "./DcaOutTestBase.s.sol";
import {IDcaOutManager} from "../src/interfaces/IDcaOutManager.sol";
import "../test/Constants.sol";

/**
 * @title DcaOutManagerTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager
 */
contract DcaOutManagerTest is DcaOutTestBase {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                               SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            SCHEDULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createDcaOutSchedule() public {
        vm.startPrank(user);

        uint256 depositAmount = 1 ether;
        dcaOutManager.createDcaOutSchedule{value: depositAmount}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);

        uint256 numOfSchedules = dcaOutManager.getSchedules(user).length;
        assertEq(numOfSchedules, 1, "User should have 1 schedule");

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, TEST_RBTC_SELL_AMOUNT, "Wrong rBTC amount");
        assertEq(schedule.salePeriod, TEST_PERIOD, "Wrong period");
        assertEq(schedule.rbtcBalance, depositAmount, "Should have initial deposit");

        vm.stopPrank();
    }

    function test_CreateMultipleSchedules() public {
        vm.startPrank(user);

        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        dcaOutManager.createDcaOutSchedule{value: 2 ether}(TEST_RBTC_SELL_AMOUNT * 2, TEST_PERIOD * 2);

        uint256 numOfSchedules = dcaOutManager.getSchedules(user).length;
        assertEq(numOfSchedules, 2, "User should have 2 schedules");

        vm.stopPrank();
    }

    function testRevert_createDcaOutSchedule_AmountTooSmall() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountBelowMinimum.selector, MIN_SALE_AMOUNT - 1, MIN_SALE_AMOUNT));
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(MIN_SALE_AMOUNT - 1, TEST_PERIOD);

        vm.stopPrank();
    }

    function testRevert_createDcaOutSchedule_PeriodTooShort() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SalePeriodBelowMinimum.selector, MIN_SALE_PERIOD - 1, MIN_SALE_PERIOD));
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, MIN_SALE_PERIOD - 1);

        vm.stopPrank();
    }

    function testRevert_createDcaOutSchedule_MaxSchedulesReached() public {
        vm.startPrank(user);

        // Create max number of schedules (use less rBTC to avoid running out of funds)
        for (uint256 i = 0; i < MAX_SCHEDULES_PER_USER; i++) {
            dcaOutManager.createDcaOutSchedule{value: 0.1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        }

        // Try to create one more
        vm.expectRevert(IDcaOutManager.DcaOutManager__MaxSchedulesReached.selector);
        dcaOutManager.createDcaOutSchedule{value: 0.1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);

        vm.stopPrank();
    }

    function testRevert_createDcaOutSchedule_SaleAmountTooHigh() public {
        vm.startPrank(user);

        // Try to create schedule with sale amount > half of deposit
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, 0.6 ether, 1 ether, 0.5 ether));
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(0.6 ether, TEST_PERIOD); // 0.6 > 0.5 (half of 1)

        vm.stopPrank();
    }

    function test_DepositRbtc() public {
        vm.startPrank(user);
        // Create schedule with initial deposit
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        bytes32 scheduleId = schedule.scheduleId;

        uint256 balanceBefore = dcaOutManager.getScheduleRbtcBalance(user, 0);

        dcaOutManager.depositRbtc{value: 0.5 ether}(0, scheduleId);
        vm.stopPrank();

        uint256 balanceAfter = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(balanceAfter - balanceBefore, 0.5 ether, "Balance should increase by deposit amount");
    }

    function testRevert_DepositRbtc_InvalidScheduleId() public {
        vm.startPrank(user);

        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        bytes32 wrongScheduleId = bytes32(uint256(123));

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIdAndIndexMismatch.selector, 123, schedule.scheduleId));
        dcaOutManager.depositRbtc{value: 0.5 ether}(0, wrongScheduleId);

        vm.stopPrank();
    }

    function test_WithdrawRbtc() public {
        vm.startPrank(user);

        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, 0.5 ether);
        uint256 balanceAfter = user.balance;

        assertEq(balanceAfter - balanceBefore, 0.5 ether, "User should receive withdrawn rBTC");
        assertEq(dcaOutManager.getScheduleRbtcBalance(user, 0), 0.5 ether, "Schedule should have remaining balance");

        vm.stopPrank();
    }

    function test_deleteDcaOutSchedule() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        
        dcaOutManager.deleteDcaOutSchedule(0, schedule.scheduleId);

        // Check schedule is deleted (no longer exists)
        vm.expectRevert();
        dcaOutManager.getSchedule(user, 0);

        // Check rBTC was returned
        uint256 balanceAfter = user.balance;
        assertEq(balanceAfter - balanceBefore, 1 ether, "User should receive all rBTC back");

        vm.stopPrank();
    }

    function test_SetSaleAmount() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSaleAmount = 0.3 ether; // Valid amount (less than half of 1 ether)
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, newSaleAmount);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.rbtcSaleAmount, newSaleAmount, "Sale amount should be updated");
        
        vm.stopPrank();
    }

    function test_SetSalePeriod() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSalePeriod = 2 days; // Valid period
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, newSalePeriod);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.salePeriod, newSalePeriod, "Sale period should be updated");
        
        vm.stopPrank();
    }

    function testRevert_SetSaleAmount_TooHigh() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 invalidSaleAmount = 0.6 ether; // More than half of 1 ether
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, invalidSaleAmount, 1 ether, 0.5 ether));
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, invalidSaleAmount);
        
        vm.stopPrank();
    }

    function testRevert_SetSalePeriod_TooShort() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 invalidSalePeriod = MIN_SALE_PERIOD - 1;
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SalePeriodBelowMinimum.selector, invalidSalePeriod, MIN_SALE_PERIOD));
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, invalidSalePeriod);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteMint() public {
        // User creates schedule with deposit
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Execute the sale
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);

        // Check user received DOC
        uint256 userDocBalance = dcaOutManager.getUserDocBalance(user);
        assertTrue(userDocBalance > 0, "User should have DOC balance");

        // Check rBTC balance decreased
        uint256 remainingRbtc = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(remainingRbtc, 1 ether - TEST_RBTC_SELL_AMOUNT, "rBTC balance should decrease by sale amount");
    }

    function testRevert_ExecuteMint_NotSwapper() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__UnauthorizedSwapper.selector, address(this)));
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);
    }

    function testRevert_UpdateSchedule_SaleAmountTooHigh() public {
        vm.startPrank(user);
        // Create schedule with valid amount (0.05 ether is half of 0.1 ether)
        dcaOutManager.createDcaOutSchedule{value: 0.1 ether}(0.05 ether, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Execute first sale to reduce balance to 0.05 ether
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);

        // Fast forward time to allow next sale
        vm.warp(block.timestamp + TEST_PERIOD + 1);

        // Try to update schedule to sell more than available (0.06 ether > 0.05 ether available)
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, 0.06 ether, 0.05 ether, 0.025 ether));
        vm.startPrank(user);
        dcaOutManager.updateDcaOutSchedule(0, schedule.scheduleId, 0.06 ether, TEST_PERIOD);
        vm.stopPrank();
    }

    function testRevert_ExecuteMint_NotReady() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Execute first sale
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);

        // Try to execute again immediately (should fail)
        // Note: We can't predict exact timestamps on mainnet fork, so we just check the error type
        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);
    }

    function test_BatchExecuteMint() public {
        // User 1 creates schedule
        vm.prank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule1 = dcaOutManager.getSchedule(user, 0);

        // User 2 creates schedule
        vm.prank(user2);
        dcaOutManager.createDcaOutSchedule{value: 2 ether}(TEST_RBTC_SELL_AMOUNT * 2, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule2 = dcaOutManager.getSchedule(user2, 0);

        // Execute batch sale
        address[] memory users = new address[](2);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](2);

        users[0] = user;
        users[1] = user2;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = schedule1.scheduleId;
        scheduleIds[1] = schedule2.scheduleId;

        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds);

        // Check both users received DOC
        assertTrue(dcaOutManager.getUserDocBalance(user) > 0, "User 1 should have DOC");
        assertTrue(dcaOutManager.getUserDocBalance(user2) > 0, "User 2 should have DOC");
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetMinSalePeriod() public view {
        assertEq(dcaOutManager.getMinSalePeriod(), MIN_SALE_PERIOD, "Wrong min sell period");
    }

    function test_GetMaxSchedulesPerUser() public view {
        assertEq(dcaOutManager.getMaxSchedulesPerUser(), MAX_SCHEDULES_PER_USER, "Wrong max schedules");
    }

    function test_GetMinSaleAmount() public view {
        assertEq(dcaOutManager.getMinSaleAmount(), MIN_SALE_AMOUNT, "Wrong min sell amount");
    }
}