// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

// Test helper contract to access internal functions

contract OnlyMoCModifierTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    function testOnlyMoCModifierWorks() public {
        // Test that onlyMoC modifier actually works as intended
        // The onlyMoC modifier should allow only the MoC proxy to send rBTC to the contract
        
        uint256 initialBalance = address(dcaOutManager).balance;
        uint256 sendAmount = 1 ether;
        
        // Test 1: Sending rBTC from user should fail
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__NotMoC.selector, user));
        (bool success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertEq(address(dcaOutManager).balance, initialBalance, "Contract balance should not change");
        assertTrue(success); // Counterintuitive!! Foundry wraps the call after the expectRevert in a try-catch block making success true even though the call reverts
        vm.prank(user); // Let's assert this test with expectRevert and assertFalse(success) separately because of this
        (success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertFalse(success, "User addresses should not be able to send rBTC to contract");

        // Test 2: Sending rBTC from non-MoC address should fail
        address nonMoC = makeAddr("nonMoC");
        vm.deal(nonMoC, sendAmount);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__NotMoC.selector, nonMoC));
        vm.prank(nonMoC);
        (success, ) = address(dcaOutManager).call{value: sendAmount}("");
        assertEq(address(dcaOutManager).balance, initialBalance, "Contract balance should not change");
        assertTrue(success); // Counterintuitive!! Foundry wraps the call after the expectRevert in a try-catch block making success true even though the call reverts
        vm.prank(user); // Let's assert this test with expectRevert and assertFalse(success) separately because of this
        (success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertFalse(success, "User addresses should not be able to send rBTC to contract");

        // Test 3: MoC sending 0 value should succeed (onlyMoC modifier allows it)
        vm.prank(address(mocProxy));
        (success, ) = address(dcaOutManager).call{value: 0}("");
        assertTrue(success, "MoC proxy should be able to call receive() with 0 value");
        assertEq(address(dcaOutManager).balance, initialBalance, "Contract balance should not change with 0 value");

        // Test 4: MoC sending non-zero value should revert (indicates change was returned, commission mismatch)
        vm.deal(address(mocProxy), sendAmount);
        vm.expectRevert(abi.encodeWithSelector(IDcaOutManager.DcaOutManager__UnexpectedChangeReturned.selector, sendAmount));
        vm.prank(address(mocProxy));
        (success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertTrue(success); // Counterintuitive!! Foundry wraps the call after the expectRevert in a try-catch block making success true even though the call reverts
        vm.prank(address(mocProxy)); // Let's assert this test with expectRevert and assertFalse(success) separately because of this
        (success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertFalse(success, "MoC proxy should not be able to call receive() with non-zero value");
        // After expectRevert, the revert is caught so balance check happens
        assertEq(address(dcaOutManager).balance, initialBalance, "Contract balance should not change on revert");
    }
}
