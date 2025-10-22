// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import "./Constants.sol";

contract DeployBase is Script {
    enum Environment {
        LOCAL,
        FORK,
        TESTNET,
        MAINNET
    }

    struct DeploymentConfig {
        address owner;
        address feeCollector;
        address admin;
        Environment environment;
    }

    mapping(Environment => address) internal adminAddresses;
    mapping(Environment => address) internal feeCollectorAddresses;
    Environment environment;

    constructor() {
        // Admin addresses
        adminAddresses[Environment.LOCAL] = makeAddr(OWNER_STRING);
        adminAddresses[Environment.FORK] = makeAddr(OWNER_STRING);
        adminAddresses[Environment.TESTNET] = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;
        adminAddresses[Environment.MAINNET] = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;

        // Fee collector addresses
        feeCollectorAddresses[Environment.LOCAL] = makeAddr(FEE_COLLECTOR_STRING);
        feeCollectorAddresses[Environment.FORK] = makeAddr(FEE_COLLECTOR_STRING);
        feeCollectorAddresses[Environment.TESTNET] = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;
        feeCollectorAddresses[Environment.MAINNET] = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;

        environment = getEnvironment();

        console.log("Environment:", uint256(environment)); // 0=LOCAL, 1=FORK, 2=TESTNET, 3=MAINNET
        console.log("Chain ID:", block.chainid);
    }

    function getFeeCollector(Environment deploymentEnvironment) internal view returns (address) {
        return feeCollectorAddresses[deploymentEnvironment];
    }

    function getEnvironment() internal view returns (Environment) {
        bool isRealDeployment = vm.envOr("REAL_DEPLOYMENT", false);

        if (isRealDeployment) {
            if (block.chainid == RSK_TESTNET_CHAIN_ID) return Environment.TESTNET;
            if (block.chainid == RSK_MAINNET_CHAIN_ID) return Environment.MAINNET;
            revert("Unsupported chain for deployment");
        }

        if (block.chainid == ANVIL_CHAIN_ID) return Environment.LOCAL;
        if (isFork()) return Environment.FORK;
        revert("Unsupported chain");
    }

    /**
     * @notice Get the appropriate maximum fee rate based on deployment type
     * @return maxFeeRate The maximum fee rate to use (production has flat 1% fee, test has variable 2% max fee)
     */
    function getMaxFeeRate() public view returns (uint256 maxFeeRate) {
        bool isRealDeployment = vm.envOr("REAL_DEPLOYMENT", false);
        return isRealDeployment ? MAX_FEE_RATE_PRODUCTION : MAX_FEE_RATE_TEST;
    }
}
