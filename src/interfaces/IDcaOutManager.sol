// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IFeeHandler} from "./IFeeHandler.sol";

/**
 * @title IDcaOutManager
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Interface for the DCA Out Manager contract
 */
interface IDcaOutManager {
    /*//////////////////////////////////////////////////////////////
                            TYPE DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    struct DcaOutSchedule {
        uint256 rbtcBalance;       // Current rBTC balance deposited
        uint256 rbtcSaleAmount;    // Amount of rBTC to sell per period
        uint256 salePeriod;        // Time between sales (in seconds)
        uint256 lastSaleTimestamp; // Timestamp of last execution
        bytes32 scheduleId;        // Unique identifier of the schedule
        bool paused;               // Whether the schedule is paused
    }

    struct ProtocolConfig {
        address docTokenAddress;
        address mocProxyAddress;
        address feeCollector;
        IFeeHandler.FeeSettings feeSettings;
        uint256 minSalePeriod;
        uint256 maxSchedulesPerUser;
        uint256 minSaleAmount;
        uint256 mocCommission;
        address swapper;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DcaOutManager__ScheduleCreated(
        address indexed user,
        uint256 indexed rbtcSaleAmount,
        uint256 indexed salePeriod,
        uint256 scheduleIndex,
        bytes32 scheduleId,
        uint256 rbtcDepositAmount
    );

    event DcaOutManager__ScheduleUpdated(
        address indexed user,
        uint256 indexed rbtcSaleAmount,
        uint256 indexed salePeriod,
        uint256 scheduleIndex,
        bytes32 scheduleId,
        uint256 rbtcBalance
    );

    event DcaOutManager__ScheduleDeleted(
        address indexed user,
        uint256 indexed refundedAmount,
        bytes32 indexed scheduleId,
        uint256 scheduleIndex
    );

    event DcaOutManager__RbtcDeposited(
        address indexed user,
        uint256 indexed amount,
        bytes32 indexed scheduleId,
        uint256 scheduleIndex
    );

    event DcaOutManager__RbtcSold(
        address indexed user,
        bytes32 indexed scheduleId,
        uint256 indexed rbtcSaleAmount, // established in the schedule
        uint256 docReceivedAfterFee,
        uint256 docReceived
    );

    event DcaOutManager__RbtcSoldBatch(
        uint256 indexed totalRbtcSaleAmount,
        uint256 indexed totalDocReceivedAfterFee,
        uint256 indexed totalDocReceived,
        uint256 usersCount
    );

    event DcaOutManager__DocWithdrawn(address indexed user, uint256 indexed amount);

    event DcaOutManager__RbtcWithdrawn(
        address indexed user,
        uint256 indexed amount,
        bytes32 indexed scheduleId,
        uint256 scheduleIndex
    );

    event DcaOutManager__SwapperSet(address indexed swapper);
    event DcaOutManager__MinSalePeriodSet(uint256 indexed minSalePeriod);
    event DcaOutManager__MaxSchedulesPerUserSet(uint256 indexed maxSchedules);
    event DcaOutManager__MinSaleAmountSet(uint256 indexed minSaleAmount);
    event DcaOutManager__MocCommissionSet(uint256 indexed mocCommission);
    event DcaOutManager__SaleAmountSet(address indexed user, bytes32 indexed scheduleId, uint256 indexed rbtcSaleAmount);
    event DcaOutManager__SalePeriodSet(address indexed user, bytes32 indexed scheduleId, uint256 indexed salePeriod);
    event DcaOutManager__SchedulePaused(address indexed user, bytes32 indexed scheduleId);
    event DcaOutManager__ScheduleUnpaused(address indexed user, bytes32 indexed scheduleId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DcaOutManager__DepositAmountCantBeZero();
    error DcaOutManager__NoDocToWithdraw();
    error DcaOutManager__SaleAmountBelowMinimum(uint256 inputAmount, uint256 minimumAmount);
    error DcaOutManager__SalePeriodBelowMinimum(uint256 inputPeriod, uint256 minimumPeriod);
    error DcaOutManager__MaxSchedulesReached();
    error DcaOutManager__InexistentScheduleIndex(address user, uint256 scheduleIndex, uint256 scheduleCount);
    error DcaOutManager__ScheduleIdAndIndexMismatch(bytes32 providedId, bytes32 expectedId);
    error DcaOutManager__SalePeriodNotElapsed(uint256 lastSaleTimestamp, uint256 nextSaleTimestamp, uint256 currentTime);
    error DcaOutManager__DocMintFailed(uint256 rbtcAmount);
    error DcaOutManager__RbtcWithdrawalFailed(address user, uint256 amount);
    error DcaOutManager__CannotSetSaleAmountMoreThanBalance(uint256 saleAmount, uint256 rbtcBalance, uint256 maxSaleAmount);
    error DcaOutManager__UnauthorizedSwapper(address caller);
    error DcaOutManager__NotMoC(address caller);
    error DcaOutManager__TotalSaleAmountMismatch(uint256 totalSaleAmount, uint256 totalRbtcToSpend);
    error DcaOutManager__ScheduleIsPaused(address user, bytes32 scheduleId);
    error DcaOutManager__UnexpectedChangeReturned(uint256 amount);
    
    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// Schedule management ///

    /**
     * @notice Create a new DCA schedule
     * @param rbtcSaleAmount Amount of rBTC to sell per period
     * @param salePeriod Time between sells (in seconds)
     */
    function createDcaOutSchedule(uint256 rbtcSaleAmount, uint256 salePeriod) external payable;

