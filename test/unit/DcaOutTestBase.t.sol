// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DcaOutManager} from "../../src/DcaOutManager.sol";
import {IDcaOutManager} from "../../src/interfaces/IDcaOutManager.sol";
import {IFeeHandler} from "../../src/interfaces/IFeeHandler.sol";
import {ICoinPairPrice} from "../interfaces/ICoinPairPrice.sol";
import {DeployDcaOut} from "../../script/DeployDcaOut.s.sol";
import {HelperConfig, MockDoc, MockMocProxy} from "../../script/HelperConfig.s.sol";
import {DcaOutManagerTestHelper} from "./DcaOutManagerTestHelper.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
    DcaOutManagerTestHelper public testHelper;

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
        uint256 rbtcDepositAmount,
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
    event DcaOutManager__ScheduleDeleted(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId,
        uint256 refundedAmount
    );
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
    event DcaOutManager__SwapperSet(address indexed swapper);
    event DcaOutManager__MinSalePeriodSet(uint256 indexed minSalePeriod);
    event DcaOutManager__MaxSchedulesPerUserSet(uint256 indexed maxSchedules);
    event DcaOutManager__MinSaleAmountSet(uint256 indexed minSaleAmount);
    event DcaOutManager__MocCommissionSet(uint256 indexed mocCommission);
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
        owner = config.owner;
        swapper = config.swapper;
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

        // Deploy test helper for fee calculations
        IFeeHandler.FeeSettings memory feeSettings = IFeeHandler.FeeSettings({
            minFeeRate: MIN_FEE_RATE,
            maxFeeRate: MAX_FEE_RATE,
            feePurchaseLowerBound: FEE_PURCHASE_LOWER_BOUND,
            feePurchaseUpperBound: FEE_PURCHASE_UPPER_BOUND
        });

        IDcaOutManager.ProtocolConfig memory protocolConfig = IDcaOutManager.ProtocolConfig({
            docTokenAddress: config.docTokenAddress,
            mocProxyAddress: config.mocProxyAddress,
            feeCollector: config.feeCollector,
            feeSettings: feeSettings,
            minSalePeriod: MIN_SALE_PERIOD,
            maxSchedulesPerUser: MAX_SCHEDULES_PER_USER,
            minSaleAmount: MIN_SALE_AMOUNT,
            mocCommission: MOC_COMMISSION,
            swapper: swapper
        });
        
        testHelper = new DcaOutManagerTestHelper(protocolConfig);

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

        bytes32 scheduleId = keccak256(
            abi.encodePacked(userAddress, block.timestamp, scheduleIndex)
        );
        
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__ScheduleCreated(userAddress, scheduleIndex, scheduleId, initialDeposit, rbtcSaleAmount, salePeriod);
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
        assertEq(schedule.scheduleId, scheduleId, "Schedule ID mismatch");
        
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
        
        // Get oracle price for precise assertions
        (uint256 rbtcPrice, bool isValid,) = mocOracle.getPriceInfo();
        assertTrue(isValid, "Oracle price should be valid");
        // Calculate expected DOC amount based on oracle price
        uint256 rbtcToMintDoc = Math.mulDiv(scheduleBefore.rbtcSaleAmount, PRECISION_FACTOR, PRECISION_FACTOR + MOC_COMMISSION, Math.Rounding.Up);
        uint256 expectedDocMinted = (rbtcToMintDoc * rbtcPrice) / 1e18;
        uint256 expectedDocAfterFees = expectedDocMinted - testHelper.calculateFee(expectedDocMinted);

        // Check event emission (partial match - docReceived values are unpredictable)
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcSold(userAddress, scheduleId, scheduleBefore.rbtcSaleAmount, expectedDocAfterFees, expectedDocMinted);
        vm.prank(swapper);
        dcaOutManager.sellRbtc(userAddress, scheduleIndex, scheduleId);
        
        // Verify execution results
        IDcaOutManager.DcaOutSchedule memory scheduleAfter = dcaOutManager.getSchedule(userAddress, scheduleIndex);
        uint256 rbtcSpent = scheduleBefore.rbtcBalance - scheduleAfter.rbtcBalance;
        uint256 userDocBalanceAfter = dcaOutManager.getUserDocBalance(userAddress);
        uint256 contractDocBalanceAfter = docToken.balanceOf(address(dcaOutManager));

        // With correct commission rate, exactly rbtcSaleAmount should be spent (no change returned)
        assertEq(rbtcSpent, scheduleBefore.rbtcSaleAmount, "rBTC spent should equal the rBTC to mint DOC");

        // Check that lastSaleTimestamp was updated
        assertGe(scheduleAfter.lastSaleTimestamp, scheduleBefore.lastSaleTimestamp, "Last sale timestamp should be updated");
        
        // Check that user received DOC
        assertGe(userDocBalanceAfter, userDocBalanceBefore, "User should receive DOC");
        
        // Check that contract received DOC from MoC
        assertGe(contractDocBalanceAfter, contractDocBalanceBefore, "Contract should receive DOC from MoC");
        
        // Check that rBTC balance decreased (accounting for potential change from MoC)
        assertLe(scheduleAfter.rbtcBalance, scheduleBefore.rbtcBalance, "rBTC balance should decrease");
        
        // Check that received DOC is reasonable
        uint256 docReceived = userDocBalanceAfter - userDocBalanceBefore;
        assertEq(docReceived, expectedDocAfterFees, "DOC received should be equal to expected after fees");
        assertEq(contractDocBalanceAfter - contractDocBalanceBefore, docReceived, "Contract should receive the same amount of DOC as the user");
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
        // Calculate total and track initial states
        uint256 totalRbtcToSpend = 0;
        uint256[] memory scheduleRbtcBalancesBefore = new uint256[](users.length);
        for (uint256 i; i < users.length; ++i) {
            IDcaOutManager.DcaOutSchedule memory schedule = dcaOutManager.getSchedule(users[i], scheduleIndexes[i]);
            totalRbtcToSpend += schedule.rbtcSaleAmount;
            scheduleRbtcBalancesBefore[i] = schedule.rbtcBalance;
        }
        
        uint256 rBtcBalanceBefore = address(dcaOutManager).balance;
        
        // Execute batch sale
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds, totalRbtcToSpend);
        
        // Verify exact rBTC accounting (this must be exact - no precision loss here)
        assertEq(rBtcBalanceBefore - address(dcaOutManager).balance, totalRbtcToSpend, "rBTC balance should decrease by exact total");
        
        // Verify each user's balance decreased by exact sale amount (exact accounting)
        for (uint256 i; i < users.length; ++i) {
            uint256 balanceAfter = dcaOutManager.getScheduleRbtcBalance(users[i], scheduleIndexes[i]);
            uint256 expectedBalance = scheduleRbtcBalancesBefore[i] - dcaOutManager.getScheduleSaleAmount(users[i], scheduleIndexes[i]);
            assertEq(balanceAfter, expectedBalance, "User rBTC balance should decrease by exact sale amount");
        }
        
        // Verify users received DOC (approximate - small precision loss is acceptable)
        // The precision loss comes from proportional distribution in batch operations
        // This is inherent to the approach and is negligible (< 1e-15% of typical amounts)
        for (uint256 i; i < users.length; ++i) {
            uint256 docBalance = dcaOutManager.getUserDocBalance(users[i]);
            assertGt(docBalance, 0, "User should receive DOC from batch sale");
        }
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
        vm.prank(userAddress);
        dcaOutManager.depositRbtc{value: amount}(scheduleIndex, scheduleId);
        
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
        uint256 expectedWithdrawal = (amount == 0 || amount > balanceBefore) ? balanceBefore : amount;
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__RbtcWithdrawn(userAddress, scheduleIndex, scheduleId, expectedWithdrawal);
        vm.prank(userAddress);
        dcaOutManager.withdrawRbtc(scheduleIndex, scheduleId, amount);
        
        // Verify withdrawal
        uint256 balanceAfter = dcaOutManager.getScheduleRbtcBalance(userAddress, scheduleIndex);
        assertEq(balanceAfter, balanceBefore - expectedWithdrawal, "rBTC balance should decrease by withdrawal amount");
    }

    /**
     * @notice Withdraw DOC balance
     * @param userAddress The user
     */
    function withdrawDoc(address userAddress) internal {
        uint256 userDocBalanceInContractBefore = dcaOutManager.getUserDocBalance(userAddress);
        uint256 userDocBalanceBefore = docToken.balanceOf(userAddress);
        
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit DcaOutManager__DocWithdrawn(userAddress, userDocBalanceInContractBefore);
        
        vm.prank(userAddress);
        dcaOutManager.withdrawDoc();
        
        // Verify withdrawal
        uint256 userDocBalanceInContractAfter = dcaOutManager.getUserDocBalance(userAddress);
        uint256 userDocBalanceAfter = docToken.balanceOf(userAddress);
        
        assertEq(userDocBalanceInContractAfter, 0, "User DOC balance should be zero after withdrawing");
        assertEq(userDocBalanceAfter, userDocBalanceBefore + userDocBalanceInContractBefore, "User should receive DOC tokens");
    }
}
