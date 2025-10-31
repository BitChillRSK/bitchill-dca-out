// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IFeeHandler} from "../../src/interfaces/IFeeHandler.sol";
import "../Constants.sol";

/**
 * @title FeeHandlerTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager fee handling
 */
contract FeeHandlerTest is DcaOutTestBase {

    event FeeHandler__MinFeeRateSet(uint256 minFeeRate);
    event FeeHandler__MaxFeeRateSet(uint256 maxFeeRate);
    event FeeHandler__PurchaseLowerBoundSet(uint256 feePurchaseLowerBound);
    event FeeHandler__PurchaseUpperBoundSet(uint256 feePurchaseUpperBound);
    event FeeHandler__FeeCollectorAddressSet(address feeCollector);

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            FEE GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetFeeParameters() public view {
        assertEq(dcaOutManager.getMinFeeRate(), 100, "Min fee rate should be 100 basis points");
        assertEq(dcaOutManager.getMaxFeeRate(), 200, "Max fee rate should be 200 basis points");
        assertEq(dcaOutManager.getFeePurchaseLowerBound(), 1000e18, "Lower bound should be 1000 DOC");
        assertEq(dcaOutManager.getFeePurchaseUpperBound(), 100000e18, "Upper bound should be 100000 DOC");
        // Check that fee collector is set (address may vary)
        assertTrue(dcaOutManager.getFeeCollectorAddress() != address(0), "Fee collector should be set");
    }

    /*//////////////////////////////////////////////////////////////
                            FEE SETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetFeeRateParams() public {
        uint256 newMinRate = 25;
        uint256 newMaxRate = 75;
        uint256 newLowerBound = 2000e18;
        uint256 newUpperBound = 8000e18;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__MinFeeRateSet(newMinRate);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__MaxFeeRateSet(newMaxRate);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__PurchaseLowerBoundSet(newLowerBound);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__PurchaseUpperBoundSet(newUpperBound);
        dcaOutManager.setFeeRateParams(newMinRate, newMaxRate, newLowerBound, newUpperBound);
        
        assertEq(dcaOutManager.getMinFeeRate(), newMinRate, "Min fee rate should be updated");
        assertEq(dcaOutManager.getMaxFeeRate(), newMaxRate, "Max fee rate should be updated");
        assertEq(dcaOutManager.getFeePurchaseLowerBound(), newLowerBound, "Lower bound should be updated");
        assertEq(dcaOutManager.getFeePurchaseUpperBound(), newUpperBound, "Upper bound should be updated");
    }

    function testSetMinFeeRate() public {
        uint256 newMinRate = 30;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__MinFeeRateSet(newMinRate);
        dcaOutManager.setMinFeeRate(newMinRate);
        
        assertEq(dcaOutManager.getMinFeeRate(), newMinRate, "Min fee rate should be updated");
    }

    function testSetMaxFeeRate() public {
        uint256 newMaxRate = 80;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__MaxFeeRateSet(newMaxRate);
        dcaOutManager.setMaxFeeRate(newMaxRate);
        
        assertEq(dcaOutManager.getMaxFeeRate(), newMaxRate, "Max fee rate should be updated");
    }

    function testSetPurchaseLowerBound() public {
        uint256 newLowerBound = 1500e18;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__PurchaseLowerBoundSet(newLowerBound);
        dcaOutManager.setPurchaseLowerBound(newLowerBound);
        
        assertEq(dcaOutManager.getFeePurchaseLowerBound(), newLowerBound, "Lower bound should be updated");
    }

    function testSetPurchaseUpperBound() public {
        uint256 newUpperBound = 12000e18;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__PurchaseUpperBoundSet(newUpperBound);
        dcaOutManager.setPurchaseUpperBound(newUpperBound);
        
        assertEq(dcaOutManager.getFeePurchaseUpperBound(), newUpperBound, "Upper bound should be updated");
    }

    function testSetFeeCollectorAddress() public {
        address newFeeCollector = makeAddr("newFeeCollector");
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeeHandler__FeeCollectorAddressSet(newFeeCollector);
        dcaOutManager.setFeeCollectorAddress(newFeeCollector);
        
        assertEq(dcaOutManager.getFeeCollectorAddress(), newFeeCollector, "Fee collector should be updated");
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetFeeRateParamsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setFeeRateParams(25, 75, 2000e18, 8000e18);
    }

    function testCannotSetMinFeeRateIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMinFeeRate(30);
    }

    function testCannotSetMaxFeeRateIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMaxFeeRate(80);
    }

    function testCannotSetPurchaseLowerBoundIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setPurchaseLowerBound(1500e18);
    }

    function testCannotSetPurchaseUpperBoundIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setPurchaseUpperBound(12000e18);
    }

    function testCannotSetFeeCollectorIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setFeeCollectorAddress(makeAddr("newCollector"));
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION ERROR TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetFeeRateParamsWithMinHigherThanMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IFeeHandler.FeeHandler__MinFeeRateCannotBeHigherThanMax.selector));
        dcaOutManager.setFeeRateParams(200, 100, 1000, 2000); // min > max
    }

    function testCannotSetFeeRateParamsWithLowerBoundHigherThanUpperBound() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IFeeHandler.FeeHandler__FeeLowerBoundCAnnotBeHigherThanUpperBound.selector));
        dcaOutManager.setFeeRateParams(100, 200, 2000, 1000); // lower > upper
    }

    /*//////////////////////////////////////////////////////////////
                            FEE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCalculateFeeWithZeroDocAmount() public view {
        uint256 fee = testHelper.calculateFee(0);
        assertEq(fee, 0, "Fee should be zero for zero DOC amount");
    }

    function testCalculateFeeWithAmountBelowLowerBound() public view {
        uint256 smallAmount = 1 ether; // Below the 1,000 DOC lower bound
        uint256 fee = testHelper.calculateFee(smallAmount);
        assertEq(fee, smallAmount * MAX_FEE_RATE / 10_000);
    }

    function testCalculateFeeWithAmountAtLowerBound() public view {
        uint256 lowerBound = 1000 ether; // Exactly at the lower bound
        uint256 fee = testHelper.calculateFee(lowerBound);
        assertEq(fee, lowerBound * MAX_FEE_RATE / 10_000);
    }

    function testCalculateFeeWithAmountAtUpperBound() public view {
        uint256 upperBound = 100000 ether; // At the upper bound
        uint256 fee = testHelper.calculateFee(upperBound);
        assertEq(fee, upperBound * MIN_FEE_RATE / 10_000);
    }

    function testCalculateFeeWithAmountAboveUpperBound() public view {
        uint256 aboveUpperBound = 100001 ether; // Above the upper bound
        uint256 fee = testHelper.calculateFee(aboveUpperBound);
        assertEq(fee, aboveUpperBound * MIN_FEE_RATE / 10_000);
    }

    function testFeeCalculationProgression() public view {
        uint256 baseAmount = 1000 ether;
        uint256 baseFee = testHelper.calculateFee(baseAmount);
        uint256 baseFeeRate = (baseFee * 1e18) / baseAmount; // Fee rate in basis points
        
        // Test with 2x amount
        uint256 doubleAmount = baseAmount * 2;
        uint256 doubleFee = testHelper.calculateFee(doubleAmount);
        uint256 doubleFeeRate = (doubleFee * 1e18) / doubleAmount;
        
        // Fee rate should decrease as amount increases (progressive structure)
        assertTrue(doubleFeeRate < baseFeeRate, "Fee rate should decrease with larger amounts");
        
        // Test with 10x amount
        uint256 tenXAmount = baseAmount * 10;
        uint256 tenXFee = testHelper.calculateFee(tenXAmount);
        uint256 tenXFeeRate = (tenXFee * 1e18) / tenXAmount;
        
        // Fee rate should continue to decrease
        assertTrue(tenXFeeRate < doubleFeeRate, "Fee rate should continue to decrease with larger amounts");
        
        // Test with 100x amount
        uint256 hundredXAmount = baseAmount * 100;
        uint256 hundredXFee = testHelper.calculateFee(hundredXAmount);
        uint256 hundredXFeeRate = (hundredXFee * 1e18) / hundredXAmount;
        
        // Fee rate should be lowest for largest amounts
        assertTrue(hundredXFeeRate < tenXFeeRate, "Fee rate should be lowest for largest amounts");
    }
}
