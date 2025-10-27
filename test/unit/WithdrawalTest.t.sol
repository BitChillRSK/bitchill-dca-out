// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

/**
 * @title WithdrawalTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager withdrawal functions
 */
contract WithdrawalTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            DOC WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdrawDoc() public {
        // First create a schedule and execute a sale to get some DOC
        vm.startPrank(user);
        dcaOutManager.createDcaOutSchedule{value: 1 ether}(SALE_AMOUNT, SALE_PERIOD);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);
        vm.stopPrank();

        // Execute sale to get DOC
        vm.prank(swapper);
        dcaOutManager.sellRbtc(user, 0, schedule.scheduleId);

        uint256 docBalance = dcaOutManager.getUserDocBalance(user);
        assertTrue(docBalance > 0, "User should have DOC balance");
        
        vm.startPrank(user);
        dcaOutManager.withdrawDoc();
        vm.stopPrank();

        uint256 newBalance = dcaOutManager.getUserDocBalance(user);
        assertEq(newBalance, 0, "DOC balance should be zero after withdrawing");
    }

    function testCannotWithdrawDocWithZeroAmount() public {
        vm.startPrank(user);
        
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__NoDocToWithdraw.selector));
        dcaOutManager.withdrawDoc();
        
        vm.stopPrank();
    }
}
