// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutManager} from "../../src/DcaOutManager.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";

/**
 * @title DcaOutManagerTestHelper
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test helper contract to expose internal functions for testing
 */
contract DcaOutManagerTestHelper is DcaOutManager {
    constructor(IDcaOutManager.ProtocolConfig memory config) DcaOutManager(config) {}

    // Expose internal functions for testing
    function calculateFee(uint256 docAmount) external view returns (uint256) {
        return _calculateFee(docAmount);
    }
}
