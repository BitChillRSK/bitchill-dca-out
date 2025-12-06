# =============================================================================
# BitChill DCA Out - Foundry Project Makefile
# =============================================================================

# Default target
.DEFAULT_GOAL := help

# Variables
FOUNDRY_PROFILE ?= default
MAINNET_RPC_URL ?= $(shell echo $$MAINNET_RPC_URL)
TESTNET_RPC_URL ?= $(shell echo $$TESTNET_RPC_URL)
BLOCK_NUMBER_MAINNET ?= latest
BLOCK_NUMBER_TESTNET ?= latest

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# =============================================================================
# Help
# =============================================================================

.PHONY: help
help: ## Show this help message
	@echo "$(BLUE)BitChill DCA Out - Foundry Project Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# =============================================================================
# Environment Setup
# =============================================================================

.PHONY: install
install: ## Install dependencies
	@echo "$(BLUE)Installing Foundry dependencies...$(NC)"
	forge install
	@echo "$(GREEN)Dependencies installed successfully!$(NC)"

.PHONY: update
update: ## Update dependencies
	@echo "$(BLUE)Updating Foundry dependencies...$(NC)"
	forge update
	@echo "$(GREEN)Dependencies updated successfully!$(NC)"

.PHONY: clean
clean: ## Clean build artifacts and cache
	@echo "$(BLUE)Cleaning build artifacts and cache...$(NC)"
	forge clean
	rm -rf cache/out
	@echo "$(GREEN)Clean completed!$(NC)"

.PHONY: build
build: ## Build the project
	@echo "$(BLUE)Building contracts...$(NC)"
	forge build --optimize --optimizer-runs 200
	@echo "$(GREEN)Build completed successfully!$(NC)"

# =============================================================================
# Local Testing (with mocks)
# =============================================================================

.PHONY: test
test: ## Run all unit tests locally
	@echo "$(BLUE)Running all unit tests locally...$(NC)"
	forge test --verbosity 2

.PHONY: test-gas
test-gas: ## Run tests with gas reporting
	@echo "$(BLUE)Running tests with gas reporting...$(NC)"
	forge test --gas-report

.PHONY: test-coverage
test-coverage: ## Run tests with coverage reporting
	@echo "$(BLUE)Running tests with coverage...$(NC)"
	forge coverage --report lcov
	@echo "$(YELLOW)Coverage report generated: lcov.info$(NC)"

.PHONY: test-debug
test-debug: ## Run tests in debug mode (stops on first failure)
	@echo "$(BLUE)Running tests in debug mode...$(NC)"
	forge test -vvv --fail-fast

# =============================================================================
# Fork Testing
# =============================================================================

.PHONY: test-fork-mainnet
test-fork-mainnet: ## Run fork tests against RSK mainnet
	@echo "$(BLUE)Running fork tests against RSK mainnet...$(NC)"
	@if [ -z "$(MAINNET_RPC_URL)" ]; then \
		echo "$(RED)Error: MAINNET_RPC_URL environment variable not set$(NC)"; \
		echo "$(YELLOW)Set it with: export MAINNET_RPC_URL=your_rpc_url$(NC)"; \
		exit 1; \
	fi
	forge test --fork-url $(MAINNET_RPC_URL) --fork-block-number $(BLOCK_NUMBER_MAINNET) --match-path "test/unit/*.sol" -vv

.PHONY: test-fork-testnet
test-fork-testnet: ## Run fork tests against RSK testnet
	@echo "$(BLUE)Running fork tests against RSK testnet...$(NC)"
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "$(RED)Error: TESTNET_RPC_URL environment variable not set$(NC)"; \
		echo "$(YELLOW)Set it with: export TESTNET_RPC_URL=your_rpc_url$(NC)"; \
		exit 1; \
	fi
	forge test --fork-url $(TESTNET_RPC_URL) --fork-block-number $(BLOCK_NUMBER_TESTNET) --match-path "test/unit/*.sol" -vv

