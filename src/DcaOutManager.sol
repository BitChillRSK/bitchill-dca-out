// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDcaOutManager} from "./interfaces/IDcaOutManager.sol";
import {IMocProxy} from "./interfaces/IMocProxy.sol";
import {FeeHandler} from "./FeeHandler.sol";
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
     * @notice Validate that the minimum sale period is greater than 1 day
     * @param minSalePeriod The minimum sale period to validate
     */
    modifier validateMinSalePeriod(uint256 minSalePeriod) {
        if (minSalePeriod < 1 days) revert DcaOutManager__MinSalePeriodBelowLowerBound(minSalePeriod, 1 days);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param config Protocol configuration (addresses, fee settings, and limits)
     */
    constructor(IDcaOutManager.ProtocolConfig memory config)
        FeeHandler(config.feeCollector, config.feeSettings)
        validateMinSalePeriod(config.minSalePeriod)
    {
        i_docToken = IERC20(config.docTokenAddress);
        i_mocProxy = IMocProxy(config.mocProxyAddress);
        s_minSalePeriod = config.minSalePeriod;
        s_maxSchedulesPerUser = config.maxSchedulesPerUser;
        s_minSaleAmount = config.minSaleAmount;
        s_mocCommission = config.mocCommission;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SWAPPER_ROLE, config.swapper);
    }

    /*//////////////////////////////////////////////////////////////
                        SCHEDULE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IDcaOutManager
     * @dev Uses assembly for gas-optimized schedule ID generation
     *      Validates inputs against protocol limits before storage
     */
    function createDcaOutSchedule(uint256 rbtcSaleAmount, uint256 salePeriod) external payable override nonReentrant {
        // Validate inputs
        if (msg.value == 0) revert DcaOutManager__DepositAmountCantBeZero();
        _validateSalePeriod(salePeriod);

        // Validate sale amount against balance (similar to DcaManager validation)
        _validateSaleAmount(rbtcSaleAmount, msg.value);

        DcaOutSchedule[] storage schedules = s_userSchedules[msg.sender];
        uint256 scheduleIndex = schedules.length; // The new schedule's index

        if (scheduleIndex >= s_maxSchedulesPerUser) revert DcaOutManager__MaxSchedulesReached();

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

        emit DcaOutManager__ScheduleCreated(
            msg.sender, scheduleId, scheduleIndex, rbtcSaleAmount, salePeriod, msg.value
        );
    }

    /// @inheritdoc IDcaOutManager
    function updateDcaOutSchedule(uint256 scheduleIndex, bytes32 scheduleId, uint256 rbtcSaleAmount, uint256 salePeriod)
        external
        payable
        override
    {
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
            msg.sender, scheduleId, scheduleIndex, rbtcSaleAmount, salePeriod, schedule.rbtcBalance
        );
    }

    /// @inheritdoc IDcaOutManager
    function setSaleAmount(uint256 scheduleIndex, bytes32 scheduleId, uint256 rbtcSaleAmount) external override {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        _validateSaleAmount(rbtcSaleAmount, schedule.rbtcBalance);
        schedule.rbtcSaleAmount = rbtcSaleAmount;
        emit DcaOutManager__SaleAmountSet(msg.sender, scheduleId, rbtcSaleAmount);
    }

    /// @inheritdoc IDcaOutManager
    function setSalePeriod(uint256 scheduleIndex, bytes32 scheduleId, uint256 salePeriod) external override {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        _validateSalePeriod(salePeriod);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.salePeriod = salePeriod;
        emit DcaOutManager__SalePeriodSet(msg.sender, scheduleId, salePeriod);
    }

    /// @inheritdoc IDcaOutManager
    function pauseSchedule(uint256 scheduleIndex, bytes32 scheduleId) external override {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.paused = true;
        emit DcaOutManager__SchedulePaused(msg.sender, scheduleId);
    }

    /// @inheritdoc IDcaOutManager
    function unpauseSchedule(uint256 scheduleIndex, bytes32 scheduleId) external override {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];
        schedule.paused = false;
        emit DcaOutManager__ScheduleUnpaused(msg.sender, scheduleId);
    }

    /// @inheritdoc IDcaOutManager
    function deleteDcaOutSchedule(uint256 scheduleIndex, bytes32 scheduleId) external override nonReentrant {
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

        emit DcaOutManager__ScheduleDeleted(msg.sender, scheduleId, scheduleIndex, schedule.rbtcBalance);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDcaOutManager
    function depositRbtc(uint256 scheduleIndex, bytes32 scheduleId) external payable override {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        if (msg.value == 0) revert DcaOutManager__DepositAmountCantBeZero();

        DcaOutSchedule storage schedule = s_userSchedules[msg.sender][scheduleIndex];

        // Update balance
        schedule.rbtcBalance += msg.value;

        emit DcaOutManager__RbtcDeposited(msg.sender, scheduleId, scheduleIndex, msg.value);
    }

    /// @inheritdoc IDcaOutManager
    function withdrawRbtc(uint256 scheduleIndex, bytes32 scheduleId, uint256 amount) external override nonReentrant {
        _validateScheduleIndexAndId(msg.sender, scheduleIndex, scheduleId);
        uint256 rbtcBalance = s_userSchedules[msg.sender][scheduleIndex].rbtcBalance;
        if (rbtcBalance == 0) revert DcaOutManager__NoRbtcBalance();
        if (amount == 0 || amount > rbtcBalance) amount = rbtcBalance;
        s_userSchedules[msg.sender][scheduleIndex].rbtcBalance -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert DcaOutManager__RbtcWithdrawalFailed(msg.sender, amount);
        emit DcaOutManager__RbtcWithdrawn(msg.sender, scheduleId, scheduleIndex, amount);
    }

    /// @inheritdoc IDcaOutManager
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
     * @inheritdoc IDcaOutManager
     * @dev Skips ID and period validations to minimize gas. Intended for BitChill bot.
     */
    function sellRbtc(address user, uint256 scheduleIndex, bytes32 scheduleId) external onlySwapper {
        _validateScheduleIndexAndId(user, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[user][scheduleIndex];
        _validateScheduleNotPaused(user, schedule.paused, scheduleId);
        schedule.lastSaleTimestamp = _validatePeriodElapsed(schedule.lastSaleTimestamp, schedule.salePeriod);
        uint256 rbtcToSpend = schedule.rbtcSaleAmount;
        uint256 docReceived = _mintDoc(rbtcToSpend);

        schedule.rbtcBalance -= rbtcToSpend;

        uint256 feeAmount = _calculateFee(docReceived);
        s_userDocBalances[user] += docReceived - feeAmount;
        _transferFee(i_docToken, feeAmount);
        emit DcaOutManager__RbtcSold(user, scheduleId, rbtcToSpend, docReceived - feeAmount, docReceived);
    }

    /// @inheritdoc IDcaOutManager
    function batchSellRbtc(
        address[] calldata users,
        uint256[] calldata scheduleIndexes,
        bytes32[] calldata scheduleIds,
        uint256 totalRbtcToSpend
    ) external onlySwapper {
        uint256 len = users.length;
        uint256 totalDocReceived = _mintDoc(totalRbtcToSpend);
        uint256 sumOfSaleAmounts;
        uint256 totalFee;

        FeeSettings memory feeSettings = _feeSettings();

        for (uint256 i; i < len;) {
            (uint256 saleAmount, uint256 fee) = _processUserSale(
                users[i], scheduleIndexes[i], scheduleIds[i], totalDocReceived, totalRbtcToSpend, feeSettings
            );
            sumOfSaleAmounts += saleAmount;
            totalFee += fee;
            unchecked {
                ++i;
            }
        }

        if (sumOfSaleAmounts != totalRbtcToSpend) {
            revert DcaOutManager__TotalSaleAmountMismatch(sumOfSaleAmounts, totalRbtcToSpend);
        }

        _transferFee(i_docToken, totalFee);
        emit DcaOutManager__RbtcSoldBatch(totalRbtcToSpend, totalDocReceived - totalFee, totalDocReceived, len);
    }

    /**
     * @dev Internal function to process a user's sale
     * @param user The user address
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID for validation
     * @param totalDocReceived The total DOC received
     * @param totalRbtcToSpend The total rBTC to spend
     * @return saleAmount The amount of rBTC sold
     * @return fee The fee amount
     */
    function _processUserSale(
        address user,
        uint256 scheduleIndex,
        bytes32 scheduleId,
        uint256 totalDocReceived,
        uint256 totalRbtcToSpend,
        FeeSettings memory feeSettings
    ) internal returns (uint256 saleAmount, uint256 fee) {
        _validateScheduleIndexAndId(user, scheduleIndex, scheduleId);
        DcaOutSchedule storage schedule = s_userSchedules[user][scheduleIndex];
        _validateScheduleNotPaused(user, schedule.paused, scheduleId);
        schedule.lastSaleTimestamp = _validatePeriodElapsed(schedule.lastSaleTimestamp, schedule.salePeriod);

        saleAmount = schedule.rbtcSaleAmount;

        uint256 docReceived = (totalDocReceived * saleAmount) / totalRbtcToSpend;
        schedule.rbtcBalance -= saleAmount;

        fee = _calculateFeeWithParams(docReceived, feeSettings);
        s_userDocBalances[user] += docReceived - fee;

        emit DcaOutManager__RbtcSold(user, scheduleId, saleAmount, docReceived - fee, docReceived);
    }

    /*//////////////////////////////////////////////////////////////
                           OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDcaOutManager
    function setMinSalePeriod(uint256 minSalePeriod) external override onlyOwner validateMinSalePeriod(minSalePeriod) {
        s_minSalePeriod = minSalePeriod;
        emit DcaOutManager__MinSalePeriodSet(minSalePeriod);
    }

    /// @inheritdoc IDcaOutManager
    function setMaxSchedulesPerUser(uint256 maxSchedules) external override onlyOwner {
        s_maxSchedulesPerUser = maxSchedules;
        emit DcaOutManager__MaxSchedulesPerUserSet(maxSchedules);
    }

    /// @inheritdoc IDcaOutManager
    function setMinSaleAmount(uint256 minSaleAmount) external onlyOwner {
        s_minSaleAmount = minSaleAmount;
        emit DcaOutManager__MinSaleAmountSet(minSaleAmount);
    }

    /**
     * @inheritdoc IDcaOutManager
     * @dev This should be kept in sync with MoC's actual commission rate.
     *      MoC commission can be changed via governance. When it changes,
     *      the owner should update this value accordingly.
     *      The commission rate uses precision factor 1e18 (e.g., 15e14 = 0.15%, 2e15 = 0.2%).
     *      To get the current MoC rate, check: MoCInrate.commissionRatesByTxType(MINT_DOC_FEES_RBTC)
     *      where MINT_DOC_FEES_RBTC = 3.
     */
    function setMocCommission(uint256 mocCommission) external onlyOwner {
        s_mocCommission = mocCommission;
        emit DcaOutManager__MocCommissionSet(mocCommission);
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
        if (saleAmount > rbtcBalance) {
            revert DcaOutManager__CannotSetSaleAmountMoreThanBalance(saleAmount, rbtcBalance, rbtcBalance);
        }
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
        if (s_userSchedules[user][scheduleIndex].scheduleId != scheduleId) {
            revert DcaOutManager__ScheduleIdAndIndexMismatch(
                scheduleId, s_userSchedules[user][scheduleIndex].scheduleId
            );
        }
    }

    /**
     * @notice Validate that the period has elapsed since the last sale
     * @notice The period is considered to have elapsed if the next allowed sale is within the current day (UTC)
     * @notice First sale stamps 00:00 UTC of that day; later sales add whole periods from that midnight
     * @param lastSaleTimestamp The timestamp of the last sale
     * @param salePeriod The sale period
     * @return currentSaleTimestamp The timestamp of the current sale
     */
    function _validatePeriodElapsed(uint256 lastSaleTimestamp, uint256 salePeriod)
        private
        view
        returns (uint256 currentSaleTimestamp)
    {
        uint256 currentDayStart = block.timestamp - (block.timestamp % 1 days); // 00:00 UTC of today
        uint256 nextSaleDayStart = lastSaleTimestamp + salePeriod - (lastSaleTimestamp + salePeriod) % 1 days; // 00:00 UTC of the next sale day
        if (lastSaleTimestamp != 0 && currentDayStart < nextSaleDayStart) {
            revert DcaOutManager__SalePeriodNotElapsed(
                lastSaleTimestamp, lastSaleTimestamp + salePeriod, block.timestamp
            );
        }
        if (lastSaleTimestamp == 0) {
            return currentDayStart;
        }
        // If the wall-clock snap still leaves today's UTC day due, consume one more
        // period so a second sale the same day cannot pass.
        uint256 periodsElapsed = (block.timestamp - lastSaleTimestamp) / salePeriod;
        unchecked {
            currentSaleTimestamp = lastSaleTimestamp + periodsElapsed * salePeriod;
        }
        nextSaleDayStart = currentSaleTimestamp + salePeriod - (currentSaleTimestamp + salePeriod) % 1 days;
        if (currentDayStart >= nextSaleDayStart) {
            unchecked {
                currentSaleTimestamp += salePeriod;
            }
        }
    }

    /**
     * @notice Validate that the schedule is not paused
     * @param user The user address
     * @param paused Whether the schedule is paused
     * @param scheduleId The schedule ID for validation
     */
    function _validateScheduleNotPaused(address user, bool paused, bytes32 scheduleId) private pure {
        if (paused) revert DcaOutManager__ScheduleIsPaused(user, scheduleId);
    }

    /**
     * @notice Mint DOC from MoC protocol by depositing rBTC
     * @dev Sends exactly rbtcSaleAmount to MoC. If change is returned, the receive() function will revert,
     *      indicating the stored MoC commission rate is incorrect and needs to be updated.
     *      Since we ensure the commission rate is correct, exactly rbtcSaleAmount will be spent.
     * @param rbtcSaleAmount Amount of rBTC to send (exact amount, no change expected)
     * @return docReceived Amount of DOC received
     */
    function _mintDoc(uint256 rbtcSaleAmount) internal returns (uint256 docReceived) {
        uint256 docBalanceBefore = i_docToken.balanceOf(address(this));

        // Calculate the rBTC amount that will be used to mint DOC (accounting for MoC commission)
        uint256 btcToMintDoc =
            Math.mulDiv(rbtcSaleAmount, PRECISION_FACTOR, PRECISION_FACTOR + s_mocCommission, Math.Rounding.Up);

        // Call MoC to mint DOC (payable function)
        // If change is returned, receive() will revert, indicating commission rate mismatch
        try i_mocProxy.mintDoc{value: rbtcSaleAmount}(btcToMintDoc) {
            docReceived = i_docToken.balanceOf(address(this)) - docBalanceBefore;
        } catch {
            revert DcaOutManager__DocMintFailed(rbtcSaleAmount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDcaOutManager
    function getSchedules(address user) public view override returns (DcaOutSchedule[] memory) {
        return s_userSchedules[user];
    }

    /// @inheritdoc IDcaOutManager
    function getMySchedules() external view override returns (DcaOutSchedule[] memory) {
        return getSchedules(msg.sender);
    }

    /// @inheritdoc IDcaOutManager
    function getSchedulesCount(address user) public view override returns (uint256) {
        return getSchedules(user).length;
    }

    /// @inheritdoc IDcaOutManager
    function getMySchedulesCount() external view override returns (uint256) {
        return getSchedulesCount(msg.sender);
    }

    /// @inheritdoc IDcaOutManager
    function getSchedule(address user, uint256 scheduleIndex) public view override returns (DcaOutSchedule memory) {
        return s_userSchedules[user][scheduleIndex];
    }

    /// @inheritdoc IDcaOutManager
    function getMySchedule(uint256 scheduleIndex) external view override returns (DcaOutSchedule memory) {
        return getSchedule(msg.sender, scheduleIndex);
    }

    /// @inheritdoc IDcaOutManager
    function getScheduleRbtcBalance(address user, uint256 scheduleIndex) public view override returns (uint256) {
        return s_userSchedules[user][scheduleIndex].rbtcBalance;
    }

    /// @inheritdoc IDcaOutManager
    function getMyScheduleRbtcBalance(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleRbtcBalance(msg.sender, scheduleIndex);
    }

    /// @inheritdoc IDcaOutManager
    function getScheduleSaleAmount(address user, uint256 scheduleIndex) public view override returns (uint256) {
        return s_userSchedules[user][scheduleIndex].rbtcSaleAmount;
    }

    /// @inheritdoc IDcaOutManager
    function getMyScheduleSaleAmount(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleSaleAmount(msg.sender, scheduleIndex);
    }

    /// @inheritdoc IDcaOutManager
    function getScheduleSalePeriod(address user, uint256 scheduleIndex) public view override returns (uint256) {
        return s_userSchedules[user][scheduleIndex].salePeriod;
    }

    /// @inheritdoc IDcaOutManager
    function getMyScheduleSalePeriod(uint256 scheduleIndex) external view override returns (uint256) {
        return getScheduleSalePeriod(msg.sender, scheduleIndex);
    }

    /// @inheritdoc IDcaOutManager
    function getScheduleId(address user, uint256 scheduleIndex) public view override returns (bytes32) {
        return s_userSchedules[user][scheduleIndex].scheduleId;
    }

    /// @inheritdoc IDcaOutManager
    function getMyScheduleId(uint256 scheduleIndex) external view override returns (bytes32) {
        return getScheduleId(msg.sender, scheduleIndex);
    }

    /// @inheritdoc IDcaOutManager
    function getScheduleIsPaused(address user, uint256 scheduleIndex) public view override returns (bool) {
        return s_userSchedules[user][scheduleIndex].paused;
    }

    /// @inheritdoc IDcaOutManager
    function getMyScheduleIsPaused(uint256 scheduleIndex) external view override returns (bool) {
        return getScheduleIsPaused(msg.sender, scheduleIndex);
    }

    /// @inheritdoc IDcaOutManager
    function getMyDocBalance() external view override returns (uint256) {
        return getUserDocBalance(msg.sender);
    }

    /// @inheritdoc IDcaOutManager
    function getUserDocBalance(address user) public view override returns (uint256) {
        return s_userDocBalances[user];
    }

    /// @inheritdoc IDcaOutManager
    function getMinSalePeriod() external view override returns (uint256) {
        return s_minSalePeriod;
    }

    /// @inheritdoc IDcaOutManager
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
     * @notice Get MoC commission rate
     * @return MoC commission rate (using precision factor 1e18, e.g., 15e14 = 0.15%)
     */
    function getMocCommission() external view returns (uint256) {
        return s_mocCommission;
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive rBTC only from MoC proxy
     * @dev Reverts if any rBTC is received, as this indicates MoC returned change.
     *      This means the stored MoC commission rate (s_mocCommission) is incorrect
     *      and needs to be updated via setMocCommission().
     */
    receive() external payable {
        if (msg.sender != address(i_mocProxy)) revert DcaOutManager__NotMoC(msg.sender);
        if (msg.value > 0) revert DcaOutManager__UnexpectedChangeReturned(msg.value);
    }
}