    /**
     * @notice Update a DCA schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param rbtcSaleAmount New rBTC amount per period (0 to skip)
     * @param salePeriod New sale period (0 to skip)
     */
    function updateDcaOutSchedule(
        uint256 scheduleIndex,
        bytes32 scheduleId,
        uint256 rbtcSaleAmount,
        uint256 salePeriod
    ) external payable;

    /**
     * @notice Set the rBTC sale amount for a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param rbtcSaleAmount New rBTC amount to sell per period
     */
    function setSaleAmount(uint256 scheduleIndex, bytes32 scheduleId, uint256 rbtcSaleAmount) external;

    /**
     * @notice Set the sale period for a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param salePeriod New time between sales (in seconds)
     */
    function setSalePeriod(uint256 scheduleIndex, bytes32 scheduleId, uint256 salePeriod) external;

    /**
     * @notice Pause a schedule to prevent sales
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function pauseSchedule(uint256 scheduleIndex, bytes32 scheduleId) external;

    /**
     * @notice Unpause a schedule to allow sales
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function unpauseSchedule(uint256 scheduleIndex, bytes32 scheduleId) external;

    /**
     * @notice Delete a DCA schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function deleteDcaOutSchedule(uint256 scheduleIndex, bytes32 scheduleId) external;

    /// Deposit/Withdrawal ///

    /**
     * @notice Deposit rBTC to a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function depositRbtc(uint256 scheduleIndex, bytes32 scheduleId) external payable;

    /**
     * @notice Withdraw DOC balance
     */
    function withdrawDoc() external;

    /**
     * @notice Withdraw rBTC from a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param amount Amount of rBTC to withdraw - 0 to withdraw all
     * @param to Address to send the rBTC to - 0x0 to send to the caller
     */
    function withdrawRbtc(uint256 scheduleIndex, bytes32 scheduleId, uint256 amount, address payable to) external;

    /// Execution (called by swapper) ///

    /**
     * @notice Gas-optimized trusted single sale (assumes well-formed inputs)
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     */
    function sellRbtc(address user, uint256 scheduleIndex, bytes32 scheduleId) external;

    /**
     * @notice Gas-optimized trusted batch sale (assumes well-formed inputs)
     * @param users Addresses of the users on behalf of whom rBTC is going to be sold
     * @param scheduleIndexes Indexes of the schedules that correspond to each user's sale
     * @param scheduleIds IDs of the schedules that correspond to each user's sale
     * @param totalRbtcToSpend Total amount of rBTC to spend
     */
    function batchSellRbtc(
        address[] calldata users,
        uint256[] calldata scheduleIndexes,
        bytes32[] calldata scheduleIds,
        uint256 totalRbtcToSpend
    ) external;

    /// Owner functions ///
    /**
     * @notice Set minimum sale period
     * @param minPeriod Minimum time between sales
     */
    function setMinSalePeriod(uint256 minPeriod) external;

    /**
     * @notice Set maximum schedules per user
     * @param maxSchedules Maximum number of schedules
     */
    function setMaxSchedulesPerUser(uint256 maxSchedules) external;

