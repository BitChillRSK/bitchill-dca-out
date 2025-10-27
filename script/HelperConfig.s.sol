// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {MockDoc} from "../test/mocks/MockDoc.sol";
import {MockMocProxy} from "../test/mocks/MockMocProxy.sol";
import {MockMocOracle} from "../test/mocks/MockMocOracle.sol";
import "./Constants.sol";

/**
 * @title HelperConfig
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Configuration helper for deploying across different networks
 */
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct NetworkConfig {
        address docTokenAddress;
        address mocProxyAddress;
        address mocOracleAddress;
        address feeCollector;
        address owner;
        address swapper;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    NetworkConfig public activeNetworkConfig;

    // Mock addresses for local testing
    address public mockDocToken;
    address public mockMocProxy;
    address public mockMocOracle;
    
    // Real oracle addresses for fork testing
    address constant MOC_ORACLE_MAINNET = 0xe2927A0620b82A66D67F678FC9b826B0E01B1bFD;
    address constant MOC_ORACLE_TESTNET = 0xbffBD993FF1d229B0FfE55668F2009d20d4F7C5f;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event HelperConfig__CreatedMockDoc(address docToken);
    event HelperConfig__CreatedMockMocProxy(address mocProxy);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        if (block.chainid == RSK_MAINNET_CHAIN_ID) {
            activeNetworkConfig = getRootstockMainnetConfig();
        } else if (block.chainid == RSK_TESTNET_CHAIN_ID) {
            activeNetworkConfig = getRootstockTestnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        NETWORK CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get Rootstock mainnet configuration
     * @return RootstockMainnetNetworkConfig Network configuration
     */
    function getRootstockMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            docTokenAddress: DOC_TOKEN_MAINNET,
            mocProxyAddress: MOC_PROXY_MAINNET,
            mocOracleAddress: MOC_ORACLE_MAINNET,
            feeCollector: FEE_COLLECTOR_MAINNET,
            owner: OWNER_MAINNET,
            swapper: SWAPPER_MAINNET
        });
    }

    /**
     * @notice Get Rootstock testnet configuration
     * @return RootstockTestnetNetworkConfig Network configuration
     */
    function getRootstockTestnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            docTokenAddress: DOC_TOKEN_TESTNET,
            mocProxyAddress: MOC_PROXY_TESTNET,
            mocOracleAddress: MOC_ORACLE_TESTNET,
            feeCollector: FEE_COLLECTOR_TESTNET,
            owner: OWNER_TESTNET,
            swapper: SWAPPER_TESTNET
        });
    }

    /**
     * @notice Get or create Anvil local configuration
     * @return anvilNetworkConfig Network configuration with mocks
     */
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        // Return existing config if already created
        if (activeNetworkConfig.docTokenAddress != address(0)) {
            return activeNetworkConfig;
        }

        console2.log("Creating mock contracts for local testing...");

        vm.startBroadcast();

        // Deploy mock DOC token
        MockDoc mockDoc = new MockDoc();
        mockDocToken = address(mockDoc);
        emit HelperConfig__CreatedMockDoc(mockDocToken);
        console2.log("Mock DOC deployed at:", mockDocToken);

        // Deploy mock MoC oracle first
        MockMocOracle mockOracle = new MockMocOracle();
        mockMocOracle = address(mockOracle);
        console2.log("Mock MoC Oracle deployed at:", mockMocOracle);

        // Deploy mock MoC proxy with oracle address
        MockMocProxy mockMoc = new MockMocProxy(mockDocToken, mockMocOracle);
        mockMocProxy = address(mockMoc);
        emit HelperConfig__CreatedMockMocProxy(mockMocProxy);
        console2.log("Mock MoC Proxy deployed at:", mockMocProxy);

        vm.stopBroadcast();

        return NetworkConfig({
            docTokenAddress: mockDocToken,
            mocProxyAddress: mockMocProxy,
            mocOracleAddress: mockMocOracle,
            feeCollector: makeAddr(FEE_COLLECTOR_STRING), 
            owner: makeAddr(OWNER_STRING), 
            swapper: makeAddr(SWAPPER_STRING)
        });
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}

