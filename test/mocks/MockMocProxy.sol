// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MockDoc} from "./MockDoc.sol";
import {ICoinPairPrice} from "../interfaces/ICoinPairPrice.sol";
import "../Constants.sol";

contract MockMocProxy {
    MockDoc public docToken;
    ICoinPairPrice public oracle;

    event MockMint(address indexed sender, uint256 rbtcAmount, uint256 docMinted);

    constructor(address _docToken, address _oracle) {
        docToken = MockDoc(_docToken);
        oracle = ICoinPairPrice(_oracle);
    }

    /**
     * @notice Mock minting DOC with rBTC
     * @param btcToMint Amount of rBTC to convert
     * @return Amount of DOC minted
     */
    function mintDoc(uint256 btcToMint) external payable returns (uint256) {
        require(msg.value >= btcToMint, "MockMocProxy: insufficient value");
        require(btcToMint > 0, "MockMocProxy: zero amount");

        // Get oracle price and calculate DOC to mint
        (uint256 oraclePrice, bool isValid,) = oracle.getPriceInfo();
        require(isValid, "MockMocProxy: invalid oracle price");

        // Subtract the "change" from the rBTC to mint
        // Commission to charge
        uint256 commission = btcToMint * MOC_COMMISSION / PRECISION_FACTOR;
        uint256 change = msg.value - btcToMint - commission; 
        // Calculate DOC to mint using oracle price
        uint256 docToMint = (btcToMint * oraclePrice) / 1e18;

        // Mint DOC to sender
        docToken.mint(msg.sender, docToMint);

        // Simulate transfer to commission receiver
        payable(address(1234)).transfer(commission);

        emit MockMint(msg.sender, btcToMint, docToMint);

        // Return change to sender
        payable(msg.sender).transfer(change);

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
