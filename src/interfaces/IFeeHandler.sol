// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title IFeeHandler
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Interface for fee calculation and management
 */
interface IFeeHandler {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeeHandler__MinFeeRateSet(uint256 minFeeRate);
    event FeeHandler__MaxFeeRateSet(uint256 maxFeeRate);
    event FeeHandler__PurchaseLowerBoundSet(uint256 feePurchaseLowerBound);
    event FeeHandler__PurchaseUpperBoundSet(uint256 feePurchaseUpperBound);
    event FeeHandler__FeeCollectorAddressSet(address feeCollector);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error FeeHandler__MinFeeRateCannotBeHigherThanMax();
    error FeeHandler__FeeLowerBoundCAnnotBeHigherThanUpperBound();
    error FeeHandler__FeeCollectorCannotBeZero();

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct FeeSettings {
        uint256 minFeeRate;
        uint256 maxFeeRate;
        uint256 feePurchaseLowerBound;
        uint256 feePurchaseUpperBound;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set all fee rate parameters at once
     * @param minFeeRate Minimum fee rate
     * @param maxFeeRate Maximum fee rate
     * @param feePurchaseLowerBound Lower bound for fee calculation
     * @param feePurchaseUpperBound Upper bound for fee calculation
     */
    function setFeeRateParams(
        uint256 minFeeRate,
        uint256 maxFeeRate,
        uint256 feePurchaseLowerBound,
        uint256 feePurchaseUpperBound
    ) external;

    /**
     * @notice Set the minimum fee rate
     * @param minFeeRate Minimum fee rate
     */
    function setMinFeeRate(uint256 minFeeRate) external;

    /**
     * @notice Set the maximum fee rate
     * @param maxFeeRate Maximum fee rate
     */
    function setMaxFeeRate(uint256 maxFeeRate) external;

    /**
     * @notice Set the purchase lower bound
     * @param feePurchaseLowerBound Purchase amount below which max fee applies
     */
    function setPurchaseLowerBound(uint256 feePurchaseLowerBound) external;

    /**
     * @notice Set the purchase upper bound
     * @param feePurchaseUpperBound Purchase amount above which min fee applies
     */
    function setPurchaseUpperBound(uint256 feePurchaseUpperBound) external;

    /**
     * @notice Set the fee collector address
     * @param feeCollector Address to receive fees
     */
    function setFeeCollectorAddress(address feeCollector) external;

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the minimum fee rate
     * @return The minimum fee rate
     */
    function getMinFeeRate() external view returns (uint256);

    /**
     * @notice Get the maximum fee rate
     * @return The maximum fee rate
     */
    function getMaxFeeRate() external view returns (uint256);

    /**
     * @notice Get the fee purchase lower bound
     * @return The purchase amount below which max fee applies
     */
    function getFeePurchaseLowerBound() external view returns (uint256);

    /**
     * @notice Get the fee purchase upper bound
     * @return The purchase amount above which min fee applies
     */
    function getFeePurchaseUpperBound() external view returns (uint256);

    /**
     * @notice Get the fee collector address
     * @return The fee collector address
     */
    function getFeeCollectorAddress() external view returns (address);
}

