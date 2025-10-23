// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutManager} from "../../src/DcaOutManager.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import {IFeeHandler} from "../../src/interfaces/IFeeHandler.sol";
import {ICoinPairPrice} from "../interfaces/ICoinPairPrice.sol";
import {DeployDcaOut} from "../../script/DeployDcaOut.s.sol";
import {HelperConfig, MockDoc, MockMocProxy} from "../../script/HelperConfig.s.sol";
import "../Constants.sol";
import "../../script/Constants.sol";

/**
 * @title DcaOutTestBase
 * @author BitChill team: Antonio Rodríguez-Ynyesto
 * @notice Base test class for DCA Out protocol tests
 */
contract DcaOutTestBase is Test {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DcaOutManager public dcaOutManager;
    DeployDcaOut public deployDcaOut;
    HelperConfig public helperConfig;
    MockDoc public docToken;
    MockMocProxy public mocProxy;
    ICoinPairPrice public mocOracle;

    address public owner;
    address public user;
    address public user2;
    address public swapper;
    address public feeCollector;

    uint256 constant STARTING_RBTC_USER_BALANCE = STARTING_RBTC_BALANCE;

    // MoC protocol addresses for fork testing
    address constant MOC_IN_RATE_MAINNET = 0xc0f9B54c41E3d0587Ce0F7540738d8d649b0A3F3;
    address constant MOC_IN_RATE_TESTNET = 0x76790f846FAAf44cf1B2D717d0A6c5f6f5152B60;
    address DUMMY_COMMISSION_RECEIVER = makeAddr("Dummy commission receiver");

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    // DcaOutManager
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
    event DcaOutManager__RbtcWithdrawn(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId,
        uint256 amount
    );
    event DcaOutManager__DocWithdrawn(address user, uint256 amount);
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
    event DcaOutManager__SwapperSet(address indexed swapper);
    event DcaOutManager__MinSalePeriodSet(uint256 indexed minSalePeriod);
    event DcaOutManager__MaxSchedulesPerUserSet(uint256 indexed maxSchedules);
    event DcaOutManager__SaleAmountSet(address indexed user, bytes32 indexed scheduleId, uint256 indexed rbtcSaleAmount);
    event DcaOutManager__SalePeriodSet(address indexed user, bytes32 indexed scheduleId, uint256 indexed salePeriod);

    /*//////////////////////////////////////////////////////////////
                            SETUP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Deploy DcaOutManager first to get the config
        deployDcaOut = new DeployDcaOut();
        (dcaOutManager, helperConfig) = deployDcaOut.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        // Use addresses from deployment config as single source of truth
        // For local/fork testing, test contract acts as owner and swapper
        bool isLocal = block.chainid == ANVIL_CHAIN_ID;
        bool isFork = block.chainid == RSK_MAINNET_CHAIN_ID || block.chainid == RSK_TESTNET_CHAIN_ID;
        
        owner = (isLocal || isFork) ? address(this) : config.owner;
        swapper = (isLocal || isFork) ? address(this) : config.swapper;
        feeCollector = config.feeCollector;
        
        // Create test users (these are not in the config as they're test-specific)
        user = makeAddr(USER_STRING);
        user2 = makeAddr("user2");

        // Deal rBTC funds to user
        vm.deal(user, STARTING_RBTC_USER_BALANCE);
        vm.deal(user2, STARTING_RBTC_USER_BALANCE);

        // For fork testing, we need to use mocks instead of real contracts
        // and set up the MoC commission receiver to avoid OutOfGas errors
        if (block.chainid == RSK_MAINNET_CHAIN_ID || block.chainid == RSK_TESTNET_CHAIN_ID) {
            // Override MoC commission receiver to avoid OutOfGas errors
            address mocInRate = block.chainid == RSK_MAINNET_CHAIN_ID ? MOC_IN_RATE_MAINNET : MOC_IN_RATE_TESTNET;
            vm.store(
                mocInRate,
                bytes32(uint256(214)), // Storage slot for commission address in MoCInrate
                bytes32(uint256(uint160(DUMMY_COMMISSION_RECEIVER)))
            );
        }
        
        // Get mock contracts
        docToken = MockDoc(config.docTokenAddress);
        mocProxy = MockMocProxy(payable(config.mocProxyAddress));
        mocOracle = ICoinPairPrice(config.mocOracleAddress);

        // Roles and ownership are handled entirely by the deployment script
        // No additional role management needed in test setup
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a DCA schedule for testing
     * @param userAddress The user to create the schedule for
     * @param rbtcSaleAmount Amount of rBTC to sell per period
     * @param salePeriod Time between sells
     * @param initialDeposit Initial rBTC deposit
     * @return scheduleId The created schedule ID
     */
    function createDcaOutSchedule(
        address userAddress,
        uint256 rbtcSaleAmount,
        uint256 salePeriod,
        uint256 initialDeposit
    ) internal returns (bytes32) {
        uint256 scheduleIndex = dcaOutManager.getSchedules(userAddress).length;
        
        // Check event emission
        vm.expectEmit(true, true, false, true);
        emit DcaOutManager__ScheduleCreated(userAddress, scheduleIndex, bytes32(0), rbtcSaleAmount, salePeriod);
        
        vm.prank(userAddress);
        dcaOutManager.createDcaOutSchedule{value: initialDeposit}(rbtcSaleAmount, salePeriod);

        // Verify schedule was created correctly
        IDcaOutManager.DcaOutSchedule[] memory schedules = dcaOutManager.getSchedules(userAddress);
        assertEq(schedules.length, scheduleIndex + 1, "Schedule count should increase by 1");
        
        IDcaOutManager.DcaOutSchedule memory schedule = schedules[scheduleIndex];
        assertEq(schedule.rbtcSaleAmount, rbtcSaleAmount, "Wrong rBTC sale amount");
        assertEq(schedule.salePeriod, salePeriod, "Wrong sale period");
        assertEq(schedule.rbtcBalance, initialDeposit, "Wrong initial rBTC balance");
        assertEq(schedule.lastSaleTimestamp, 0, "Last sale timestamp should be 0 for new schedule");
        assertTrue(schedule.scheduleId != bytes32(0), "Schedule ID should not be zero");
        
        return schedule.scheduleId;
    }

    /**
     * @notice Execute a single rBTC sale
     * @param userAddress The user whose schedule to execute
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID
     */
    function executeSale(address userAddress, uint256 scheduleIndex, bytes32 scheduleId) internal {
        // Get schedule details before execution
        IDcaOutManager.DcaOutSchedule memory scheduleBefore = dcaOutManager.getSchedule(userAddress, scheduleIndex);
        uint256 userDocBalanceBefore = dcaOutManager.getUserDocBalance(userAddress);
        uint256 contractDocBalanceBefore = docToken.balanceOf(address(dcaOutManager));
        
        // Get oracle price for more precise assertions
        (, bool isValid,) = mocOracle.getPriceInfo();
        assertTrue(isValid, "Oracle price should be valid");
        
        // Calculate expected DOC amount based on oracle price (for future use)
        // uint256 expectedDocAmount = (scheduleBefore.rbtcSaleAmount * oraclePrice) / 1e18;
        
        // Check event emission (partial match - rbtcSpent and docReceived are unpredictable)
        vm.expectEmit(true, true, true, false);
        emit DcaOutManager__RbtcSold(userAddress, scheduleId, scheduleBefore.rbtcSaleAmount, 0, 0, 0);
        
        vm.prank(swapper);
        dcaOutManager.sellRbtc(userAddress, scheduleIndex, scheduleId);
        
        // Verify execution results
        IDcaOutManager.DcaOutSchedule memory scheduleAfter = dcaOutManager.getSchedule(userAddress, scheduleIndex);
        uint256 userDocBalanceAfter = dcaOutManager.getUserDocBalance(userAddress);
        uint256 contractDocBalanceAfter = docToken.balanceOf(address(dcaOutManager));
        
        // Check that lastSaleTimestamp was updated
        assertTrue(scheduleAfter.lastSaleTimestamp > scheduleBefore.lastSaleTimestamp, "Last sale timestamp should be updated");
        
        // Check that user received DOC
        assertTrue(userDocBalanceAfter > userDocBalanceBefore, "User should receive DOC");
        
        // Check that contract received DOC from MoC
        assertTrue(contractDocBalanceAfter > contractDocBalanceBefore, "Contract should receive DOC from MoC");
        
        // Check that rBTC balance decreased (accounting for potential change from MoC)
        assertTrue(scheduleAfter.rbtcBalance < scheduleBefore.rbtcBalance, "rBTC balance should decrease");
        
        // More precise assertions using oracle data
        uint256 docReceived = userDocBalanceAfter - userDocBalanceBefore;
        uint256 docReceivedFromMoC = contractDocBalanceAfter - contractDocBalanceBefore;
        
        // Check that received DOC is reasonable
        assertTrue(docReceived > 0, "User should receive some DOC");
        assertTrue(docReceivedFromMoC > 0, "Contract should receive some DOC from MoC");
        
        // Note: Oracle-based precise assertions can be added later once the mock oracle
        // behavior is better aligned with the actual MoC proxy behavior
    }

    /**
     * @notice Execute batch rBTC sales
     * @param users Array of users
     * @param scheduleIndexes Array of schedule indexes
     * @param scheduleIds Array of schedule IDs
     */
    function executeBatchSale(
        address[] memory users,
        uint256[] memory scheduleIndexes,
        bytes32[] memory scheduleIds
    ) internal {
        // Calculate total rBTC to spend and track initial states
        uint256 totalRbtcToSpend;
        uint256[] memory userDocBalancesBefore = new uint256[](users.length);
        uint256[] memory scheduleRbtcBalancesBefore = new uint256[](users.length);
        
        for (uint256 i; i < users.length; ++i) {
            IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(users[i], scheduleIndexes[i]);
            totalRbtcToSpend += schedule.rbtcSaleAmount;
            userDocBalancesBefore[i] = dcaOutManager.getUserDocBalance(users[i]);
            scheduleRbtcBalancesBefore[i] = schedule.rbtcBalance;
        }
        
        // uint256 contractDocBalanceBefore = docToken.balanceOf(address(dcaOutManager));
        
        // Get oracle price for more precise assertions
        (, bool isValid,) = mocOracle.getPriceInfo();
        assertTrue(isValid, "Oracle price should be valid");
        
        // Calculate expected total DOC amount based on oracle price
        uint256 expectedTotalDocAmount = (totalRbtcToSpend * 1e18) / 1e18; // Simplified for now
        
        // The exact amounts of rBTC spent and DOC received are unpredictable
        vm.expectEmit(true, false, false, false);
        emit DcaOutManager__RbtcSoldBatch(totalRbtcToSpend, 0, 0, 0, users.length);
        
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, totalRbtcToSpend);
        
        // Verify batch execution results
        _verifyBatchExecutionResults(users, scheduleIndexes, userDocBalancesBefore, scheduleRbtcBalancesBefore, expectedTotalDocAmount);
    }
    
    function _verifyBatchExecutionResults(
        address[] memory users,
        uint256[] memory scheduleIndexes,
        uint256[] memory userDocBalancesBefore,
        uint256[] memory scheduleRbtcBalancesBefore,
        uint256 /* expectedTotalDocAmount */
    ) internal view {
        uint256 contractDocBalanceAfter = docToken.balanceOf(address(dcaOutManager));
        assertTrue(contractDocBalanceAfter > 0, "Contract should receive DOC from MoC");
        
        uint256 totalDocReceived = 0;
        for (uint256 i; i < users.length; ++i) {
            // Check that user received DOC
            uint256 userDocBalanceAfter = dcaOutManager.getUserDocBalance(users[i]);
            assertTrue(userDocBalanceAfter > userDocBalancesBefore[i], "User should receive DOC");
            
            // Check that rBTC balance decreased (accounting for potential change from MoC)
            uint256 currentBalance = dcaOutManager.getScheduleRbtcBalance(users[i], scheduleIndexes[i]);
            assertTrue(currentBalance <= scheduleRbtcBalancesBefore[i], "rBTC balance should not increase");
            
            totalDocReceived += (userDocBalanceAfter - userDocBalancesBefore[i]);
        }
        
        // More precise assertions using oracle data
        assertTrue(totalDocReceived > 0, "Total DOC received should be positive");
        
        // Note: Oracle-based precise assertions can be added later once the mock oracle
        // behavior is better aligned with the actual MoC proxy behavior
    }

    /**
     * @notice Deposit rBTC to a schedule
     * @param userAddress The user
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID
     * @param amount Amount to deposit
     */
    function depositRbtc(address userAddress, uint256 scheduleIndex, bytes32 scheduleId, uint256 amount) internal {
        uint256 balanceBefore = dcaOutManager.getScheduleRbtcBalance(userAddress, scheduleIndex);
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcDeposited(userAddress, scheduleIndex, scheduleId, amount);
        
        vm.startPrank(userAddress);
        dcaOutManager.depositRbtc{value: amount}(scheduleIndex, scheduleId);
        vm.stopPrank();
        
        // Verify deposit
        uint256 balanceAfter = dcaOutManager.getScheduleRbtcBalance(userAddress, scheduleIndex);
        assertEq(balanceAfter, balanceBefore + amount, "rBTC balance should increase by deposit amount");
    }

    /**
     * @notice Withdraw rBTC from a schedule
     * @param userAddress The user
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID
     * @param amount Amount to withdraw (0 for all)
     */
    function withdrawRbtc(address userAddress, uint256 scheduleIndex, bytes32 scheduleId, uint256 amount) internal {
        uint256 balanceBefore = dcaOutManager.getScheduleRbtcBalance(userAddress, scheduleIndex);
        uint256 expectedWithdrawal = amount == 0 ? balanceBefore : amount;
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcWithdrawn(userAddress, scheduleIndex, scheduleId, expectedWithdrawal);
        
        vm.startPrank(userAddress);
        dcaOutManager.withdrawRbtc(scheduleIndex, scheduleId, amount);
        vm.stopPrank();
        
        // Verify withdrawal
        uint256 balanceAfter = dcaOutManager.getScheduleRbtcBalance(userAddress, scheduleIndex);
        assertEq(balanceAfter, balanceBefore - expectedWithdrawal, "rBTC balance should decrease by withdrawal amount");
    }

    /**
     * @notice Withdraw DOC balance
     * @param userAddress The user
     * @param amount Amount to withdraw
     */
    function withdrawDoc(address userAddress, uint256 amount) internal {
        uint256 userDocBalanceBefore = dcaOutManager.getUserDocBalance(userAddress);
        uint256 userDocTokenBalanceBefore = docToken.balanceOf(userAddress);
        
        // Check event emission
        vm.expectEmit(false, false, false, true);
        emit DcaOutManager__DocWithdrawn(userAddress, amount);
        
        vm.startPrank(userAddress);
        dcaOutManager.withdrawDoc(amount);
        vm.stopPrank();
        
        // Verify withdrawal
        uint256 userDocBalanceAfter = dcaOutManager.getUserDocBalance(userAddress);
        uint256 userDocTokenBalanceAfter = docToken.balanceOf(userAddress);
        
        assertEq(userDocBalanceAfter, userDocBalanceBefore - amount, "User DOC balance should decrease by withdrawal amount");
        assertEq(userDocTokenBalanceAfter, userDocTokenBalanceBefore + amount, "User should receive DOC tokens");
    }
}
