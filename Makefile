# Include .env file
include .env

.PHONY: build tests

build:
	forge build

tests:
	forge test --fork-url $(RPC_URL)
