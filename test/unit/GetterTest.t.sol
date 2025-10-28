// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
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
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        dcaOutManager.createDcaOutSchedule{value: 2 ether}(SALE_AMOUNT * 2, SALE_PERIOD * 2);
        
        IDcaOutManager.DcaOutSchedule[] memory mySchedules = dcaOutManager.getMySchedules();
        assertEq(mySchedules.length, 2, "Should have 2 schedules");
        assertEq(mySchedules[0].rbtcSaleAmount, SALE_AMOUNT, "First schedule amount");
        assertEq(mySchedules[1].rbtcSaleAmount, SALE_AMOUNT * 2, "Second schedule amount");
        vm.stopPrank();
    }

    function testGetMyScheduleRbtcBalance() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        
        uint256 balance = dcaOutManager.getMyScheduleRbtcBalance(0);
        assertEq(balance, 1 ether, "Should have 1 ether balance");
        vm.stopPrank();
    }

    function testgetMyScheduleSaleAmount() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        
        uint256 amount = dcaOutManager.getMyScheduleSaleAmount(0);
        assertEq(amount, SALE_AMOUNT, "Should return sale amount");
        vm.stopPrank();
    }

    function testGetMyScheduleSalePeriod() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        
        uint256 period = dcaOutManager.getMyScheduleSalePeriod(0);
        assertEq(period, SALE_PERIOD, "Should return sale period");
        vm.stopPrank();
    }

    function testGetMyScheduleId() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        
        bytes32 scheduleId = dcaOutManager.getMyScheduleId(0);
        assertNotEq(scheduleId, bytes32(0), "Schedule ID should not be zero");
        vm.stopPrank();
    }

    function testGetMyDocBalance() public {
        // First create a schedule and execute a sale to get some DOC
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Execute sale to get DOC
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);

        vm.startPrank(user);
        uint256 docBalance = dcaOutManager.getMyDocBalance();
        assertTrue(docBalance > 0, "User should have DOC balance");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetSchedule() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        vm.stopPrank();

        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        assertEq(schedule.rbtcSaleAmount, SALE_AMOUNT, "Wrong rBTC amount");
        assertEq(schedule.salePeriod, SALE_PERIOD, "Wrong period");
        assertEq(schedule.rbtcBalance, 1 ether, "Should have initial deposit");
    }

    function testgetScheduleRbtcBalance() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        vm.stopPrank();

        uint256 balance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertEq(balance, 1 ether, "Should have initial deposit");
    }

    function testGetScheduleRbtcAmount() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        vm.stopPrank();

        uint256 amount = dcaOutManager.getScheduleSaleAmount(user, 0);
        assertEq(amount, SALE_AMOUNT, "Wrong rBTC amount");
    }

    function testGetScheduleSalePeriod() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        vm.stopPrank();

        uint256 period = dcaOutManager.getScheduleSalePeriod(user, 0);
        assertEq(period, SALE_PERIOD, "Wrong period");
    }

    function testGetScheduleId() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        vm.stopPrank();

        bytes32 scheduleId = dcaOutManager.getScheduleId(user, 0);
        assertNotEq(scheduleId, bytes32(0), "Schedule ID should not be zero");
    }

    function testGetUserDocBalance() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        vm.stopPrank();

        // Execute a sale to generate DOC balance
        vm.startPrank(swapper);
        dcaOutManager.sellRbtc(user, 0, dcaOutManager.getScheduleId(user, 0));
        vm.stopPrank();

        uint256 balance = dcaOutManager.getUserDocBalance(user);
        assertTrue(balance > 0, "User should have DOC balance");
    }
}
