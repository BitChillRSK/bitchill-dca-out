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
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, 1 ether);
        
        // Execute the sale
        executeSale(user, 0, scheduleId);
    }

    function testCannotExecuteMintIfNotSwapper() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, 1 ether);

        // Use a non-swapper address
        address nonSwapper = makeAddr("nonSwapper");
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__UnauthorizedSwapper.selector, nonSwapper));
        vm.prank(nonSwapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testCannotExecuteMintIfNotReady() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, 1 ether);

        // Execute first sale
        executeSale(user, 0, scheduleId);

        // Try to execute again immediately (should fail)
        // Note: We can't predict exact timestamps on mainnet fork, so we just check the error type
        vm.expectRevert();
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, scheduleId);
    }

    function testCannotUpdateScheduleWithSaleAmountTooHigh() public {
        bytes32 scheduleId = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, 1 ether);

        // Execute first sale to reduce balance
        executeSale(user, 0, scheduleId);

        // Get the actual balance after the first sale (may include change)
        uint256 actualBalance = dcaOutManager.getScheduleRbtcBalance(user, 0);
        
        // Try to update schedule to sell more than half of available balance
        uint256 tooHighAmount = (actualBalance / 2) + 1; // More than half
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__SaleAmountTooHighForPeriodicSales.selector, tooHighAmount, actualBalance, actualBalance / 2));
        vm.startPrank(user);
        dcaOutManager.updateDcaOutSchedule(0, scheduleId, tooHighAmount, SALE_PERIOD);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            BATCH EXECUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testBatchExecuteMint() public {
        // User 1 creates schedule
        bytes32 scheduleId1 = createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, 1 ether);

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
                            UNCHECKED REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertSellRbtcWithArrayIndexOutOfBounds() public {
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
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
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(0.1 ether, SALE_PERIOD);
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
