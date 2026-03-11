SHELL := /bin/bash

.PHONY: bootstrap build test test-integration fuzz coverage fmt lint verify-deps verify-commits export-abis demo-local demo-testnet demo-stress demo-workflow ci

bootstrap:
	./scripts/bootstrap.sh

build:
	forge build

test:
	forge test

test-integration:
	forge test --match-path test/integration/* -vv

fuzz:
	forge test --match-path test/fuzz/* -vv

coverage:
	./scripts/verify_coverage.sh

fmt:
	forge fmt

lint:
	forge fmt --check

verify-deps:
	./scripts/verify_dependencies.sh

export-abis:
	./scripts/export_abis.sh

verify-commits:
	./scripts/verify_commits.sh

demo-local:
	./scripts/demo-local.sh

demo-testnet:
	./scripts/demo-testnet.sh

demo-stress:
	./scripts/demo-stress.sh

demo-workflow:
	./scripts/demo-workflow.sh

ci: verify-deps lint test coverage
