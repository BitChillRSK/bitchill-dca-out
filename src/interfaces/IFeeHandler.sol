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

    function setFeeRateParams(
        uint256 minFeeRate,
        uint256 maxFeeRate,
        uint256 feePurchaseLowerBound,
        uint256 feePurchaseUpperBound
    ) external;

    function setMinFeeRate(uint256 minFeeRate) external;
    function setMaxFeeRate(uint256 maxFeeRate) external;
    function setPurchaseLowerBound(uint256 feePurchaseLowerBound) external;
    function setPurchaseUpperBound(uint256 feePurchaseUpperBound) external;
    function setFeeCollectorAddress(address feeCollector) external;

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getMinFeeRate() external view returns (uint256);
    function getMaxFeeRate() external view returns (uint256);
    function getFeePurchaseLowerBound() external view returns (uint256);
    function getFeePurchaseUpperBound() external view returns (uint256);
    function getFeeCollectorAddress() external view returns (address);
}

