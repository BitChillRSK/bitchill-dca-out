// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {DeployDcaOut} from "./DeployDcaOut.s.sol";
import {DcaOutManager} from "../src/DcaOutManager.sol";

/**
 * @title DeployAndSeedSchedules
 * @notice Deploys DcaOutManager to Rootstock testnet and seeds two schedules per funded account
 */
contract DeployAndSeedSchedules is Script {
    struct ScheduleConfig {
        uint256 deposit;
        uint256 saleAmount;
        uint256 salePeriod;
    }

    function run() external {
        console2.log("==== DeployAndSeedSchedules.run() ====");
        if(block.chainid != RSK_TESTNET_CHAIN_ID) {
            revert("This script is only for Rootstock Testnet");
        }

        // Get private keys from environment variables
        // Note: Variables must be exported in shell or sourced from .env file
        // Example: export PRIVATE_KEY=0x... && export PRIVATE_KEY2=0x...
        // Or: source .env (if .env file exports the variables)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 secondKey = vm.envUint("PRIVATE_KEY2");

        // Deploy manager using existing deployment flow
        DeployDcaOut deployScript = new DeployDcaOut();
        (DcaOutManager manager,) = deployScript.run();
        console2.log("DcaOutManager deployed at:", address(manager));

        // Seed schedules for both accounts
        _seedSchedules(
            manager,
            deployerKey,
            [
                ScheduleConfig({deposit: 0.0002 ether, saleAmount: 0.0001 ether, salePeriod: 10}),
                ScheduleConfig({deposit: 0.0003 ether, saleAmount: 0.00015 ether, salePeriod: 40})
            ]
        );

        _seedSchedules(
            manager,
            secondKey,
            [
                ScheduleConfig({deposit: 0.00025 ether, saleAmount: 0.000125 ether, salePeriod: 20}),
                ScheduleConfig({deposit: 0.0004 ether, saleAmount: 0.0002 ether, salePeriod: 30})
            ]
        );

        console2.log("==== DeployAndSeedSchedules complete ====");
    }

    function _seedSchedules(
        DcaOutManager manager,
        uint256 privateKey,
        ScheduleConfig[2] memory configs
    ) internal {
        address user = vm.addr(privateKey);
        console2.log("Seeding schedules for:", user);

        vm.startBroadcast(privateKey);
        for (uint256 i; i < configs.length; i++) {
            ScheduleConfig memory config = configs[i];
            console2.log("  Creating schedule index:", i);
            console2.log("    deposit (wei):", config.deposit);
            console2.log("    saleAmount (wei):", config.saleAmount);
            console2.log("    salePeriod (seconds):", config.salePeriod);
            manager.createDcaOutSchedule{value: config.deposit}(config.saleAmount, config.salePeriod);

            uint256 scheduleIndex = manager.getSchedulesCount(user) - 1;
            bytes32 scheduleId = manager.getScheduleId(user, scheduleIndex);
            console2.log("    Created schedule index:", scheduleIndex);
            console2.log("    Schedule ID:");
            console2.logBytes32(scheduleId);
        }
        vm.stopBroadcast();
    }
}

