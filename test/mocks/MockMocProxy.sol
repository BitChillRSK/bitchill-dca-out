// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MockDoc} from "./MockDoc.sol";

contract MockMocProxy {
    MockDoc public docToken;
    uint256 public constant MOCK_EXCHANGE_RATE = 100_000; // 1 rBTC = 100,000 DOC

    event MockMint(address indexed sender, uint256 rbtcAmount, uint256 docMinted);

    constructor(address _docToken) {
        docToken = MockDoc(_docToken);
    }

    /**
     * @notice Mock minting DOC with rBTC
     * @param btcToMint Amount of rBTC to convert
     * @return Amount of DOC minted
     */
    function mintDoc(uint256 btcToMint) external payable returns (uint256) {
        require(msg.value >= btcToMint, "MockMocProxy: insufficient value");
        require(btcToMint > 0, "MockMocProxy: zero amount");

        // Calculate DOC to mint (simulate 1 rBTC = 100,000 DOC)
        uint256 docToMint = (btcToMint * MOCK_EXCHANGE_RATE) / 1 ether;

        // Mint DOC to sender
        docToken.mint(msg.sender, docToMint);

        emit MockMint(msg.sender, btcToMint, docToMint);

        return docToMint;
    }

    /**
     * @notice Mock minting with vendors (not used but keeping interface)
     */
    function mintDocVendors(uint256 btcToMint, address /*vendor*/) external payable returns (uint256) {
        return this.mintDoc{value: msg.value}(btcToMint);
    }

    /**
     * @notice Allow contract to receive rBTC
     */
    receive() external payable {
        // Allow contract to receive rBTC
    }
}
