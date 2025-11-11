// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import "../Constants.sol";

/**
 * @title OnlyOwnerTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager owner functions
 */
contract OnlyOwnerTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGrantSwapperRole() public {
        address newSwapper = makeAddr("newSwapper");
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__SwapperSet(newSwapper);
        vm.prank(owner);
        dcaOutManager.grantSwapperRole(newSwapper);
        
        // Verify the role was granted
        assertTrue(dcaOutManager.hasRole(dcaOutManager.SWAPPER_ROLE(), newSwapper), "New swapper should have role");
    }

    function testRevokeSwapperRole() public {
        address newSwapper = makeAddr("newSwapper");
        
        // First grant the role
        vm.prank(owner);
        dcaOutManager.grantSwapperRole(newSwapper);
        
        // Then revoke it
        vm.prank(owner);
        dcaOutManager.revokeSwapperRole(newSwapper);
        
        // Verify the role was revoked
        assertFalse(dcaOutManager.hasRole(dcaOutManager.SWAPPER_ROLE(), newSwapper), "Swapper should not have role");
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER SETTINGS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetMinSalePeriod() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__MinSalePeriodSet(2 days);
        dcaOutManager.setMinSalePeriod(2 days);
        assertEq(dcaOutManager.getMinSalePeriod(), 2 days, "Min sale period should be updated");
    }

    function testCannotSetMinSalePeriodIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMinSalePeriod(2 days);
    }

    function testCannotSetMaxSchedulesIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMaxSchedulesPerUser(5);
    }

    function testSetMaxSchedulesPerUser() public {
        // Test that non-owner cannot call this function
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMaxSchedulesPerUser(5);

        // Test that owner can call this function
        vm.prank(owner);
        dcaOutManager.setMaxSchedulesPerUser(5);
        assertEq(dcaOutManager.getMaxSchedulesPerUser(), 5, "Max schedules per user should be updated");
    }

    function testSetMinSaleAmount() public {
        vm.prank(owner);
        uint256 newMinSaleAmount = 0.002 ether;
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__MinSaleAmountSet(newMinSaleAmount);
        dcaOutManager.setMinSaleAmount(newMinSaleAmount);
        
        assertEq(dcaOutManager.getMinSaleAmount(), newMinSaleAmount, "Min sale amount should be updated");
    }

    function testCannotSetMinSaleAmountIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMinSaleAmount(0.002 ether);
    }

    function testSetMocCommission() public {
        vm.prank(owner);
        uint256 newCommission = 2e15; // 0.2%
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__MocCommissionSet(newCommission);
        dcaOutManager.setMocCommission(newCommission);
        assertEq(dcaOutManager.getMocCommission(), newCommission, "MoC commission should be updated");
    }
 
    function testCannotSetMocCommissionIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMocCommission(2e15);
    }
}
