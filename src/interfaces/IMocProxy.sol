// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title IMocProxy
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Interface for MoC proxy contract for minting DOC with rBTC
 */
interface IMocProxy {
    /**
     * @notice Mint DOC by depositing rBTC
     * @param btcToMint Amount of rBTC to send to mint DOC
     */
    function mintDoc(uint256 btcToMint) external payable;

    /**
     * @notice Mint DOC by depositing rBTC
     * @dev Alternative function name used by MoC
     * @param btcToMint Amount of rBTC to send to mint DOC
     */
    function mintDocVendors(uint256 btcToMint, address vendor) external payable;
}