.PHONY: test-fork-both
test-fork-both: ## Run fork tests against both mainnet and testnet
	@echo "$(BLUE)Running fork tests against both networks...$(NC)"
	$(MAKE) test-fork-mainnet
	$(MAKE) test-fork-testnet

# =============================================================================
# Specific Test Suites
# =============================================================================

.PHONY: test-sale
test-sale: ## Run only SaleTest suite
	@echo "$(BLUE)Running SaleTest suite...$(NC)"
	forge test --match-contract SaleTest -vv

.PHONY: test-schedule
test-schedule: ## Run only ScheduleTest suite
	@echo "$(BLUE)Running ScheduleTest suite...$(NC)"
	forge test --match-contract ScheduleTest -vv

.PHONY: test-admin
test-admin: ## Run only AdminTest suite
	@echo "$(BLUE)Running AdminTest suite...$(NC)"
	forge test --match-contract AdminTest -vv

.PHONY: test-fee
test-fee: ## Run only FeeHandlerTest suite
	@echo "$(BLUE)Running FeeHandlerTest suite...$(NC)"
	forge test --match-contract FeeHandlerTest -vv

.PHONY: test-getter
test-getter: ## Run only GetterTest suite
	@echo "$(BLUE)Running GetterTest suite...$(NC)"
	forge test --match-contract GetterTest -vv

# =============================================================================
# Deployment Scripts
# =============================================================================

.PHONY: deploy-local
deploy-local: ## Deploy to local Anvil network
	@echo "$(BLUE)Deploying to local Anvil network...$(NC)"
	forge script script/DeployDcaOut.s.sol --fork-url http://localhost:8545 --broadcast --verify

.PHONY: deploy-testnet
deploy-testnet: ## Deploy to RSK testnet
	@echo "$(BLUE)Deploying to RSK testnet...$(NC)"
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "$(RED)Error: TESTNET_RPC_URL environment variable not set$(NC)"; \
		exit 1; \
	fi
	forge script script/DeployDcaOut.s.sol --fork-url $(TESTNET_RPC_URL) --broadcast --verify

.PHONY: deploy-mainnet
deploy-mainnet: ## Deploy to RSK mainnet
	@echo "$(BLUE)Deploying to RSK mainnet...$(NC)"
	@if [ -z "$(MAINNET_RPC_URL)" ]; then \
		echo "$(RED)Error: MAINNET_RPC_URL environment variable not set$(NC)"; \
		exit 1; \
	fi
	@echo "$(RED)WARNING: Deploying to mainnet!$(NC)"
	@read -p "Are you sure you want to continue? (y/N) " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "$(YELLOW)Deployment cancelled.$(NC)"; \
		exit 1; \
	fi
	forge script script/DeployDcaOut.s.sol --fork-url $(MAINNET_RPC_URL) --broadcast --verify

.PHONY: deploy-seed-testnet
deploy-seed-testnet: ## Deploy and seed schedules on testnet
	@echo "$(BLUE)Deploying and seeding schedules on RSK testnet...$(NC)"
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "$(RED)Error: TESTNET_RPC_URL environment variable not set$(NC)"; \
		exit 1; \
	fi
	forge script script/DeployAndSeedSchedules.s.sol --fork-url $(TESTNET_RPC_URL) --broadcast --verify

# =============================================================================
# Local Development Environment
# =============================================================================

.PHONY: anvil
anvil: ## Start local Anvil network
	@echo "$(BLUE)Starting Anvil local network...$(NC)"
	@echo "$(YELLOW)Network running on http://localhost:8545$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	anvil --host 0.0.0.0 --port 8545

.PHONY: anvil-fork-mainnet
anvil-fork-mainnet: ## Start Anvil with mainnet fork
	@echo "$(BLUE)Starting Anvil with RSK mainnet fork...$(NC)"
	@if [ -z "$(MAINNET_RPC_URL)" ]; then \
		echo "$(RED)Error: MAINNET_RPC_URL environment variable not set$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Forked network running on http://localhost:8545$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	anvil --fork-url $(MAINNET_RPC_URL) --fork-block-number $(BLOCK_NUMBER_MAINNET) --host 0.0.0.0 --port 8545

