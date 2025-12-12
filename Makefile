# BitChill DCA Out - Foundry Project Makefile

# Default target
.DEFAULT_GOAL := test

# Load environment variables from .env file if it exists
ifneq (,$(wildcard .env))
include .env
export
endif

# Environment variables with fallbacks
MAINNET_RPC_URL ?= $(shell echo $$MAINNET_RPC_URL)
TESTNET_RPC_URL ?= $(shell echo $$TESTNET_RPC_URL)
BLOCKSCOUT_API_URL ?= $(shell echo $$BLOCKSCOUT_API_URL)

# =============================================================================
# Core Commands
# =============================================================================

.PHONY: test
test: ## Run all unit tests
	forge test -v

.PHONY: test-mainnet
test-mainnet: ## Run fork tests against RSK mainnet
	@if [ -z "$(MAINNET_RPC_URL)" ]; then \
		echo "Error: Set MAINNET_RPC_URL environment variable"; \
		exit 1; \
	fi
	forge test --fork-url $(MAINNET_RPC_URL) -v

.PHONY: test-testnet
test-testnet: ## Run fork tests against RSK testnet
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "Error: Set TESTNET_RPC_URL environment variable"; \
		exit 1; \
	fi
	forge test --fork-url $(TESTNET_RPC_URL) -v


# =============================================================================
# Deployment
# =============================================================================

.PHONY: deploy-local
deploy-local: ## Deploy to local Anvil
	forge script script/DeployDcaOut.s.sol --fork-url http://localhost:8545 --broadcast

.PHONY: deploy-testnet
deploy-testnet: ## Deploy to RSK testnet
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "Error: Set TESTNET_RPC_URL environment variable"; \
		exit 1; \
	fi
	REAL_DEPLOYMENT=true \
	forge script script/DeployDcaOut.s.sol \
		--rpc-url $(TESTNET_RPC_URL) \
		--account dev_wallet \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url $(BLOCKSCOUT_API_URL) \
		--legacy

.PHONY: deploy-mainnet
deploy-mainnet: ## Deploy to RSK mainnet (CAUTION!)
	@if [ -z "$(MAINNET_RPC_URL)" ]; then \
		echo "Error: Set MAINNET_RPC_URL environment variable"; \
		exit 1; \
	fi
	@echo "WARNING: Deploying to mainnet!"
	REAL_DEPLOYMENT=true \
	forge script script/DeployDcaOut.s.sol \
		--rpc-url $(MAINNET_RPC_URL) \
		--account dev_wallet \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url $(BLOCKSCOUT_API_URL) \
		--legacy

.PHONY: deploy-seed-testnet
deploy-seed-testnet: ## Deploy to RSK testnet and seed test schedules
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "Error: Set TESTNET_RPC_URL environment variable"; \
		exit 1; \
	fi
	@echo "WARNING: This uses plain text private keys from .env for testing"
	REAL_DEPLOYMENT=true \
	forge script script/DeployAndSeedSchedules.s.sol \
		--rpc-url $(TESTNET_RPC_URL) \
		--account dev_wallet \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url $(BLOCKSCOUT_API_URL) \
		--legacy

# =============================================================================
# Utilities
# =============================================================================

.PHONY: format
format: ## Format Solidity code
	forge fmt

.PHONY: help
help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "%-20s %s\n", $$1, $$2}'
