// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DcaOutManager__ScheduleCreated(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId,
        uint256 rbtcSaleAmount,
        uint256 salePeriod
    );

    event DcaOutManager__ScheduleUpdated(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId,
        uint256 rbtcBalance,
        uint256 rbtcSaleAmount,
        uint256 salePeriod
    );

    event DcaOutManager__ScheduleDeleted(address indexed user, uint256 indexed scheduleIndex, bytes32 indexed scheduleId);

    event DcaOutManager__RbtcDeposited(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId,
        uint256 amount
    );

    event DcaOutManager__RbtcSold(
        address indexed user,
        bytes32 indexed scheduleId,
        uint256 indexed rbtcSaleAmount, // establieshed in the schedule
        uint256 rbtcSpent, // amount of rBTC spent in the sale (rbtcSaleAmount - change returned by MoC)
        uint256 docReceivedAfterFee,
        uint256 docReceived
    );

    event DcaOutManager__RbtcSoldBatch(
        uint256 indexed totalRbtcSaleAmount,
        uint256 indexed totalRbtcSpent,
        uint256 indexed totalDocReceivedAfterFee,
        uint256 totalDocReceived,
        uint256 usersCount
    );

    event DcaOutManager__DocWithdrawn(address indexed user, uint256 indexed amount);

    event DcaOutManager__RbtcWithdrawn(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId,
        uint256 amount
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
    
    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Schedule management
    function createDcaOutSchedule(uint256 rbtcSaleAmount, uint256 salePeriod) external payable;
    function updateDcaOutSchedule(
        uint256 scheduleIndex,
        bytes32 scheduleId,
        uint256 rbtcSaleAmount,
        uint256 salePeriod
    ) external payable;
    function setSaleAmount(uint256 scheduleIndex, bytes32 scheduleId, uint256 rbtcSaleAmount) external;
    function setSalePeriod(uint256 scheduleIndex, bytes32 scheduleId, uint256 salePeriod) external;
    function pauseSchedule(uint256 scheduleIndex, bytes32 scheduleId) external;
    function unpauseSchedule(uint256 scheduleIndex, bytes32 scheduleId) external;
    function deleteDcaOutSchedule(uint256 scheduleIndex, bytes32 scheduleId) external;

    // Deposit/Withdrawal
    function depositRbtc(uint256 scheduleIndex, bytes32 scheduleId) external payable;
    function withdrawDoc() external;
    function withdrawRbtc(uint256 scheduleIndex, bytes32 scheduleId, uint256 amount) external;

    // Execution (called by swapper)
    function sellRbtc(address user, uint256 scheduleIndex, bytes32 scheduleId) external;
    function batchSellRbtc(
        address[] calldata users,
        uint256[] calldata scheduleIndexes,
        bytes32[] calldata scheduleIds,
        uint256 totalRbtcToSpend
    ) external;

    // Owner functions
    function setMinSalePeriod(uint256 minPeriod) external;
    function setMaxSchedulesPerUser(uint256 maxSchedules) external;
    function setMinSaleAmount(uint256 minSaleAmount) external;
    function setMocCommission(uint256 mocCommission) external;

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    // Getters
    function getMySchedules() external view returns (DcaOutSchedule[] memory);
    function getSchedules(address user) external view returns (DcaOutSchedule[] memory);
    function getMySchedulesCount() external view returns (uint256);
    function getSchedulesCount(address user) external view returns (uint256);
    function getMySchedule(uint256 scheduleIndex) external view returns (DcaOutSchedule memory);
    function getSchedule(address user, uint256 scheduleIndex) external view returns (DcaOutSchedule memory);
    function getMyScheduleRbtcBalance(uint256 scheduleIndex) external view returns (uint256);
    function getScheduleRbtcBalance(address user, uint256 scheduleIndex) external view returns (uint256);
    function getMyScheduleSaleAmount(uint256 scheduleIndex) external view returns (uint256);
    function getScheduleSaleAmount(address user, uint256 scheduleIndex) external view returns (uint256);
    function getMyScheduleSalePeriod(uint256 scheduleIndex) external view returns (uint256);
    function getScheduleSalePeriod(address user, uint256 scheduleIndex) external view returns (uint256);
    function getMyScheduleId(uint256 scheduleIndex) external view returns (bytes32);
    function getScheduleId(address user, uint256 scheduleIndex) external view returns (bytes32);
    function getMyDocBalance() external view returns (uint256);
    function getUserDocBalance(address user) external view returns (uint256);
    function getMinSalePeriod() external view returns (uint256);
    function getMaxSchedulesPerUser() external view returns (uint256);
    function getMinSaleAmount() external view returns (uint256);
    function getMocCommission() external view returns (uint256);
}

