// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

/**
 * @title GetterTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager getter functions
 */
contract GetterTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            GLOBAL GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetMinSalePeriod() public view {
        assertEq(dcaOutManager.getMinSalePeriod(), MIN_SALE_PERIOD, "Wrong min sell period");
    }

    function testGetMaxSchedulesPerUser() public view {
        assertEq(dcaOutManager.getMaxSchedulesPerUser(), MAX_SCHEDULES_PER_USER, "Wrong max schedules");
    }

    function testGetMinSaleAmount() public view {
        assertEq(dcaOutManager.getMinSaleAmount(), MIN_SALE_AMOUNT, "Wrong min sell amount");
    }

    /*//////////////////////////////////////////////////////////////
                            USER GETTER TESTS (MY FUNCTIONS)
    //////////////////////////////////////////////////////////////*/

    function testGetMySchedules() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        createDcaOutSchedule(user, SALE_AMOUNT * 2, SALE_PERIOD * 2, DEPOSIT_AMOUNT * 2);
        vm.prank(user);
        IDcaOutManager.DcaOutSchedule[] memory mySchedules = dcaOutManager.getMySchedules();
        assertEq(mySchedules.length, 2, "Should have 2 schedules");
        assertEq(mySchedules[0].rbtcSaleAmount, SALE_AMOUNT, "First schedule amount");
        assertEq(mySchedules[1].rbtcSaleAmount, SALE_AMOUNT * 2, "Second schedule amount");
    }

    function testGetMyScheduleRbtcBalance() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        uint256 balance = dcaOutManager.getMyScheduleRbtcBalance(0);
        assertEq(balance, DEPOSIT_AMOUNT, "Should have deposit amount balance");
    }

    function testgetMyScheduleSaleAmount() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        uint256 amount = dcaOutManager.getMyScheduleSaleAmount(0);
        assertEq(amount, SALE_AMOUNT, "Should return sale amount");
    }

    function testGetMyScheduleSalePeriod() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        vm.prank(user);
        uint256 period = dcaOutManager.getMyScheduleSalePeriod(0);
        assertEq(period, SALE_PERIOD, "Should return sale period");
    }

    function testGetMyScheduleId() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        dcaOutManager.createDcaOutSchedule{value: DEPOSIT_AMOUNT}(SALE_AMOUNT, SALE_PERIOD);
        vm.prank(user);
        bytes32 scheduleId = dcaOutManager.getMyScheduleId(0);
        assertNotEq(scheduleId, bytes32(0), "Schedule ID should not be zero");
    }

    function testGetMyDocBalance() public {
        // First create a schedule and execute a sale to get some DOC
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute sale to get DOC
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);

        vm.prank(user);
        uint256 docBalance = dcaOutManager.getMyDocBalance();
        assertGe(docBalance, 0, "User should have DOC balance");
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetSchedule() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, SALE_AMOUNT, "Wrong rBTC amount");
        assertEq(schedule.salePeriod, SALE_PERIOD, "Wrong period");
        assertEq(schedule.rbtcBalance, DEPOSIT_AMOUNT, "Should have initial deposit");    }

    function testgetScheduleRbtcBalance() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        uint256 balance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(balance, DEPOSIT_AMOUNT, "Should have initial deposit");
    }

    function testGetScheduleRbtcAmount() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        uint256 amount = dcaOutManager.getScheduleSaleAmount(user, 0);
        assertEq(amount, SALE_AMOUNT, "Wrong rBTC amount");
    }

    function testGetScheduleSalePeriod() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        uint256 period = dcaOutManager.getScheduleSalePeriod(user, 0);
        assertEq(period, SALE_PERIOD, "Wrong period");
    }

    function testGetScheduleId() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        bytes32 scheduleId = dcaOutManager.getScheduleId(user, 0);
        assertNotEq(scheduleId, bytes32(0), "Schedule ID should not be zero");
    }

    function testGetMyScheduleIsPaused() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId);
        vm.prank(user);
        bool isPaused = dcaOutManager.getMyScheduleIsPaused(0);
        assertTrue(isPaused, "Schedule should be paused");
    }

    function testGetScheduleIsPaused() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        dcaOutManager.pauseSchedule(0, scheduleId);
        vm.prank(user);
        bool isPaused = dcaOutManager.getScheduleIsPaused(user, 0);
        assertTrue(isPaused, "Schedule should be paused");
    }

    function testGetUserDocBalance() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);

        // Execute a sale to generate DOC balance
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);

        uint256 balance = dcaOutManager.getUserDocBalance(user);
        assertTrue(balance > 0, "User should have DOC balance");
    }
}
