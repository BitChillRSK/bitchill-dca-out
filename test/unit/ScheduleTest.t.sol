// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

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
        // Use helper function which includes all necessary assertions
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
    }

    function testCreateMultipleSchedules() public {
        // Create first schedule
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        
        // Create second schedule
        createDcaOutSchedule(user, SALE_AMOUNT * 2, SALE_PERIOD * 2, 2 ether);

        uint256 numOfSchedules = dcaOutManager.getSchedules(user).length;
        assertEq(numOfSchedules, 2, "User should have 2 schedules");
    }

    function testCannotCreateDcaOutScheduleWithAmountTooSmall() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountBelowMinimum.selector, MIN_SALE_AMOUNT - 1, MIN_SALE_AMOUNT));
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(MIN_SALE_AMOUNT - 1, SALE_PERIOD);
    }

    function testCannotCreateDcaOutScheduleWithPeriodTooShort() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SalePeriodBelowMinimum.selector, MIN_SALE_PERIOD - 1, MIN_SALE_PERIOD));
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, MIN_SALE_PERIOD - 1);
    }

    function testCannotCreateDcaOutScheduleWhenMaxSchedulesReached() public {
        // Create max number of schedules (use less rBTC to avoid running out of funds)
        for (uint256 i = 0; i < MAX_SCHEDULES_PER_USER; i++) {
            createDcaOutSchedule(user, SALE_AMOUNT / 2, SALE_PERIOD, DEPOSIT_AMOUNT / 2);
        }

        // Try to create one more
        vm.expectRevert(IDcaOutManager.DcaOutManager__MaxSchedulesReached.selector);
        vm.prank(user);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT / 2}(SALE_AMOUNT, SALE_PERIOD);
    }

    function testCannotCreateDcaOutScheduleWithSaleAmountTooHigh() public {
        vm.prank(user); 
        // Try to create schedule with sale amount > deposit
        bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__CannotSetSaleAmountMoreThanBalance.selector, DEPOSIT_AMOUNT + 1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        vm.expectRevert(encodedRevert);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(DEPOSIT_AMOUNT + 1, SALE_PERIOD);
    }

    /*//////////////////////////////////////////////////////////////
                SCHEDULE BALANCE MANAGEMENT TESTS (rBTC)
    //////////////////////////////////////////////////////////////*/

    function testDepositRbtc() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        
        // Use helper function which includes all necessary assertions
        depositRbtc(user, 0, scheduleId, DEPOSIT_AMOUNT / 2);
    }

    function testRevertDepositRbtcWithInvalidScheduleId() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        bytes32 wrongScheduleId = keccak256("wrong");

        bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__ScheduleIdAndIndexMismatch.selector, wrongScheduleId, schedule.scheduleId);
        vm.expectRevert(encodedRevert);
        vm.prank(user);
        dcaOutManager.depositRbtc{value: DEPOSIT_AMOUNT / 2}(0, wrongScheduleId);
    }

    function testWithdrawRbtc() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        uint256 balanceBefore = user.balance;
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcWithdrawn(user, 0, schedule.scheduleId, DEPOSIT_AMOUNT / 2);
        
        vm.prank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, DEPOSIT_AMOUNT / 2);
        uint256 balanceAfter = user.balance;

        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT / 2, "User should receive withdrawn rBTC");
        assertEq(dcaOutManager.getScheduleRbtcBalance(user, 0), DEPOSIT_AMOUNT / 2, "Schedule should have remaining balance");
    }

    function testWithdrawRbtcMoreThanBalanceWithdrawsAll() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcWithdrawn(user, 0, schedule.scheduleId, DEPOSIT_AMOUNT);
        vm.prank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, DEPOSIT_AMOUNT + 1); // Withdraw more than the schedule balance
        uint256 balanceAfter = user.balance;

        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT, "User should receive all deposited rBTC back (and no more)");
        assertEq(dcaOutManager.getScheduleRbtcBalance(user, 0), 0 ether, "Schedule shouldn't have remaining balance");
    }

    function testWithdrawRbtcZeroWithdrawsAll() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcWithdrawn(user, 0, schedule.scheduleId, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, 0); // Withdraw all rBTC by setting amount to 0
        uint256 balanceAfter = user.balance;

        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT, "User should receive all rBTC back");
        assertEq(dcaOutManager.getScheduleRbtcBalance(user, 0), 0 ether, "Schedule shouldn't have remaining balance");
    }

    function testWithdrawRbtcWithExactBalance() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        uint256 balance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(balance, DEPOSIT_AMOUNT, "Should have DEPOSIT_AMOUNT balance");

        vm.prank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, balance); // Withdraw exact balance

        uint256 newBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(newBalance, 0, "Balance should be zero after withdrawing all");
    }
    
    function testDeleteDcaOutSchedule() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        uint256 balanceBefore = user.balance;
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__ScheduleDeleted(user, 0, schedule.scheduleId);
        
        vm.prank(user);
        dcaOutManager.deleteDcaOutSchedule(0, schedule.scheduleId);

        // Check schedule is deleted (no longer exists)
        vm.expectRevert();
        dcaOutManager.getSchedule(user, 0);

        // Check rBTC was returned
        uint256 balanceAfter = user.balance;
        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT, "User should receive all rBTC back");
    }

    /*//////////////////////////////////////////////////////////////
                            SCHEDULE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetSaleAmount() public {  
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSaleAmount = 0.3 ether; // Valid amount (less than half of DEPOSIT_AMOUNT)

        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__SaleAmountSet(user, schedule.scheduleId, newSaleAmount);        
        vm.prank(user);
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, newSaleAmount);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.rbtcSaleAmount, newSaleAmount, "Sale amount should be updated");
    }

    function testSetSalePeriod() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSalePeriod = 2 days; // Valid period
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__SalePeriodSet(user, schedule.scheduleId, newSalePeriod);
        vm.prank(user);
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, newSalePeriod);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.salePeriod, newSalePeriod, "Sale period should be updated");
    }

    function testUpdateDcaOutSchedule() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 newSaleAmount = 0.3 ether;
        uint256 newSalePeriod = 2 days;
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__ScheduleUpdated(user, 0, schedule.scheduleId, DEPOSIT_AMOUNT, newSaleAmount, newSalePeriod);
        vm.prank(user);
        dcaOutManager.updateDcaOutSchedule(0, schedule.scheduleId, newSaleAmount, newSalePeriod);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.rbtcSaleAmount, newSaleAmount, "Sale amount should be updated");
        assertEq(updatedSchedule.salePeriod, newSalePeriod, "Sale period should be updated");
    }

    function testCannotSetSaleAmountMoreThanBalance() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 invalidSaleAmount = DEPOSIT_AMOUNT + 1; // More than deposit
        bytes memory encodedRevert = abi.encodeWithSelector(IDcaOutManager.DcaOutManager__CannotSetSaleAmountMoreThanBalance.selector, invalidSaleAmount, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        vm.expectRevert(encodedRevert);
        vm.prank(user);
        dcaOutManager.setSaleAmount(0, schedule.scheduleId, invalidSaleAmount);
    }

    function testCannotSetSalePeriodTooShort() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        uint256 invalidSalePeriod = MIN_SALE_PERIOD - 1;
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SalePeriodBelowMinimum.selector, invalidSalePeriod, MIN_SALE_PERIOD));
        vm.prank(user);
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, invalidSalePeriod);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateScheduleWithExactMinAmount() public {
        createDcaOutSchedule(user, MIN_SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, MIN_SALE_AMOUNT, "Should accept exact minimum amount");
    }

    function testCreateScheduleWithExactMinPeriod() public {
        createDcaOutSchedule(user, SALE_AMOUNT, MIN_SALE_PERIOD, DEPOSIT_AMOUNT);
        
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.salePeriod, MIN_SALE_PERIOD, "Should accept exact minimum period");
    }

    function testSetSalePeriodWithExactMinPeriod() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        
        vm.prank(user);
        dcaOutManager.setSalePeriod(0, schedule.scheduleId, MIN_SALE_PERIOD);
        
        IDcaOutManager.DcaOutSchedule memory updatedSchedule = dcaOutManager.getSchedule(user, 0);
        assertEq(updatedSchedule.salePeriod, MIN_SALE_PERIOD, "Should accept exact minimum period");
    }

    function testCannotCreateScheduleWithZeroDeposit() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__DepositAmountCantBeZero.selector));
        dcaOutManager.createDcaOutSchedule{value: 0}(SALE_AMOUNT, SALE_PERIOD);
    }

    function testCannotDepositRbtcWithZeroAmount() public {
        // Create a schedule first
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__DepositAmountCantBeZero.selector));
        dcaOutManager.depositRbtc{value: 0}(0, scheduleId);
    }
}
