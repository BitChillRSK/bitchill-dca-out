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
     * @notice Validate schedule index exists for user
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     */
    modifier validateScheduleIndexAndId(address user, uint256 scheduleIndex, bytes32 scheduleId) {
        if (scheduleIndex >= s_userSchedules[user].length) {
            revert DcaOutManager__InexistentScheduleIndex(user, scheduleIndex, s_userSchedules[user].length);
        }
        if (s_userSchedules[user][scheduleIndex].scheduleId != scheduleId) revert DcaOutManager__ScheduleIdAndIndexMismatch(scheduleId, s_userSchedules[user][scheduleIndex].scheduleId);
        _;
    }

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
        uint256 mocCommission
    ) FeeHandler(feeCollector, feeSettings) {
        i_docToken = IERC20(docTokenAddress);
        i_mocProxy = IMocProxy(mocProxyAddress);
        s_minSalePeriod = minSalePeriod;
        s_maxSchedulesPerUser = maxSchedulesPerUser;
        s_minSaleAmount = minSaleAmount;
        s_mocCommission = mocCommission;

        // Grant DEFAULT_ADMIN_ROLE to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

        if (scheduleIndex == s_maxSchedulesPerUser) {
            revert DcaOutManager__MaxSchedulesReached();
        }

        // Create schedule ID
        bytes32 scheduleId = keccak256(
            abi.encodePacked(msg.sender, block.timestamp, scheduleIndex)
        );

        // Create schedule
        DcaOutSchedule memory newSchedule = DcaOutSchedule({
            rbtcSaleAmount: rbtcSaleAmount,
            salePeriod: salePeriod,
            lastExecutionTime: 0, // Never executed yet
            rbtcBalance: msg.value,
            scheduleId: scheduleId
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
    ) external override payable validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId) {
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
        validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId)
    {
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
        validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId)
    {
        _validateSalePeriod(salePeriod);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.salePeriod = salePeriod;
        emit DcaOutManager__SalePeriodSet(msg.sender, scheduleId, salePeriod);
    }

    /**
     * @notice Delete a DCA schedule
     * @param scheduleIndex Index of the schedule
     * @param scheduleId Schedule ID for validation
     */
    function deleteDcaOutSchedule(uint256 scheduleIndex, bytes32 scheduleId)
        external
        override
        validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId)
        nonReentrant
    {
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
        nonReentrant
        validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId)
    {
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
        validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId)
    {
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        if (amount == 0 || amount > schedule.rbtcBalance) amount = schedule.rbtcBalance;
        schedule.rbtcBalance -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert DcaOutManager__RbtcWithdrawalFailed(msg.sender, amount);
        emit DcaOutManager__RbtcWithdrawn(msg.sender, scheduleIndex, scheduleId, amount);
    }

    /**
     * @notice Withdraw DOC balance
     * @param amount Amount of DOC to withdraw
     */
    function withdrawDoc(uint256 amount) external override nonReentrant {
        if (amount == 0) revert DcaOutManager__WithdrawalAmountCantBeThanZero();
        if (s_userDocBalances[msg.sender] < amount) revert DcaOutManager__DocBalanceInsufficient(amount, s_userDocBalances[msg.sender]);

        // Update balance
        s_userDocBalances[msg.sender] -= amount;

        // Transfer DOC
        i_docToken.safeTransfer(msg.sender, amount);

        emit DcaOutManager__DocWithdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION (SWAPPER ONLY)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sell rBTC for a user's schedule
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     */
    function sellRbtc(address user, uint256 scheduleIndex, bytes32 scheduleId)
        external
        override
        onlySwapper
        validateScheduleIndexAndId(user, scheduleIndex, scheduleId)
    {
        // Validate and update state
        uint256 rbtcToSpend = _sellRbtcChecksEffects(user, scheduleIndex, scheduleId);

        // Mint DOC from MoC
        uint256 docReceived = _mintDocFromMoc(rbtcToSpend);
        if (docReceived == 0) revert DcaOutManager__DocMintFailed(rbtcToSpend);

        // Calculate and collect fee
        uint256 fee = _calculateFee(docReceived);
        uint256 docAfterFee = docReceived - fee;
        _transferFee(i_docToken, fee);

        // Credit user's DOC balance
        s_userDocBalances[user] += docAfterFee;

        emit DcaOutManager__RbtcSold(
            user, s_userSchedules[user][scheduleIndex].scheduleId, rbtcToSpend, docAfterFee, docReceived
        );
    }

    /**
     * @notice Sell rBTC for multiple users in a batch
     * @param users Array of user addresses
     * @param scheduleIndexes Array of schedule indexes
     * @param scheduleIds Array of schedule IDs for validation
     */
    function batchSellRbtc(
        address[] memory users,
        uint256[] memory scheduleIndexes,
        bytes32[] memory scheduleIds
    ) external override onlySwapper {
        uint256 len = users.length;
        if (len == 0) revert DcaOutManager__ArrayLengthMismatch(0, 0);
        if (len != scheduleIndexes.length || len != scheduleIds.length) {
            revert DcaOutManager__ArrayLengthMismatch(len, scheduleIndexes.length);
        }

        uint256 totalRbtcToSpend;
        uint256[] memory rbtcSaleAmounts = new uint256[](len);

        // Validate all schedules and update state
        for (uint256 i; i < len; ++i) {
            uint256 rbtcSaleAmount = _sellRbtcChecksEffects(users[i], scheduleIndexes[i], scheduleIds[i]);
            rbtcSaleAmounts[i] = rbtcSaleAmount;
            totalRbtcToSpend += rbtcSaleAmount;
        }

        // Mint total DOC from MoC
        uint256 totalDocReceived = _mintDocFromMoc(totalRbtcToSpend);
        if (totalDocReceived == 0) revert DcaOutManager__DocMintFailed(totalRbtcToSpend);

        // Distribute DOC proportionally and collect fees
        uint256 totalFee;
        for (uint256 i; i < len; ++i) {
            // Calculate user's share of minted DOC
            uint256 userDocShare = (totalDocReceived * rbtcSaleAmounts[i]) / totalRbtcToSpend;
            
            // Calculate fee for this user
            uint256 userFee = _calculateFee(userDocShare);
            uint256 userDocAfterFee = userDocShare - userFee;
            totalFee += userFee;

            // Credit user's balance
            s_userDocBalances[users[i]] += userDocAfterFee;

            emit DcaOutManager__RbtcSold(
                users[i],
                s_userSchedules[users[i]][scheduleIndexes[i]].scheduleId,
                rbtcSaleAmounts[i],
                userDocAfterFee,
                userDocShare
            );
        }

        // Transfer total fees
        _transferFee(i_docToken, totalFee);

        emit DcaOutManager__RbtcSoldBatch(totalRbtcToSpend, totalDocReceived - totalFee, totalDocReceived, len);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
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
    function grantSwapperRole(address swapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SWAPPER_ROLE, swapper);
        emit DcaOutManager__SwapperSet(swapper);
    }

    /**
     * @notice Revoke swapper role from an address
     * @param swapper Address to revoke swapper role
     */
    function revokeSwapperRole(address swapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        // Sale amount must be at most half of the balance to allow at least two DCA sales
        if (saleAmount > rbtcBalance / 2) revert DcaOutManager__SaleAmountTooHighForPeriodicSales(saleAmount, rbtcBalance, rbtcBalance / 2);
    }

    function _validateSalePeriod(uint256 salePeriod) private view {
        if (salePeriod < s_minSalePeriod) revert DcaOutManager__SalePeriodBelowMinimum(salePeriod, s_minSalePeriod);
    }

    /**
     * @notice Mint DOC from MoC protocol by depositing rBTC
     * @param rbtcSaleAmount Amount of rBTC to send
     * @return docReceived Amount of DOC received
     */
    function _mintDocFromMoc(uint256 rbtcSaleAmount) internal returns (uint256 docReceived) {
        uint256 docBalanceBefore = i_docToken.balanceOf(address(this));

        // Calculate the net sale amount that will get exchanged for DOC after subtracting the MoC commission
        uint256 netSaleAmount = rbtcSaleAmount * PRECISION_FACTOR / (PRECISION_FACTOR + s_mocCommission);
        
        // Call MoC to mint DOC (payable function)
        try i_mocProxy.mintDoc{value: rbtcSaleAmount}(netSaleAmount) {
            // Success
        } catch {
            revert DcaOutManager__DocMintFailed(rbtcSaleAmount);
        }
        
        docReceived = i_docToken.balanceOf(address(this)) - docBalanceBefore;
    }

    /**
     * @notice Checks and effects for selling rBTC, before interactions
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     * @return The rBTC amount to spend
     */
    function _sellRbtcChecksEffects(address user, uint256 scheduleIndex, bytes32 scheduleId)
        private
        validateScheduleIndexAndId(user, scheduleIndex, scheduleId)
        returns (uint256)
    {
        DcaOutSchedule storage schedule = s_userSchedules[user][scheduleIndex];

        // Validate schedule has enough rBTC to sell
        if (schedule.rbtcBalance < schedule.rbtcSaleAmount) {
            revert DcaOutManager__InsufficientRbtcBalance(schedule.rbtcSaleAmount, schedule.rbtcBalance);
        }

        // Check if sale period has elapsed (skip check if this is the first sale)
        if (schedule.lastExecutionTime > 0 && 
            block.timestamp < schedule.lastExecutionTime + schedule.salePeriod) {
            revert DcaOutManager__SalePeriodNotElapsed(schedule.lastExecutionTime, schedule.lastExecutionTime + schedule.salePeriod, block.timestamp);
        }

        // Update state
        uint256 rbtcToSpend = schedule.rbtcSaleAmount;
        schedule.rbtcBalance -= rbtcToSpend;
        
        // Update last execution time (similar pattern to DcaManager)
        schedule.lastExecutionTime = schedule.lastExecutionTime == 0
            ? block.timestamp
            : schedule.lastExecutionTime + schedule.salePeriod;

        return rbtcToSpend;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all schedules for the caller
     * @return Array of schedules
     */
    function getMySchedules() external view override returns (DcaOutSchedule[] memory) {
        return s_userSchedules[msg.sender];
    }

    /**
     * @notice Get all schedules for a user
     * @param user User address
     * @return Array of schedules
     */
    function getSchedules(address user) external view override returns (DcaOutSchedule[] memory) {
        return s_userSchedules[user];
    }

    /**
     * @notice Get a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return The schedule details
     */
    function getSchedule(address user, uint256 scheduleIndex)
        external
        view
        override
        returns (DcaOutSchedule memory)
    {
        return s_userSchedules[user][scheduleIndex];
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
     * @notice Get rBTC amount for caller's schedule
     * @param scheduleIndex Schedule index
     * @return rBTC amount
     */
    function getMyScheduleRbtcAmount(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleRbtcAmount(msg.sender, scheduleIndex);
    }

    /**
     * @notice Get rBTC amount for a user's schedule
     * @param user User address
     * @param scheduleIndex Schedule index
     * @return rBTC amount
     */
    function getScheduleRbtcAmount(address user, uint256 scheduleIndex)
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

    /**
     * @notice Allow contract to receive rBTC only from MoC proxy
     */
    receive() external payable onlyMoC {}
}
