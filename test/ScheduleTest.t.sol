// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../src/interfaces/IDcaOutManager.sol";
import "../test/Constants.sol";

/**
 * @title ScheduleTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager schedule management
 */
contract ScheduleTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            SCHEDULE CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateDcaOutSchedule() public {
        vm.startPrank(user);

        uint256 depositAmount = 1 ether;
        
        // Check event emission (partial match)
        vm.expectEmit(true, true, false, true);
        emit DcaOutManager__ScheduleCreated(user, 0, bytes32(0), TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        
        dcaOutManager.createDcaOutSchedule{value: depositAmount}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);

        uint256 numOfSchedules = dcaOutManager.getSchedules(user).length;
        assertEq(numOfSchedules, 1, "User should have 1 schedule");

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, TEST_RBTC_SELL_AMOUNT, "Wrong rBTC amount");
        assertEq(schedule.salePeriod, TEST_PERIOD, "Wrong period");
        assertEq(schedule.rbtcBalance, depositAmount, "Should have initial deposit");

        vm.stopPrank();
    }

    function testCreateMultipleSchedules() public {
        vm.startPrank(user);

        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        dcaOutManager.createDcaOutSchedule{value: 2 ether}(TEST_RBTC_SELL_AMOUNT * 2, TEST_PERIOD * 2);

        uint256 numOfSchedules = dcaOutManager.getSchedules(user).length;
        assertEq(numOfSchedules, 2, "User should have 2 schedules");

        vm.stopPrank();
    }

    function testCannotCreateDcaOutScheduleWithAmountTooSmall() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountBelowMinimum.selector, MIN_SALE_AMOUNT - 1, MIN_SALE_AMOUNT));
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(MIN_SALE_AMOUNT - 1, TEST_PERIOD);

        vm.stopPrank();
    }

    function testCannotCreateDcaOutScheduleWithPeriodTooShort() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SalePeriodBelowMinimum.selector, MIN_SALE_PERIOD - 1, MIN_SALE_PERIOD));
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, MIN_SALE_PERIOD - 1);

        vm.stopPrank();
    }

    function testCannotCreateDcaOutScheduleWhenMaxSchedulesReached() public {
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

    function testCannotCreateDcaOutScheduleWithSaleAmountTooHigh() public {
        vm.startPrank(user);

        // Try to create schedule with sale amount > half of deposit
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, 0.6 ether, 1 ether, 0.5 ether));
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(0.6 ether, TEST_PERIOD); // 0.6 > 0.5 (half of 1)

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SCHEDULE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositRbtc() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        uint256 balanceBefore = dcaOutManager.getScheduleRbtcBalance(user, 0);
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcDeposited(user, 0, schedule.scheduleId, 0.5 ether);
        
        super.depositRbtc(user, 0, schedule.scheduleId, 0.5 ether);
        
        uint256 balanceAfter = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(balanceAfter - balanceBefore, 0.5 ether, "Balance should increase by deposit amount");
    }

    function testRevertDepositRbtcWithInvalidScheduleId() public {
        vm.startPrank(user);

        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        bytes32 wrongScheduleId = bytes32(uint256(123));

        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIdAndIndexMismatch.selector, 123, schedule.scheduleId));
        dcaOutManager.depositRbtc{value: 0.5 ether}(0, wrongScheduleId);

        vm.stopPrank();
    }

    function testWithdrawRbtc() public {
        vm.startPrank(user);

        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcWithdrawn(user, 0, schedule.scheduleId, 0.5 ether);
        
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, 0.5 ether);
        uint256 balanceAfter = user.balance;

        assertEq(balanceAfter - balanceBefore, 0.5 ether, "User should receive withdrawn rBTC");
        assertEq(dcaOutManager.getScheduleRbtcBalance(user, 0), 0.5 ether, "Schedule should have remaining balance");

        vm.stopPrank();
    }

    function testDeleteDcaOutSchedule() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__ScheduleDeleted(user, 0, schedule.scheduleId);
        
        dcaOutManager.deleteDcaOutSchedule(0, schedule.scheduleId);

        // Check schedule is deleted (no longer exists)
        vm.expectRevert();
        dcaOutManager.getSchedule(user, 0);

        // Check rBTC was returned
        uint256 balanceAfter = user.balance;
        assertEq(balanceAfter - balanceBefore, 1 ether, "User should receive all rBTC back");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SCHEDULE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetSaleAmount() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSaleAmount = 0.3 ether; // Valid amount (less than half of 1 ether)

        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__SaleAmountSet(user, schedule.scheduleId, newSaleAmount);        
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, newSaleAmount);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.rbtcSaleAmount, newSaleAmount, "Sale amount should be updated");
        
        vm.stopPrank();
    }

    function testSetSalePeriod() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSalePeriod = 2 days; // Valid period
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__SalePeriodSet(user, schedule.scheduleId, newSalePeriod);
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, newSalePeriod);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.salePeriod, newSalePeriod, "Sale period should be updated");
        
        vm.stopPrank();
    }

    function testUpdateDcaOutSchedule() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSaleAmount = 0.3 ether;
        uint256 newSalePeriod = 2 days;
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__ScheduleUpdated(user, 0, schedule.scheduleId, 1 ether, newSaleAmount, newSalePeriod);
        
        dcaOutManager.updateDcaOutSchedule(0, schedule.scheduleId, newSaleAmount, newSalePeriod);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.rbtcSaleAmount, newSaleAmount, "Sale amount should be updated");
        assertEq(updatedSchedule.salePeriod, newSalePeriod, "Sale period should be updated");
        
        vm.stopPrank();
    }

    function testCannotSetSaleAmountTooHigh() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 invalidSaleAmount = 0.6 ether; // More than half of 1 ether
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, invalidSaleAmount, 1 ether, 0.5 ether));
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, invalidSaleAmount);
        
        vm.stopPrank();
    }

    function testCannotSetSalePeriodTooShort() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 invalidSalePeriod = MIN_SALE_PERIOD - 1;
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SalePeriodBelowMinimum.selector, invalidSalePeriod, MIN_SALE_PERIOD));
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, invalidSalePeriod);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateScheduleWithExactMinAmount() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(MIN_SALE_AMOUNT, TEST_PERIOD);
        vm.stopPrank();
        
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, MIN_SALE_AMOUNT, "Should accept exact minimum amount");
    }

    function testCreateScheduleWithExactMinPeriod() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, MIN_SALE_PERIOD);
        vm.stopPrank();
        
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.salePeriod, MIN_SALE_PERIOD, "Should accept exact minimum period");
    }

    function testCreateScheduleWithMaxAllowedAmount() public {
        vm.startPrank(user);
        uint256 maxAmount = 0.5 ether; // Half of 1 ether deposit
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(maxAmount, TEST_PERIOD);
        vm.stopPrank();
        
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, maxAmount, "Should accept maximum allowed amount");
    }

    function testSetSaleAmountWithExactMaxAllowed() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();
        
        uint256 maxAllowed = 0.5 ether; // Half of 1 ether balance
        vm.startPrank(user);
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, maxAllowed);
        vm.stopPrank();
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.rbtcSaleAmount, maxAllowed, "Should accept exact maximum allowed amount");
    }

    function testSetSalePeriodWithExactMinPeriod() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();
        
        vm.startPrank(user);
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, MIN_SALE_PERIOD);
        vm.stopPrank();
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.salePeriod, MIN_SALE_PERIOD, "Should accept exact minimum period");
    }

    function testWithdrawRbtcWithExactBalance() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        vm.stopPrank();

        // Get the schedule after creation to avoid array out-of-bounds
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        uint256 balance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(balance, 1 ether, "Should have 1 ether balance");

        vm.startPrank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, balance); // Withdraw exact balance
        vm.stopPrank();

        uint256 newBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(newBalance, 0, "Balance should be zero after withdrawing all");
    }
}
