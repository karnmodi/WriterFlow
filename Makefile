SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
CONFIG ?= debug

.PHONY: help build test lint bundle run clean

help:
	@echo "WriterFlow build targets:"
	@echo "  make build   — swift build (CONFIG=debug|release)"
	@echo "  make test    — swift test"
	@echo "  make lint    — swiftlint (requires 'brew install swiftlint')"
	@echo "  make bundle  — build + wrap as build/WriterFlow.app"
	@echo "  make run     — build bundle and launch it"
	@echo "  make clean   — remove .build and build/"

build:
	swift build -c $(CONFIG)

test:
	swift test

lint:
	@if command -v swiftlint >/dev/null; then \
		swiftlint --config .swiftlint.yml ; \
	else \
		echo "swiftlint not installed — run: brew install swiftlint" ; \
		exit 1 ; \
	fi

bundle:
	scripts/bundle.sh $(CONFIG)

run: bundle
	open build/WriterFlow.app

clean:
	rm -rf .build build
