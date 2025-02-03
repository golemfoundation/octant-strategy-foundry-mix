-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

# specify which fork to use. set this in our .env
# if we want to test multiple forks in one go, remove this as an argument below
FORK_URL := ${TEST_RPC_URL} # BASE_RPC_URL, ETH_RPC_URL, ARBITRUM_RPC_URL

# if we want to run only matching tests, set that here
test := test_

# local tests without fork
test  :; forge test -vv
trace  :; forge test -vvv
gas  :; forge test --gas-report
test-contract  :; forge test -vv --match-contract $(contract)
test-contract-gas  :; forge test --gas-report --match-contract ${contract}
trace-contract  :; forge test -vvv --match-contract $(contract)
test-test  :; forge test -vv --match-test $(test)
test-test-trace  :; forge test -vvv --match-test $(test)
trace-test  :; forge test -vvvvv --match-test $(test)
snapshot :; forge snapshot -vv
snapshot-diff :; forge snapshot --diff -vv
trace-setup  :; forge test -vvvv
trace-max  :; forge test -vvvvv
coverage :; forge coverage --ir-minimum
coverage-report :; forge coverage --ir-minimum --report lcov
coverage-debug :; forge coverage --ir-minimum --report debug

coverage-html:
	@echo "Running coverage..."
	forge coverage --ir-minimum --report lcov
	@if [ "`uname`" = "Darwin" ]; then \
		lcov --ignore-errors inconsistent --remove lcov.info 'src/test/**' --output-file lcov.info; \
		genhtml --ignore-errors inconsistent -o coverage-report lcov.info; \
	else \
		lcov --remove lcov.info 'src/test/**' --output-file lcov.info; \
		genhtml -o coverage-report lcov.info; \
	fi
	@echo "Coverage report generated at coverage-report/index.html"

clean  :; forge clean
