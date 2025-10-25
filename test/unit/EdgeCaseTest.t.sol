// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {DcaOutManager} from "../../src/DcaOutManager.sol";
import {IFeeHandler} from "../../src/interfaces/IFeeHandler.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockDoc} from "../mocks/MockDoc.sol";
import {MockMocProxy} from "../mocks/MockMocProxy.sol";
import {DcaOutManagerTestHelper} from "./DcaOutManagerTestHelper.sol";

// Test helper contract to access internal functions

contract EdgeCaseTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
        
        // Deploy test helper with same parameters as main contract
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        IFeeHandler.FeeSettings memory feeSettings = IFeeHandler.FeeSettings({
            minFeeRate: 100,
            maxFeeRate: 200,
            feePurchaseLowerBound: 1000 ether,
            feePurchaseUpperBound: 100000 ether
        });
        
        testHelper = new DcaOutManagerTestHelper(
            config.docTokenAddress,
            config.mocProxyAddress,
            config.feeCollector,
            feeSettings,
            1 days, // minSalePeriod
            10, // maxSchedulesPerUser
            0.01 ether, // minSaleAmount
            100, // mocCommission
            swapper
        );
    }

    function testCalculateFeeWithZeroDocAmount() public view {
        // Test _calculateFee with zero DOC amount
        uint256 fee = testHelper.calculateFee(0);
        assertEq(fee, 0, "Fee should be zero for zero DOC amount");
    }

    function testCalculateFeeWithAmountBelowLowerBound() public view {
        // Test _calculateFee with amount below lower bound
        uint256 smallAmount = 1 ether; // Below the 1,000 DOC lower bound
        uint256 fee = testHelper.calculateFee(smallAmount);
        assertTrue(fee > 0, "Fee should be greater than zero for amounts below lower bound (max fee rate applied)");
    }

    function testCalculateFeeWithAmountAtLowerBound() public view {
        // Test _calculateFee with amount exactly at lower bound
        uint256 lowerBound = 1000 ether; // Exactly at the lower bound
        uint256 fee = testHelper.calculateFee(lowerBound);
        assertTrue(fee > 0, "Fee should be greater than zero at lower bound");
    }

    function testCalculateFeeWithAmountAboveUpperBound() public view {
        // Test _calculateFee with amount above upper bound
        uint256 upperBound = 100000 ether; // At the upper bound
        uint256 fee = testHelper.calculateFee(upperBound);
        assertTrue(fee > 0, "Fee should be calculated for amounts at upper bound");
    }

    function testCalculateFeeAndNetAmountsWithZeroAmount() public view {
        // Test _calculateFeeAndNetAmounts with zero amount
        (uint256 fee, uint256 netAmount) = testHelper.calculateFeeAndNetAmounts(0);
        assertEq(fee, 0, "Fee should be zero for zero amount");
        assertEq(netAmount, 0, "Net amount should be zero for zero amount");
    }

    function testCalculateFeeAndNetAmountsWithSmallAmount() public view {
        // Test _calculateFeeAndNetAmounts with small amount
        uint256 smallAmount = 1 ether;
        (uint256 fee, uint256 netAmount) = testHelper.calculateFeeAndNetAmounts(smallAmount);
        assertTrue(fee > 0, "Fee should be greater than zero for small amount (max fee rate applied)");
        assertEq(netAmount, smallAmount - fee, "Net amount should be original amount minus fee");
    }

    function testCalculateFeeAndNetAmountsWithLargeAmount() public view {
        // Test _calculateFeeAndNetAmounts with large amount
        uint256 largeAmount = 200000 ether; // Above upper bound
        (uint256 fee, uint256 netAmount) = testHelper.calculateFeeAndNetAmounts(largeAmount);
        assertTrue(fee > 0, "Fee should be greater than zero for large amount");
        assertEq(netAmount, largeAmount - fee, "Net amount should be original amount minus fee");
    }

    function testOnlyMoCModifierWorks() public {
        // Test that onlyMoC modifier actually works as intended
        // The onlyMoC modifier should allow only the MoC proxy to send rBTC to the contract
        
        uint256 initialBalance = address(dcaOutManager).balance;
        uint256 sendAmount = 1 ether;
        
        // Test 1: Sending rBTC from MoC proxy should succeed
        vm.deal(address(mocProxy), sendAmount);
        vm.prank(address(mocProxy));
        (bool success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertTrue(success, "MoC proxy should be able to send rBTC to contract");
        assertEq(address(dcaOutManager).balance, initialBalance + sendAmount, "Contract balance should increase");
        
        // Test 2: Sending rBTC from any other address should fail
        address randomUser = makeAddr("randomUser");
        vm.deal(randomUser, sendAmount);
        vm.prank(randomUser);
        (success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertFalse(success, "Non-MoC addresses should not be able to send rBTC to contract");
        assertEq(address(dcaOutManager).balance, initialBalance + sendAmount, "Contract balance should not change");
        
        // Test 3: Sending rBTC from user should fail
        vm.prank(user);
        (success,) = address(dcaOutManager).call{value: sendAmount}("");
        assertFalse(success, "User addresses should not be able to send rBTC to contract");
        assertEq(address(dcaOutManager).balance, initialBalance + sendAmount, "Contract balance should not change");
    }

    function testFeeCalculationEdgeCases() public view {
        // Test various edge cases for fee calculation
        
        // Test with minimum possible amount
        uint256 minAmount = 1 wei;
        uint256 fee = testHelper.calculateFee(minAmount);
        assertEq(fee, 0, "Fee should be zero for minimum amount");
        
        // Test with amount just below lower bound
        uint256 justBelowBound = 999 ether;
        fee = testHelper.calculateFee(justBelowBound);
        assertTrue(fee > 0, "Fee should be greater than zero for amount just below lower bound (max fee rate applied)");
        
        // Test with amount just above lower bound
        uint256 justAboveBound = 1001 ether;
        fee = testHelper.calculateFee(justAboveBound);
        assertTrue(fee > 0, "Fee should be greater than zero for amount just above lower bound");
    }

    function testFeeCalculationWithExactBounds() public view {
        // Test fee calculation with exact boundary values
        
        // Test with exact lower bound
        uint256 lowerBound = 1000 ether;
        uint256 fee = testHelper.calculateFee(lowerBound);
        assertTrue(fee > 0, "Fee should be greater than zero at exact lower bound");
        
        // Test with exact upper bound
        uint256 upperBound = 100000 ether; // Upper bound
        fee = testHelper.calculateFee(upperBound);
        assertTrue(fee > 0, "Fee should be greater than zero at exact upper bound");
    }

    function testFeeCalculationProgression() public view {
        // Test that fee calculation follows expected progression
        
        uint256 baseAmount = 1000 ether;
        uint256 baseFee = testHelper.calculateFee(baseAmount);
        
        // Test with 2x amount
        uint256 doubleAmount = baseAmount * 2;
        uint256 doubleFee = testHelper.calculateFee(doubleAmount);
        
        // Fee should increase with amount
        assertTrue(doubleFee > baseFee, "Fee should increase with amount");
        
        // Test with 10x amount
        uint256 tenXAmount = baseAmount * 10;
        uint256 tenXFee = testHelper.calculateFee(tenXAmount);
        
        // Fee should continue to increase
        assertTrue(tenXFee > doubleFee, "Fee should continue to increase with larger amounts");
    }

    function testFeeCalculationConsistency() public view {
        // Test that fee calculation is consistent
        
        uint256 amount = 150000 ether;
        uint256 fee1 = testHelper.calculateFee(amount);
        uint256 fee2 = testHelper.calculateFee(amount);
        
        assertEq(fee1, fee2, "Fee calculation should be consistent");
        
        // Test with different amounts
        uint256 amount2 = 200000 ether;
        uint256 fee3 = testHelper.calculateFee(amount2);
        
        assertTrue(fee3 > fee1, "Fee should be higher for larger amounts");
    }
}
