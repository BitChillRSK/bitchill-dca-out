// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDcaOutManager} from "./interfaces/IDcaOutManager.sol";
import {IMocProxy} from "./interfaces/IMocProxy.sol";
import {FeeHandler} from "./FeeHandler.sol";
import {IFeeHandler} from "./interfaces/IFeeHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title DcaOutManager
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Main contract for DCA Out protocol - sell rBTC for DOC periodically
 * @dev Single contract deployment - inherits AccessControl for swapper authorization
 */
contract DcaOutManager is IDcaOutManager, FeeHandler, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant SWAPPER_ROLE = keccak256("SWAPPER");
    uint256 private constant PRECISION_FACTOR = 1e18;

    IERC20 public immutable i_docToken;
    IMocProxy public immutable i_mocProxy;

    uint256 private s_minSalePeriod;
    uint256 private s_minSaleAmount;
    uint256 private s_maxSchedulesPerUser;
    uint256 private s_mocCommission;

    // User schedules: user => array of schedules
    mapping(address => DcaOutSchedule[]) private s_userSchedules;
    
    // User DOC balances (accumulated from swaps)
    mapping(address => uint256) private s_userDocBalances;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Only allow swapper role
     */
    modifier onlySwapper() {
        if (!hasRole(SWAPPER_ROLE, msg.sender)) {
            revert DcaOutManager__UnauthorizedSwapper(msg.sender);
        }
        _;
    }

    /**
     * @notice Only allow MoC proxy to send rBTC to the contract
     */
    modifier onlyMoC() {
        if (msg.sender != address(i_mocProxy)) revert DcaOutManager__NotMoC(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param docTokenAddress DOC token address
     * @param mocProxyAddress MoC proxy address
     * @param feeCollector Address to receive fees
     * @param feeSettings Fee configuration
     * @param minSalePeriod Minimum time between sells
     * @param maxSchedulesPerUser Maximum schedules per user
     * @param minSaleAmount Minimum rBTC amount per sell
     */
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
    ) FeeHandler(feeCollector, feeSettings) {
        i_docToken = IERC20(docTokenAddress);
        i_mocProxy = IMocProxy(mocProxyAddress);
        s_minSalePeriod = minSalePeriod;
        s_maxSchedulesPerUser = maxSchedulesPerUser;
        s_minSaleAmount = minSaleAmount;
        s_mocCommission = mocCommission;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SWAPPER_ROLE, swapper);
    }

    /*//////////////////////////////////////////////////////////////
                        SCHEDULE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new DCA schedule
     * @param rbtcSaleAmount Amount of rBTC to sell per period
     * @param salePeriod Time between sells (in seconds)
     */
    function createDcaOutSchedule(uint256 rbtcSaleAmount, uint256 salePeriod)
        external
        payable
        override
        nonReentrant
    {
        // Validate inputs
        if (msg.value == 0) revert DcaOutManager__DepositAmountCantBeZero();
        _validateSalePeriod(salePeriod);
        
        // Validate sale amount against balance (similar to DcaManager validation)
        _validateSaleAmount(rbtcSaleAmount, msg.value);

        DcaOutSchedule[] storage schedules = s_userSchedules[msg.sender];
        uint256 scheduleIndex = schedules.length; // The new schedule's index

        if (scheduleIndex == s_maxSchedulesPerUser) revert DcaOutManager__MaxSchedulesReached();

        // Create schedule ID
        bytes32 scheduleId;
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)
            // write address (20 bytes)
            mstore(ptr, shl(96, caller()))
            // write timestamp just after the 20 bytes (so +0x14)
            mstore(add(ptr, 0x14), timestamp())
            // write scheduleIndex just after timestamp (20 + 32 = 52 bytes = 0x34)
            mstore(add(ptr, 0x34), scheduleIndex)
            // total length = 20 + 32 + 32 = 84 bytes (0x54)
            scheduleId := keccak256(ptr, 0x54)
        }

        // Create schedule
        DcaOutSchedule memory newSchedule = DcaOutSchedule({
            rbtcSaleAmount: rbtcSaleAmount,
            salePeriod: salePeriod,
            lastSaleTimestamp: 0, // Never executed yet
            rbtcBalance: msg.value,
            scheduleId: scheduleId,
            paused: false
        });

        // Store schedule
        schedules.push(newSchedule);

        emit DcaOutManager__ScheduleCreated(msg.sender, scheduleIndex, scheduleId, rbtcSaleAmount, salePeriod);
    }

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
    ) external override payable {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        

        // Update salePeriod if provided
        if (salePeriod > 0) {
            _validateSalePeriod(salePeriod);
            schedule.salePeriod = salePeriod;
        }

        // Update rBTC balance
        schedule.rbtcBalance += msg.value;

        // Update rBTC amount if provided
        if (rbtcSaleAmount > 0) {
            _validateSaleAmount(rbtcSaleAmount, schedule.rbtcBalance);
            schedule.rbtcSaleAmount = rbtcSaleAmount;
        }

        emit DcaOutManager__ScheduleUpdated(
            msg.sender, scheduleIndex, scheduleId, 
            schedule.rbtcBalance, schedule.rbtcSaleAmount, schedule.salePeriod
        );
    }

    /**
     * @notice Set the rBTC sale amount for a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param rbtcSaleAmount New rBTC amount to sell per period
     */
    function setSaleAmount(uint256 scheduleIndex, bytes32 scheduleId, uint256 rbtcSaleAmount)
        external
        override
    {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        _validateSaleAmount(rbtcSaleAmount, schedule.rbtcBalance);
        schedule.rbtcSaleAmount = rbtcSaleAmount;
        emit DcaOutManager__SaleAmountSet(msg.sender, scheduleId, rbtcSaleAmount);
    }

    /**
     * @notice Set the sale period for a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param salePeriod New time between sales (in seconds)
     */
    function setSalePeriod(uint256 scheduleIndex, bytes32 scheduleId, uint256 salePeriod)
        external
        override
    {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        _validateSalePeriod(salePeriod);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.salePeriod = salePeriod;
        emit DcaOutManager__SalePeriodSet(msg.sender, scheduleId, salePeriod);
    }

    /**
     * @notice Pause a schedule to prevent sales
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function pauseSchedule(uint256 scheduleIndex, bytes32 scheduleId)
        external
        override
    {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.paused = true;
        emit DcaOutManager__SchedulePaused(msg.sender, scheduleId);
    }

    /**
     * @notice Unpause a schedule to allow sales
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function unpauseSchedule(uint256 scheduleIndex, bytes32 scheduleId)
        external
        override
    {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.paused = false;
        emit DcaOutManager__ScheduleUnpaused(msg.sender, scheduleId);
    }

    /**
     * @notice Delete a DCA schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function deleteDcaOutSchedule(uint256 scheduleIndex, bytes32 scheduleId)
        external
        override
        nonReentrant
        {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule[] storage schedules = s_userSchedules[msg.sender];
        DcaOutSchedule memory schedule = schedules[scheduleIndex];

        // Remove the schedule by popping the last one and overwriting the one to delete
        uint256 lastIndex = schedules.length - 1;
        if (scheduleIndex != lastIndex) {
            schedules[scheduleIndex] = schedules[lastIndex];
        }
        schedules.pop();

        // Transfer any remaining rBTC balance back to user
        if (schedule.rbtcBalance > 0) {
            (bool success,) = msg.sender.call{value: schedule.rbtcBalance}("");
            if (!success) revert DcaOutManager__RbtcWithdrawalFailed(msg.sender, schedule.rbtcBalance);
        }

        emit DcaOutManager__ScheduleDeleted(msg.sender, scheduleIndex, scheduleId);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit rBTC to a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function depositRbtc(uint256 scheduleIndex, bytes32 scheduleId)
        external
        payable
        override
    {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        if (msg.value == 0) revert DcaOutManager__DepositAmountCantBeZero();

        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        
        // Update balance
        schedule.rbtcBalance += msg.value;

        emit DcaOutManager__RbtcDeposited(msg.sender, scheduleIndex, scheduleId, msg.value);
    }

    /**
     * @notice Withdraw rBTC from a schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     * @param amount Amount of rBTC to withdraw - 0 to withdraw all
     */
    function withdrawRbtc(uint256 scheduleIndex, bytes32 scheduleId, uint256 amount)
        external
        override
        nonReentrant
    {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        if (amount == 0 || amount > schedule.rbtcBalance) amount = schedule.rbtcBalance;
        schedule.rbtcBalance -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert DcaOutManager__RbtcWithdrawalFailed(msg.sender, amount);
        emit DcaOutManager__RbtcWithdrawn(msg.sender, scheduleIndex, scheduleId, amount);
    }

    /**
     * @notice Withdraw DOC balance
     */
    function withdrawDoc() external override nonReentrant {
        uint256 balance = s_userDocBalances[msg.sender];
        if (balance == 0) revert DcaOutManager__NoDocToWithdraw();
        s_userDocBalances[msg.sender] = 0;
        i_docToken.safeTransfer(msg.sender, balance);
        emit DcaOutManager__DocWithdrawn(msg.sender, balance);
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION (SWAPPER ONLY)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gas-optimized trusted single sale (assumes well-formed inputs)
     * @dev Skips ID and period validations to minimize gas. Intended for BitChill bot.
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     */
    function sellRbtc(
        address user,
        uint256 scheduleIndex,
        bytes32 scheduleId
    ) external onlySwapper {
        _validateScheduleIndexAndId(user, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[user][scheduleIndex];
        _validateScheduleNotPaused(user, schedule.paused, scheduleId);
        uint256 lastSaleTimestamp = schedule.lastSaleTimestamp;
        uint256 salePeriod = schedule.salePeriod;
        _validatePeriodElapsed(lastSaleTimestamp, salePeriod);
        uint256 rbtcToSpend = schedule.rbtcSaleAmount;
        (uint256 docReceived, uint256 rbtcSpent) = _mintDoc(rbtcToSpend);

        schedule.rbtcBalance -= rbtcSpent;
        unchecked {
            schedule.lastSaleTimestamp = lastSaleTimestamp == 0
                ? block.timestamp
                : lastSaleTimestamp + salePeriod;
        }

        uint256 feeAmount = _calculateFee(docReceived);
        s_userDocBalances[user] += docReceived - feeAmount;
        _transferFee(i_docToken, feeAmount);
        emit DcaOutManager__RbtcSold(
            user,
            scheduleId,
            rbtcToSpend,
            rbtcSpent,
            docReceived - feeAmount,
            docReceived
        );
    }
    
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
    ) external onlySwapper {
        uint256 len = users.length;
        (uint256 totalDocReceived, uint256 totalRbtcSpent) = _mintDoc(totalRbtcToSpend);
        uint256 sumOfSaleAmounts;
        uint256 totalFee;

        for (uint256 i; i < len;) {
            (uint256 saleAmount, uint256 fee) = _processUserSale(
                users[i],
                scheduleIndexes[i],
                scheduleIds[i],
                totalDocReceived,
                totalRbtcSpent,
                totalRbtcToSpend
            );
            sumOfSaleAmounts += saleAmount;
            totalFee += fee;
            unchecked { ++i; }
        }

        if (sumOfSaleAmounts != totalRbtcToSpend)
            revert DcaOutManager__TotalSaleAmountMismatch(sumOfSaleAmounts, totalRbtcToSpend);

        _transferFee(i_docToken, totalFee);
        emit DcaOutManager__RbtcSoldBatch(totalRbtcToSpend, totalRbtcSpent, totalDocReceived - totalFee, totalDocReceived, len);
    }

    function _processUserSale(
        address user,
        uint256 scheduleIndex,
        bytes32 scheduleId,
        uint256 totalDocReceived,
        uint256 totalRbtcSpent,
        uint256 totalRbtcToSpend
    ) internal returns (uint256 saleAmount, uint256 fee) {
        _validateScheduleIndexAndId(user, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[user][scheduleIndex];
        _validateScheduleNotPaused(user, schedule.paused, scheduleId);
        _validatePeriodElapsed(schedule.lastSaleTimestamp, schedule.salePeriod);

        saleAmount = schedule.rbtcSaleAmount;

        uint256 docReceived = (totalDocReceived * saleAmount) / totalRbtcToSpend;
        uint256 rbtcSpent = Math.mulDiv(totalRbtcSpent, saleAmount, totalRbtcToSpend, Math.Rounding.Up);
        schedule.rbtcBalance -= rbtcSpent;
        unchecked {
            schedule.lastSaleTimestamp = schedule.lastSaleTimestamp == 0
                ? block.timestamp
                : schedule.lastSaleTimestamp + schedule.salePeriod;
        }

        fee = _calculateFee(docReceived);
        s_userDocBalances[user] += docReceived - fee;

        emit DcaOutManager__RbtcSold(user, scheduleId, saleAmount, rbtcSpent, docReceived - fee, docReceived);
    }

    /*//////////////////////////////////////////////////////////////
                           OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set minimum sale period
     * @param minSalePeriod Minimum time between sales
     */
    function setMinSalePeriod(uint256 minSalePeriod) external override onlyOwner {
        s_minSalePeriod = minSalePeriod;
        emit DcaOutManager__MinSalePeriodSet(minSalePeriod);
    }

    /**
     * @notice Set maximum schedules per user
     * @param maxSchedules Maximum number of schedules
     */
    function setMaxSchedulesPerUser(uint256 maxSchedules) external override onlyOwner {
        s_maxSchedulesPerUser = maxSchedules;
        emit DcaOutManager__MaxSchedulesPerUserSet(maxSchedules);
    }

    /**
     * @notice Grant swapper role to an address
     * @param swapper Address to grant swapper role
     */
    function grantSwapperRole(address swapper) external onlyOwner {
        _grantRole(SWAPPER_ROLE, swapper);
        emit DcaOutManager__SwapperSet(swapper);
    }

    /**
     * @notice Revoke swapper role from an address
     * @param swapper Address to revoke swapper role
     */
    function revokeSwapperRole(address swapper) external onlyOwner {
        _revokeRole(SWAPPER_ROLE, swapper);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate that the sale amount is valid against the rBTC balance
     * @param saleAmount The sale amount to validate
     * @param rbtcBalance The current rBTC balance
     */
    function _validateSaleAmount(uint256 saleAmount, uint256 rbtcBalance) private view {
        if (saleAmount < s_minSaleAmount) revert DcaOutManager__SaleAmountBelowMinimum(saleAmount, s_minSaleAmount);
        // Sale amount must be at most equal to balance to allow at least one sale
        if (saleAmount > rbtcBalance) revert DcaOutManager__CannotSetSaleAmountMoreThanBalance(saleAmount, rbtcBalance, rbtcBalance);
    }

    /**
     * @notice Validate that the sale period is valid
     * @param salePeriod The sale period to validate
     */
    function _validateSalePeriod(uint256 salePeriod) private view {
        if (salePeriod < s_minSalePeriod) revert DcaOutManager__SalePeriodBelowMinimum(salePeriod, s_minSalePeriod);
    }

    /**
     * @notice Validate schedule index exists for user
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     */
    function _validateScheduleIndexAndId(address user, uint256 scheduleIndex, bytes32 scheduleId) private view {
        if (scheduleIndex >= s_userSchedules[user].length) {
            revert DcaOutManager__InexistentScheduleIndex(user, scheduleIndex, s_userSchedules[user].length);
        }
        if (s_userSchedules[user][scheduleIndex].scheduleId != scheduleId) revert DcaOutManager__ScheduleIdAndIndexMismatch(scheduleId, s_userSchedules[user][scheduleIndex].scheduleId);
    }

    /**
     * @notice Validate that the period has elapsed since the last sale
     * @param lastSaleTimestamp The timestamp of the last sale
     * @param salePeriod The sale period
     */
    function _validatePeriodElapsed(uint256 lastSaleTimestamp, uint256 salePeriod) private view {
        if (lastSaleTimestamp != 0 && block.timestamp < lastSaleTimestamp + salePeriod) {
            revert DcaOutManager__SalePeriodNotElapsed(lastSaleTimestamp, lastSaleTimestamp + salePeriod, block.timestamp);
        }
    }

    /**
     * @notice Validate that the schedule is not paused
     * @param user The user address
     * @param paused Whether the schedule is paused
     * @param scheduleId The schedule ID for validation
     */
    function _validateScheduleNotPaused(address user, bool paused, bytes32 scheduleId) private view {
        if (paused) revert DcaOutManager__ScheduleIsPaused(user, scheduleId);
    }

    /**
     * @notice Mint DOC from MoC protocol by depositing rBTC and track change
     * @param rbtcSaleAmount Amount of rBTC to send
     * @return docReceived Amount of DOC received
     * @return rbtcSpent Amount of rBTC spent to mint DOC (rbtcSaleAmount - change returned by MoC)
     */
    function _mintDoc(uint256 rbtcSaleAmount) internal returns (uint256 docReceived, uint256 rbtcSpent) {
        uint256 docBalanceBefore = i_docToken.balanceOf(address(this));
        uint256 rbtcBalanceBefore = address(this).balance;

        // Calculate the rBTC amount that will be used to mint DOC (msg.value - MoC commission)
        // uint256 btcToMintDoc = rbtcSaleAmount, PRECISION_FACTOR, PRECISION_FACTOR + s_mocCommission, Math.Rounding.Up);
        uint256 btcToMintDoc = Math.mulDiv(rbtcSaleAmount, PRECISION_FACTOR, PRECISION_FACTOR + s_mocCommission, Math.Rounding.Up);
        
        // Call MoC to mint DOC (payable function)
        try i_mocProxy.mintDoc{value: rbtcSaleAmount}(btcToMintDoc) {
            docReceived = i_docToken.balanceOf(address(this)) - docBalanceBefore;
            rbtcSpent = rbtcBalanceBefore - address(this).balance;
        } catch {
            revert DcaOutManager__DocMintFailed(rbtcSaleAmount);
        } 
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all schedules for the caller
     * @return Array of schedules
     */
    function getMySchedules() external view override returns (DcaOutSchedule[] memory) {
        return getSchedules(msg.sender);
    }

    /**
     * @notice Get all schedules for a user
     * @param user User address
     * @return Array of schedules
     */
    function getSchedules(address user) public view override returns (DcaOutSchedule[] memory) {
        return s_userSchedules[user];
    }

    /**
     * @notice Get number of schedules for the caller
     * @return Number of schedules
     */
    function getMySchedulesCount() external view override returns (uint256) {
        return getSchedulesCount(msg.sender);
    }

    /**
     * @notice Get all schedules for a user
     * @param user User address
     * @return Number of schedules
     */
    function getSchedulesCount(address user) public view override returns (uint256) {
        return getSchedules(user).length;
    }

    /**
     * @notice Get a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return The schedule details
     */
    function getSchedule(address user, uint256 scheduleIndex)
        public
        view
        override
        returns (DcaOutSchedule memory)
    {
        return s_userSchedules[user][scheduleIndex];
    }

    /**
     * @notice Get caller's schedule
     * @param scheduleIndex Schedule index
     * @return The schedule details
     */
    function getMySchedule(uint256 scheduleIndex) external view override returns (DcaOutSchedule memory) {
        return getSchedule(msg.sender, scheduleIndex);
    }

    /**
     * @notice Get rBTC balance for caller's schedule
     * @param scheduleIndex Schedule index
     * @return rBTC balance
     */
    function getMyScheduleRbtcBalance(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleRbtcBalance(msg.sender, scheduleIndex);
    }

    /**
     * @notice Get rBTC balance for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return rBTC balance
     */
    function getScheduleRbtcBalance(address user, uint256 scheduleIndex)
        public
        view
        override
        returns (uint256)
    {
        return s_userSchedules[user][scheduleIndex].rbtcBalance;
    }

    /**
     * @notice Get rBTC periodic sale amount for caller's schedule
     * @param scheduleIndex Schedule index
     * @return rBTC periodic sale amount
     */
    function getMyScheduleSaleAmount(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleSaleAmount(msg.sender, scheduleIndex);
    }

    /**
     * @notice Get rBTC periodic sale amount for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return rBTC periodic sale amount
     */
    function getScheduleSaleAmount(address user, uint256 scheduleIndex)
        public
        view
        override
        returns (uint256)
    {
        return s_userSchedules[user][scheduleIndex].rbtcSaleAmount;
    }

    /**
     * @notice Get period for caller's schedule
     * @param scheduleIndex Schedule index
     * @return Period
     */
    function getMyScheduleSalePeriod(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleSalePeriod(msg.sender, scheduleIndex);
    }

    /**
     * @notice Get period for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return Period
     */
    function getScheduleSalePeriod(address user, uint256 scheduleIndex)
        public
        view
        override
        returns (uint256)
    {
        return s_userSchedules[user][scheduleIndex].salePeriod;
    }

    /**
     * @notice Get schedule ID for caller's schedule
     * @param scheduleIndex Schedule index
     * @return Schedule ID
     */
    function getMyScheduleId(uint256 scheduleIndex) external view override returns (bytes32) {
        return getScheduleId(msg.sender, scheduleIndex);
    }

    /**
     * @notice Get schedule ID for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return Schedule ID
     */
    function getScheduleId(address user, uint256 scheduleIndex)
        public
        view
        override
        returns (bytes32)
    {
        return s_userSchedules[user][scheduleIndex].scheduleId;
    }

    /**
     * @notice Get caller's DOC balance
     * @return DOC balance
     */
    function getMyDocBalance() external view override returns (uint256) {
        return getUserDocBalance(msg.sender);
    }

    /**
     * @notice Get user's total DOC balance
     * @param user User address
     * @return DOC balance
     */
    function getUserDocBalance(address user) public view override returns (uint256) {
        return s_userDocBalances[user];
    }

    /**
     * @notice Get minimum sale period
     * @return Minimum sale period
     */
    function getMinSalePeriod() external view override returns (uint256) {
        return s_minSalePeriod;
    }

    /**
     * @notice Get maximum schedules per user
     * @return Maximum schedules
     */
    function getMaxSchedulesPerUser() external view override returns (uint256) {
        return s_maxSchedulesPerUser;
    }

    /**
     * @notice Get minimum sell amount
     * @return Minimum sell amount
     */
    function getMinSaleAmount() external view returns (uint256) {
        return s_minSaleAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Allow contract to receive rBTC only from MoC proxy
     */
    receive() external payable onlyMoC {}
}
