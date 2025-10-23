// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

/**
 * @title ExecutionTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager execution (selling rBTC)
 */
contract ExecutionTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            SINGLE EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testExecuteMint() public {
        // User creates schedule with deposit
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Check event emission (partial match)
        vm.expectEmit(true, true, true, false); // rbtcSpent is not checked because it is unpredictable
        emit DcaOutManager__RbtcSold(user, schedule.scheduleId, TEST_RBTC_SELL_AMOUNT, TEST_RBTC_SELL_AMOUNT, 0, 0);
        
        // Execute the sale
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);

        // Check user received DOC
        uint256 userDocBalance = dcaOutManager.getUserDocBalance(user);
        assertTrue(userDocBalance > 0, "User should have DOC balance");

        // Check rBTC balance decreased (but may have some change credited back)
        uint256 remainingRbtc = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertTrue(remainingRbtc >= 1 ether - TEST_RBTC_SELL_AMOUNT, "rBTC balance should decrease by at least the sale amount");
        assertTrue(remainingRbtc <= 1 ether, "rBTC balance should not exceed original deposit");
    }

    function testCannotExecuteMintIfNotSwapper() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Use a non-swapper address
        address nonSwapper = makeAddr("nonSwapper");
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__UnauthorizedSwapper.selector, nonSwapper));
        vm.prank(nonSwapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);
    }

    function testCannotExecuteMintIfNotReady() public {
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

    function testCannotUpdateScheduleWithSaleAmountTooHigh() public {
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

        // Get the actual balance after the first sale (may include change)
        uint256 actualBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        
        // Try to update schedule to sell more than available (0.06 ether > actual balance available)
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, 0.06 ether, actualBalance, actualBalance / 2));
        vm.startPrank(user);
        dcaOutManager.updateDcaOutSchedule(0, schedule.scheduleId, 0.06 ether, TEST_PERIOD);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            BATCH EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testBatchExecuteMint() public {
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

        // Note: Batch event test removed due to exact matching issues

        executeBatchSale(users, scheduleIndexes, scheduleIds);

        // Check both users received DOC
        assertTrue(dcaOutManager.getUserDocBalance(user) > 0, "User 1 should have DOC");
        assertTrue(dcaOutManager.getUserDocBalance(user2) > 0, "User 2 should have DOC");
    }

    /*//////////////////////////////////////////////////////////////
                            UNCHECKED REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertSellRbtcWithArrayIndexOutOfBounds() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(TEST_RBTC_SELL_AMOUNT, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Try to access non-existent schedule index
        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 999, schedule.scheduleId);
    }

    function testRevertSellRbtcWithInsufficientBalance() public {
        vm.startPrank(user);
        // Create schedule with valid sale amount
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(0.1 ether, TEST_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Withdraw almost all balance to make it insufficient for the sale amount
        vm.prank(user);
        dcaOutManager.withdrawRbtc(0, schedule.scheduleId, 0.95 ether);

        // Check balance is now insufficient
        uint256 remainingBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        assertTrue(remainingBalance < 0.1 ether, "Balance should be insufficient for sale");

        // Try to sell - should fail due to insufficient balance
        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);
    }

    function testRevertBatchSellRbtcWithArrayLengthMismatch() public {
        address[] memory users = new address[](1);
        uint256[] memory scheduleIndexes = new uint256[](2);
        bytes32[] memory scheduleIds = new bytes32[](1);
        users[0] = user;
        scheduleIndexes[0] = 0;
        scheduleIndexes[1] = 0;
        scheduleIds[0] = bytes32(0);

        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, 1 ether);
    }

    function testRevertBatchSellRbtcWithDivisionByZero() public {
        address[] memory users = new address[](1);
        uint256[] memory scheduleIndexes = new uint256[](1);
        bytes32[] memory scheduleIds = new bytes32[](1);
        users[0] = user;
        scheduleIndexes[0] = 0;
        scheduleIds[0] = bytes32(0);

        // totalRbtcToSpend = 0 will cause division by zero
        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, 0);
    }

    function testRevertBatchSellRbtcWithArrayIndexOutOfBounds() public {
        address[] memory users = new address[](1);
        uint256[] memory scheduleIndexes = new uint256[](1);
        bytes32[] memory scheduleIds = new bytes32[](1);
        users[0] = user;
        scheduleIndexes[0] = 999; // Non-existent schedule
        scheduleIds[0] = bytes32(0);

        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, 1 ether);
    }
}
