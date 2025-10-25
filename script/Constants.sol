// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Protocol configuration
uint256 constant MOC_COMMISSION = 15e14; // 0.15% MoC commission
uint256 constant PRECISION_FACTOR = 1e18;

// Production parameters
uint256 constant MIN_SALE_AMOUNT = 0.001 ether; // at least 0.001 rBTC per sale
uint256 constant MIN_SALE_PERIOD = 1 days; // Minimum time between sales (1 day for production)

// Testing parameters for RSK testnet live deployments
uint256 constant MIN_SALE_AMOUNT_TESTNET = 0.0001 ether; // at least 0.0001 rBTC per sale for testing
uint256 constant MIN_SALE_PERIOD_TESTNET = 1 seconds; // 1 second for testing (can use vm.warp to skip time)

// Fee configuration
uint256 constant MIN_FEE_RATE = 100; // 1% fee rate
uint256 constant MAX_FEE_RATE_TEST = 200; // 2% for testing - allows for better fee range testing
uint256 constant MAX_FEE_RATE_PRODUCTION = 100; // 1% flat rate for production (same as MIN_FEE_RATE for flat fee)
uint256 constant FEE_PURCHASE_LOWER_BOUND = 1000 ether; // 1000 DOC
uint256 constant FEE_PURCHASE_UPPER_BOUND = 100_000 ether; // 100,000 DOC
uint256 constant FEE_PERCENTAGE_DIVISOR = 10_000;
uint256 constant MAX_SCHEDULES_PER_USER = 10; // Default to a maximum of 10 DCA schedules per user

// Chain IDs
uint256 constant ANVIL_CHAIN_ID = 31337;
uint256 constant RSK_MAINNET_CHAIN_ID = 30;
uint256 constant RSK_TESTNET_CHAIN_ID = 31;


// Default configurations
uint256 constant DEFAULT_AMOUNT_OUT_MINIMUM_PERCENT = 0.995 ether; // 99.5% -> 0.5% slippage
uint256 constant DEFAULT_AMOUNT_OUT_MINIMUM_SAFETY_CHECK = 0.95 ether; // 95%
uint256 constant MAX_SLIPPAGE_PERCENT = 1 ether - DEFAULT_AMOUNT_OUT_MINIMUM_PERCENT; 

/*//////////////////////////////////////////////////////////////
                        TESTS CONSTANTS
//////////////////////////////////////////////////////////////*/

// Test account names
string constant OWNER_STRING = "owner";
string constant USER_STRING = "user";
string constant SWAPPER_STRING = "swapper";
string constant FEE_COLLECTOR_STRING = "feeCollector";

// Test values
uint256 constant BTC_PRICE = 100_000; // 1 BTC = 100,000 DOC

// Token holders on mainnet with significant balances (for fork testing)
address constant DOC_HOLDER = 0x65d189e839aF28B78567bD7255f3f796495141bc; // Large DOC holder on RSK mainnet
// Token holders on testnet with significant balances (for fork testing)
address constant DOC_HOLDER_TESTNET = 0x53Ec0aF115619c536480C95Dec4a065e27E6419F; // Large DOC holder on RSK testnet

// Network-specific addresses
address constant DOC_TOKEN_MAINNET = 0xe700691dA7b9851F2F35f8b8182c69c53CcaD9Db;
address constant MOC_PROXY_MAINNET = 0xf773B590aF754D597770937Fa8ea7AbDf2668370;
address constant FEE_COLLECTOR_MAINNET = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;
address constant OWNER_MAINNET = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;
address constant SWAPPER_MAINNET = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;

address constant DOC_TOKEN_TESTNET = 0xCB46c0ddc60D18eFEB0E586C17Af6ea36452Dae0;
address constant MOC_PROXY_TESTNET = 0x2820f6d4D199B8D8838A4B26F9917754B86a0c1F;
// address constant FEE_COLLECTOR_TESTNET = 0x31e0FacEa072EE621f22971DF5bAE3a1317E41A4;
// address constant OWNER_TESTNET = 0x31e0FacEa072EE621f22971DF5bAE3a1317E41A4;
// address constant SWAPPER_TESTNET = 0x31e0FacEa072EE621f22971DF5bAE3a1317E41A4;
address constant FEE_COLLECTOR_TESTNET = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;
address constant OWNER_TESTNET = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;
address constant SWAPPER_TESTNET = 0x226E865Ab298e542c5e5098694eFaFfe111F93D3;