.PHONY: anvil-fork-testnet
anvil-fork-testnet: ## Start Anvil with testnet fork
	@echo "$(BLUE)Starting Anvil with RSK testnet fork...$(NC)"
	@if [ -z "$(TESTNET_RPC_URL)" ]; then \
		echo "$(RED)Error: TESTNET_RPC_URL environment variable not set$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Forked network running on http://localhost:8545$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	anvil --fork-url $(TESTNET_RPC_URL) --fork-block-number $(BLOCK_NUMBER_TESTNET) --host 0.0.0.0 --port 8545

# =============================================================================
# Utility Commands
# =============================================================================

.PHONY: lint
lint: ## Run Solidity linter
	@echo "$(BLUE)Running Solidity linter...$(NC)"
	forge fmt --check
	@echo "$(GREEN)Linting completed!$(NC)"

.PHONY: format
format: ## Format Solidity code
	@echo "$(BLUE)Formatting Solidity code...$(NC)"
	forge fmt
	@echo "$(GREEN)Code formatted!$(NC)"

.PHONY: snapshot
snapshot: ## Create a snapshot of current test gas usage
	@echo "$(BLUE)Creating gas snapshot...$(NC)"
	forge snapshot
	@echo "$(GREEN)Gas snapshot created!$(NC)"

.PHONY: flatten
flatten: ## Flatten contracts for verification
	@echo "$(BLUE)Flattening contracts...$(NC)"
	@echo "$(YELLOW)Main contract:$(NC)"
	forge flatten src/DcaOutManager.sol > flattened/DcaOutManager.sol
	@echo "$(YELLOW)FeeHandler contract:$(NC)"
	forge flatten src/FeeHandler.sol > flattened/FeeHandler.sol
	@echo "$(GREEN)Contracts flattened to flattened/ directory$(NC)"

.PHONY: size
size: ## Show contract sizes
	@echo "$(BLUE)Analyzing contract sizes...$(NC)"
	forge build --sizes

.PHONY: tree
tree: ## Show project structure
	@echo "$(BLUE)Project structure:$(NC)"
	tree -I 'node_modules|lib|out|cache|broadcast' --dirsfirst

.PHONY: env-check
env-check: ## Check environment setup
	@echo "$(BLUE)Environment check:$(NC)"
	@echo "Foundry version: $(shell forge --version)"
	@echo "Mainnet RPC URL: $(if $(MAINNET_RPC_URL),✓ Set,✗ Not set)"
	@echo "Testnet RPC URL: $(if $(TESTNET_RPC_URL),✓ Set,✗ Not set)"
	@echo "Current directory: $(shell pwd)"
	@echo "Git branch: $(shell git branch --show-current 2>/dev/null || echo 'Not a git repo')"

# =============================================================================
# CI/CD Commands
# =============================================================================

.PHONY: ci
ci: clean install build test ## Run full CI pipeline
	@echo "$(GREEN)CI pipeline completed successfully!$(NC)"

.PHONY: ci-fork
ci-fork: clean install build test test-fork-both ## Run CI with fork tests
	@echo "$(GREEN)CI pipeline with fork tests completed successfully!$(NC)"

# =============================================================================
# Quick Commands for Development
# =============================================================================

.PHONY: dev-setup
dev-setup: install build test ## Set up development environment
	@echo "$(GREEN)Development environment ready!$(NC)"

.PHONY: quick-test
quick-test: ## Run quick test suite (no gas reporting)
	@echo "$(BLUE)Running quick tests...$(NC)"
	forge test --match-path "test/unit/*.sol" -q

.PHONY: watch
watch: ## Watch for changes and run tests automatically
	@echo "$(BLUE)Watching for changes...$(NC)"
	@echo "$(YELLOW)Tests will run automatically on file changes$(NC)"
	find src test -name "*.sol" | entr -c make quick-test
