// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IFeeHandler} from "./interfaces/IFeeHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeHandler
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Abstract contract for handling fee calculation and collection
 * @dev Fees are charged in DOC after minting from rBTC
 */
abstract contract FeeHandler is IFeeHandler, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 internal s_minFeeRate; // Minimum fee rate (basis points)
    uint256 internal s_maxFeeRate; // Maximum fee rate (basis points)
    uint256 internal s_feePurchaseLowerBound; // Amount below which max fee applies
    uint256 internal s_feePurchaseUpperBound; // Amount above which min fee applies
    address internal s_feeCollector; // Address to receive collected fees
    uint256 constant FEE_PERCENTAGE_DIVISOR = 1e4; // Basis points divisor (100 * 100)

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param feeCollector Address to receive collected fees
     * @param feeSettings Initial fee configuration
     */
    constructor(address feeCollector, FeeSettings memory feeSettings) Ownable() {
        if (feeCollector == address(0)) revert FeeHandler__FeeCollectorCannotBeZero();
        s_feeCollector = feeCollector;
        s_minFeeRate = feeSettings.minFeeRate;
        s_maxFeeRate = feeSettings.maxFeeRate;
        s_feePurchaseLowerBound = feeSettings.feePurchaseLowerBound;
        s_feePurchaseUpperBound = feeSettings.feePurchaseUpperBound;
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
    ) external override onlyOwner {
        // Validate parameters
        if (minFeeRate > maxFeeRate) revert FeeHandler__MinFeeRateCannotBeHigherThanMax();
        if (feePurchaseLowerBound > feePurchaseUpperBound) {
            revert FeeHandler__FeeLowerBoundCAnnotBeHigherThanUpperBound();
        }

        if (s_minFeeRate != minFeeRate) setMinFeeRate(minFeeRate);
        if (s_maxFeeRate != maxFeeRate) setMaxFeeRate(maxFeeRate);
        if (s_feePurchaseLowerBound != feePurchaseLowerBound) {
            setPurchaseLowerBound(feePurchaseLowerBound);
        }
        if (s_feePurchaseUpperBound != feePurchaseUpperBound) {
            setPurchaseUpperBound(feePurchaseUpperBound);
        }
    }

    /**
     * @notice Set the minimum fee rate
     * @param minFeeRate Minimum fee rate
     */
    function setMinFeeRate(uint256 minFeeRate) public override onlyOwner {
        s_minFeeRate = minFeeRate;
        emit FeeHandler__MinFeeRateSet(minFeeRate);
    }

    /**
     * @notice Set the maximum fee rate
     * @param maxFeeRate Maximum fee rate
     */
    function setMaxFeeRate(uint256 maxFeeRate) public override onlyOwner {
        s_maxFeeRate = maxFeeRate;
        emit FeeHandler__MaxFeeRateSet(maxFeeRate);
    }

    /**
     * @notice Set the purchase lower bound
     * @param feePurchaseLowerBound Purchase amount below which max fee applies
     */
    function setPurchaseLowerBound(uint256 feePurchaseLowerBound) public override onlyOwner {
        s_feePurchaseLowerBound = feePurchaseLowerBound;
        emit FeeHandler__PurchaseLowerBoundSet(feePurchaseLowerBound);
    }

    /**
     * @notice Set the purchase upper bound
     * @param feePurchaseUpperBound Purchase amount above which min fee applies
     */
    function setPurchaseUpperBound(uint256 feePurchaseUpperBound) public override onlyOwner {
        s_feePurchaseUpperBound = feePurchaseUpperBound;
        emit FeeHandler__PurchaseUpperBoundSet(feePurchaseUpperBound);
    }

    /**
     * @notice Set the fee collector address
     * @param feeCollector Address to receive fees
     */
    function setFeeCollectorAddress(address feeCollector) external override onlyOwner {
        if (feeCollector == address(0)) revert FeeHandler__FeeCollectorCannotBeZero();
        s_feeCollector = feeCollector;
        emit FeeHandler__FeeCollectorAddressSet(feeCollector);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the minimum fee rate
     * @return The minimum fee rate
     */
    function getMinFeeRate() public view override returns (uint256) {
        return s_minFeeRate;
    }

    /**
     * @notice Get the maximum fee rate
     * @return The maximum fee rate
     */
    function getMaxFeeRate() public view override returns (uint256) {
        return s_maxFeeRate;
    }

    /**
     * @notice Get the fee purchase lower bound
     * @return The purchase amount below which max fee applies
     */
    function getFeePurchaseLowerBound() public view override returns (uint256) {
        return s_feePurchaseLowerBound;
    }

    /**
     * @notice Get the fee purchase upper bound
     * @return The purchase amount above which min fee applies
     */
    function getFeePurchaseUpperBound() public view override returns (uint256) {
        return s_feePurchaseUpperBound;
    }

    /**
     * @notice Get the fee collector address
     * @return The fee collector address
     */
    function getFeeCollectorAddress() external view override returns (address) {
        return s_feeCollector;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate fee based on the DOC amount minted
     * @dev Implements a sliding scale:
     *      - Amounts <= lower bound: max fee rate
     *      - Amounts >= upper bound: min fee rate
     *      - Amounts in between: linear interpolation
     * @param docAmount The amount of DOC minted
     * @return The fee amount to be collected
     */
    function _calculateFee(uint256 docAmount) internal view returns (uint256) {
        uint256 minFeeRate = s_minFeeRate;
        uint256 maxFeeRate = s_maxFeeRate;
        uint256 feePurchaseUpperBound = s_feePurchaseUpperBound;

        // If flat rate or amount is above upper bound, apply minimum fee
        if (minFeeRate == maxFeeRate || docAmount >= feePurchaseUpperBound) {
            return docAmount * minFeeRate / FEE_PERCENTAGE_DIVISOR;
        }

        uint256 feePurchaseLowerBound = s_feePurchaseLowerBound;
        // If amount is below lower bound, apply maximum fee
        if (docAmount <= feePurchaseLowerBound) {
            return docAmount * maxFeeRate / FEE_PERCENTAGE_DIVISOR;
        }

        // Calculate interpolated fee rate for amounts in between
        uint256 feeRate;
        unchecked {
            feeRate = maxFeeRate
                - ((docAmount - feePurchaseLowerBound) * (maxFeeRate - minFeeRate))
                    / (feePurchaseUpperBound - feePurchaseLowerBound);
        }
        return docAmount * feeRate / FEE_PERCENTAGE_DIVISOR;
    }

    /**
     * @notice Calculate fees and net amounts for a batch of DOC amounts
     * @param docAmounts Array of DOC amounts minted
     * @return aggregatedFee Total fee to be collected
     * @return netAmountsToUser Array of net amounts after fees for each user
     * @return totalNetAmount Total net amount distributed to users
     */
    function _calculateFeeAndNetAmounts(uint256[] memory docAmounts)
        internal
        view
        returns (uint256 aggregatedFee, uint256[] memory netAmountsToUser, uint256 totalNetAmount)
    {
        uint256 len = docAmounts.length;
        netAmountsToUser = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            uint256 amount = docAmounts[i];
            uint256 fee = _calculateFee(amount);
            aggregatedFee += fee;

            uint256 net = amount - fee;
            netAmountsToUser[i] = net;
            totalNetAmount += net;
        }
    }

    /**
     * @notice Transfer collected fees to the fee collector
     * @param token The DOC token contract
     * @param fee The fee amount to transfer
     */
    function _transferFee(IERC20 token, uint256 fee) internal {
        token.safeTransfer(s_feeCollector, fee);
    }
}

