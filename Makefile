# Include .env file
include .env

.PHONY: tests

tests:
	forge test --fork-url $(RPC_URL)
