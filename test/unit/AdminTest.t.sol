// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutTestBase} from "./DcaOutTestBase.t.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
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
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__MinSalePeriodSet(2 days);
        dcaOutManager.setMinSalePeriod(2 days);
        
        vm.stopPrank();
        assertEq(dcaOutManager.getMinSalePeriod(), 2 days, "Min sale period should be updated");
    }

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
        vm.startPrank(owner);
        dcaOutManager.setMaxSchedulesPerUser(5);
        assertEq(dcaOutManager.getMaxSchedulesPerUser(), 5, "Max schedules per user should be updated");
        vm.stopPrank();
    }
}