    /**
     * @notice Set minimum sale amount
     * @param minSaleAmount Minimum rBTC amount per sell
     */
    function setMinSaleAmount(uint256 minSaleAmount) external;

    /**
     * @notice Set MoC commission rate
     * @param mocCommission MoC commission rate (using precision factor 1e18)
     */
    function setMocCommission(uint256 mocCommission) external;

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all schedules for a user
     * @param user User address
     * @return Array of schedules
     */
    function getSchedules(address user) external view returns (DcaOutSchedule[] memory);

    /**
     * @notice Get all schedules for the caller
     * @return Array of schedules
     */
    function getMySchedules() external view returns (DcaOutSchedule[] memory);

    /**
     * @notice Get all schedules for a user
     * @param user User address
     * @return Number of schedules
     */
    function getSchedulesCount(address user) external view returns (uint256);

    /**
     * @notice Get number of schedules for the caller
     * @return Number of schedules
     */
    function getMySchedulesCount() external view returns (uint256);

    /**
     * @notice Get a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return The schedule details
     */
    function getSchedule(address user, uint256 scheduleIndex) external view returns (DcaOutSchedule memory);

    /**
     * @notice Get caller's schedule
     * @param scheduleIndex Schedule index
     * @return The schedule details
     */
    function getMySchedule(uint256 scheduleIndex) external view returns (DcaOutSchedule memory);
    
    /**
     * @notice Get rBTC balance for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return rBTC balance
     */
    function getScheduleRbtcBalance(address user, uint256 scheduleIndex) external view returns (uint256);

    /**
     * @notice Get rBTC balance for caller's schedule
     * @param scheduleIndex Schedule index
     * @return rBTC balance
     */
    function getMyScheduleRbtcBalance(uint256 scheduleIndex) external view returns (uint256);

    /**
     * @notice Get rBTC periodic sale amount for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return rBTC periodic sale amount
     */
    function getScheduleSaleAmount(address user, uint256 scheduleIndex) external view returns (uint256);

    /**
     * @notice Get rBTC periodic sale amount for caller's schedule
     * @param scheduleIndex Schedule index
     * @return rBTC periodic sale amount
     */
    function getMyScheduleSaleAmount(uint256 scheduleIndex) external view returns (uint256);

    /**
     * @notice Get period for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return Period
     */
    function getScheduleSalePeriod(address user, uint256 scheduleIndex) external view returns (uint256);

    /**
     * @notice Get period for caller's schedule
     * @param scheduleIndex Schedule index
     * @return Period
     */
    function getMyScheduleSalePeriod(uint256 scheduleIndex) external view returns (uint256);

    /**
     * @notice Get schedule ID for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return Schedule ID
     */
    function getScheduleId(address user, uint256 scheduleIndex) external view returns (bytes32);

    /**
     * @notice Get schedule ID for caller's schedule
     * @param scheduleIndex Schedule index
     * @return Schedule ID
     */
    function getMyScheduleId(uint256 scheduleIndex) external view returns (bytes32);

    /**
     * @notice Get whether a schedule is paused
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return Whether the schedule is paused
     */
    function getScheduleIsPaused(address user, uint256 scheduleIndex) external view returns (bool);

    /**
     * @notice Get whether caller's schedule is paused
     * @param scheduleIndex Schedule index
     * @return Whether the schedule is paused
     */
    function getMyScheduleIsPaused(uint256 scheduleIndex) external view returns (bool);

    /**
     * @notice Get caller's DOC balance
     * @return DOC balance
     */
    function getMyDocBalance() external view returns (uint256);

    /**
     * @notice Get user's total DOC balance
     * @param user User address
     * @return DOC balance
     */
    function getUserDocBalance(address user) external view returns (uint256);

    /**
     * @notice Get minimum sale period
     * @return Minimum sale period
     */
    function getMinSalePeriod() external view returns (uint256);

    /**
     * @notice Get maximum schedules per user
     * @return Maximum schedules
     */
    function getMaxSchedulesPerUser() external view returns (uint256);

    /**
     * @notice Get minimum sell amount
     * @return Minimum sell amount
     */
    function getMinSaleAmount() external view returns (uint256);

    /**
     * @notice Get MoC commission rate
     * @return MoC commission rate (using precision factor 1e18)
     */
    function getMocCommission() external view returns (uint256);
}

