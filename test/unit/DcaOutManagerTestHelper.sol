// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DcaOutManager} from "../../src/DcaOutManager.sol";
import {IFeeHandler} from "../../src/interfaces/IFeeHandler.sol";

/**
 * @title DcaOutManagerTestHelper
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Test helper contract to expose internal functions for testing
 */
contract DcaOutManagerTestHelper is DcaOutManager {
    constructor(
        address docTokenAddress,
        address mocProxyAddress,
        address feeCollector,
        IFeeHandler.FeeSettings memory feeSettings,
        uint256 minSalePeriod,
        uint256 maxSchedulesPerUser,
        uint256 minSaleAmount,
        uint256 mocCommission,
        address swapper
    ) DcaOutManager(
            docTokenAddress,
            mocProxyAddress,
            feeCollector,
            feeSettings,
            minSalePeriod,
            maxSchedulesPerUser,
            minSaleAmount,
            mocCommission,
            swapper
        ) {}

    // Expose internal functions for testing
    function calculateFee(uint256 docAmount) external view returns (uint256) {
        return _calculateFee(docAmount);
    }

    function calculateFeeAndNetAmounts(uint256 docAmount) external view returns (uint256 fee, uint256 netAmount) {
        fee = _calculateFee(docAmount);
        netAmount = docAmount - fee;
    }
}
