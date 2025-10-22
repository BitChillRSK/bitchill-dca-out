// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DcaOutManager} from "../src/DcaOutManager.sol";
import {IDcaOutManager} from "../src/interfaces/IDcaOutManager.sol";
import {IFeeHandler} from "../src/interfaces/IFeeHandler.sol";
import {DeployDcaOut} from "../script/DeployDcaOut.s.sol";
import {HelperConfig, MockDoc, MockMocProxy} from "../script/HelperConfig.s.sol";
import "../test/Constants.sol";
import "../script/Constants.sol";

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
    event DcaOutManager__ScheduleDeleted(
        address indexed user,
        uint256 indexed scheduleIndex,
        bytes32 indexed scheduleId
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
    event DcaOutManager__DocWithdrawn(
        address indexed user,
        uint256 indexed amount
    );
    event DcaOutManager__RbtcSold(
        address indexed user,
        bytes32 indexed scheduleId,
        uint256 indexed rbtcSoldAmount,
        uint256 docReceivedAfterFee,
        uint256 docReceived
    );
    event DcaOutManager__RbtcSoldBatch(
        uint256 indexed totalRbtcSoldAmount,
        uint256 indexed totalDocReceivedAfterFee,
        uint256 indexed totalDocReceived,
        uint256 usersCount
    );
    event DcaOutManager__SwapperSet(address indexed swapper);
    event DcaOutManager__MinSalePeriodSet(uint256 indexed minSalePeriod);
    event DcaOutManager__MaxSchedulesPerUserSet(uint256 indexed maxSchedules);

    /*//////////////////////////////////////////////////////////////
                            SETUP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Create test accounts
        owner = address(this); // Test contract is owner for easier testing
        user = makeAddr(USER_STRING);
        user2 = makeAddr("user2");
        swapper = makeAddr(SWAPPER_STRING);
        feeCollector = makeAddr(FEE_COLLECTOR_STRING);

        // Deal rBTC funds to user
        vm.deal(user, STARTING_RBTC_USER_BALANCE);
        vm.deal(user2, STARTING_RBTC_USER_BALANCE);

        // Deploy DcaOutManager directly (test contract becomes owner/admin)
        deployDcaOut = new DeployDcaOut();
        (dcaOutManager, helperConfig) = deployDcaOut.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

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

        // Grant swapper role - use deployer for local, config admin for fork
        address admin = block.chainid == ANVIL_CHAIN_ID ? address(this) : config.admin;
        vm.startPrank(admin);
        dcaOutManager.grantRole(dcaOutManager.SWAPPER_ROLE(), swapper);
        vm.stopPrank();
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
        vm.startPrank(userAddress);
        dcaOutManager.createDcaOutSchedule{value: initialDeposit}(rbtcSaleAmount, salePeriod);
        vm.stopPrank();

        // Get the schedule ID
        IDcaOutManager.DcaOutSchedule[] memory schedules = dcaOutManager.getSchedules(userAddress);
        return schedules[schedules.length - 1].scheduleId;
    }

    /**
     * @notice Execute a single rBTC sale
     * @param userAddress The user whose schedule to execute
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID
     */
    function executeSale(address userAddress, uint256 scheduleIndex, bytes32 scheduleId) internal {
        vm.prank(swapper);
        dcaOutManager.sellRbtc(userAddress, scheduleIndex, scheduleId);
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
        vm.prank(swapper);
        dcaOutManager.batchSellRbtc(users, scheduleIndexes, scheduleIds);
    }

    /**
     * @notice Deposit rBTC to a schedule
     * @param userAddress The user
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID
     * @param amount Amount to deposit
     */
    function depositRbtc(address userAddress, uint256 scheduleIndex, bytes32 scheduleId, uint256 amount) internal {
        vm.startPrank(userAddress);
        dcaOutManager.depositRbtc{value: amount}(scheduleIndex, scheduleId);
        vm.stopPrank();
    }

    /**
     * @notice Withdraw rBTC from a schedule
     * @param userAddress The user
     * @param scheduleIndex The schedule index
     * @param scheduleId The schedule ID
     * @param amount Amount to withdraw (0 for all)
     */
    function withdrawRbtc(address userAddress, uint256 scheduleIndex, bytes32 scheduleId, uint256 amount) internal {
        vm.startPrank(userAddress);
        dcaOutManager.withdrawRbtc(scheduleIndex, scheduleId, amount);
        vm.stopPrank();
    }

    /**
     * @notice Withdraw DOC balance
     * @param userAddress The user
     * @param amount Amount to withdraw
     */
    function withdrawDoc(address userAddress, uint256 amount) internal {
        vm.startPrank(userAddress);
        dcaOutManager.withdrawDoc(amount);
        vm.stopPrank();
    }
}
