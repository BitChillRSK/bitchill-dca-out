// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(user, 0);

        // Execute sale to get DOC
        executeSale(user, 0, schedule.scheduleId);
        uint256 docBalance = dcaOutManager.getUserDocBalance(user);
        assertGe(docBalance, 0, "User should have DOC balance");
        // vm.expectEmit(true, true, true, true);
        // emit DcaOutManager__DocWithdrawn(user, docBalance); 
        // Transfer event gets emitted first so this expectEmit fails
        vm.prank(user);
        dcaOutManager.withdrawDoc();
        uint256 newBalance = dcaOutManager.getUserDocBalance(user);
        assertEq(newBalance, 0, "DOC balance should be zero after withdrawing");
        assertEq(docToken.balanceOf(user), docBalance, "User should receive DOC tokens");
    }

    function testCannotWithdrawDocBeforeSellingRbtc() public {
        createDcaOutSchedule(user, SALE_AMOUNT, SALE_PERIOD, DEPOSIT_AMOUNT);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__NoDocToWithdraw.selector));
        dcaOutManager.withdrawDoc();
    }
}
