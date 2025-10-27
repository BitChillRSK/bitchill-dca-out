// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DeployBase} from "./DeployBase.s.sol";
import {DcaOutManager} from "../src/DcaOutManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IFeeHandler} from "../src/interfaces/IFeeHandler.sol";
import {console2} from "forge-std/Test.sol";
import "./Constants.sol";

/**
 * @title DeployDcaOut
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Deployment script for DCA Out protocol
 */
contract DeployDcaOut is DeployBase {
    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function run() external returns (DcaOutManager, HelperConfig) {
        console2.log("==== DeployDcaOut.run() called ====");
        console2.log("Chain ID:", block.chainid);

        // Get network configuration
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        console2.log("Network Configuration:");
        console2.log("  DOC Token:", config.docTokenAddress);
        console2.log("  MoC Proxy:", config.mocProxyAddress);
        console2.log("  Fee Collector:", config.feeCollector);
        console2.log("  Owner:", config.owner);
        console2.log("  Swapper:", config.swapper);

        // Set up fee settings
        IFeeHandler.FeeSettings memory feeSettings = IFeeHandler.FeeSettings({
            minFeeRate: MIN_FEE_RATE,
            maxFeeRate: getMaxFeeRate(),
            feePurchaseLowerBound: FEE_PURCHASE_LOWER_BOUND,
            feePurchaseUpperBound: FEE_PURCHASE_UPPER_BOUND
        });

        console2.log("Fee Settings:");
        console2.log("  Min Fee Rate:", feeSettings.minFeeRate);
        console2.log("  Max Fee Rate:", feeSettings.maxFeeRate);
        console2.log("  Lower Bound:", feeSettings.feePurchaseLowerBound);
        console2.log("  Upper Bound:", feeSettings.feePurchaseUpperBound);

        vm.startBroadcast();

        // Choose parameters based on environment
        uint256 minSaleAmount;
        uint256 minSalePeriod;
        
        if (environment == Environment.TESTNET) {
            // Testing parameters for testnet (manual testing with fake money)
            minSaleAmount = MIN_SALE_AMOUNT_TESTNET;
            minSalePeriod = MIN_SALE_PERIOD_TESTNET;
            console2.log("Using TESTING parameters for testnet deployment");
        } else {
            // Production parameters for mainnet, local, and fork testing
            minSaleAmount = MIN_SALE_AMOUNT;
            minSalePeriod = MIN_SALE_PERIOD;
            console2.log("Using PRODUCTION parameters for", environment == Environment.MAINNET ? "mainnet" : environment == Environment.LOCAL ? "local" : "fork", "deployment");
        }

        // Deploy DcaOutManager
        DcaOutManager dcaOutManager = new DcaOutManager(
            config.docTokenAddress,
            config.mocProxyAddress,
            config.feeCollector,
            feeSettings,
            minSalePeriod,
            MAX_SCHEDULES_PER_USER,
            minSaleAmount,
            MOC_COMMISSION,
            config.swapper
        );

        console2.log("DcaOutManager deployed at:", address(dcaOutManager));

        // Transfer ownership to config owner
        console2.log("Live network deployment - transferring ownership to owner:", config.owner);
        dcaOutManager.transferOwnership(config.owner);
        
        // Grant DEFAULT_ADMIN_ROLE to owner for role management
        dcaOutManager.grantRole(dcaOutManager.DEFAULT_ADMIN_ROLE(), config.owner);
        console2.log("DEFAULT_ADMIN_ROLE granted to owner for role management");
        
        // Revoke DEFAULT_ADMIN_ROLE from deployer for maximum security
        dcaOutManager.revokeRole(dcaOutManager.DEFAULT_ADMIN_ROLE(), msg.sender);
        console2.log("DEFAULT_ADMIN_ROLE revoked from deployer for security");
        
        console2.log("Ownership transferred successfully");

        vm.stopBroadcast();

        console2.log("==== Deployment Complete ====");

        return (dcaOutManager, helperConfig);
    }

}

