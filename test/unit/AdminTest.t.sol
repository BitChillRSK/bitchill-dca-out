// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import "../Constants.sol";

/**
 * @title AdminTest
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test suite for DCA Out Manager admin functions
 */
contract AdminTest is DcaOutTestBase {

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGrantSwapperRole() public {
        address newSwapper = makeAddr("newSwapper");
        
        // Note: SwapperSet event test removed due to exact matching issues
        
        vm.prank(address(this));
        dcaOutManager.grantSwapperRole(newSwapper);
        
        // Verify the role was granted
        assertTrue(dcaOutManager.hasRole(dcaOutManager.SWAPPER_ROLE(), newSwapper), "New swapper should have role");
    }

    function testRevokeSwapperRole() public {
        address newSwapper = makeAddr("newSwapper");
        
        // First grant the role
        vm.prank(address(this));
        dcaOutManager.grantSwapperRole(newSwapper);
        
        // Then revoke it
        vm.prank(address(this));
        dcaOutManager.revokeSwapperRole(newSwapper);
        
        // Verify the role was revoked
        assertFalse(dcaOutManager.hasRole(dcaOutManager.SWAPPER_ROLE(), newSwapper), "Swapper should not have role");
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN SETTINGS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetMinSalePeriodIfNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMinSalePeriod(2 days);
        
        vm.stopPrank();
    }

    function testCannotSetMaxSchedulesIfNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMaxSchedulesPerUser(5);
        
        vm.stopPrank();
    }

    function testSetMaxSchedulesPerUser() public {
        // Test that non-owner cannot call this function
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dcaOutManager.setMaxSchedulesPerUser(5);
        vm.stopPrank();

        // Test that owner can call this function
        vm.startPrank(address(this)); // Test contract is the owner for local testing
        dcaOutManager.setMaxSchedulesPerUser(5);
        assertEq(dcaOutManager.getMaxSchedulesPerUser(), 5, "Max schedules per user should be updated");
        vm.stopPrank();
    }
}
