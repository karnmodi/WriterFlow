SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
CONFIG ?= debug

.PHONY: help build test lint bundle run clean stop relaunch install install-run

help:
	@echo "WriterFlow build targets:"
	@echo "  make build       — swift build (CONFIG=debug|release)"
	@echo "  make test        — swift test"
	@echo "  make lint        — swiftlint (requires 'brew install swiftlint')"
	@echo "  make bundle      — build + wrap as build/WriterFlow.app"
	@echo "  make install     — install to ~/Applications/WriterFlow.app (stable permissions)"
	@echo "  make install-run — install + quit old + launch from ~/Applications"
	@echo "  make run         — stop old instance, build bundle, launch build/"
	@echo "  make stop        — quit all running WriterFlow instances"
	@echo "  make relaunch    — clean + bundle + launch (fresh build)"
	@echo "  make clean       — remove .build and build/"

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

stop:
	@pkill -x WriterFlow 2>/dev/null && echo "Stopped WriterFlow." || echo "No WriterFlow process running."
	@sleep 0.5

run: bundle stop
	open build/WriterFlow.app
	@echo ""
	@echo "WriterFlow launched."
	@echo "  App path: $$(pwd)/build/WriterFlow.app"
	@echo "  • Look for the highlighter  WF  icon in the menu bar (top-right)."
	@echo "  • A setup window should appear — grant Accessibility + Input Monitoring."
	@echo "  • In Input Monitoring: click + and select the app path above."
	@echo ""

relaunch: clean bundle stop
	open build/WriterFlow.app
	@echo ""
	@echo "WriterFlow relaunched (clean build)."
	@echo "  App path: $$(pwd)/build/WriterFlow.app"
	@echo "  Note: after clean builds, re-pair Accessibility (see Setup → Repair Accessibility)"
	@echo ""

install:
	chmod +x scripts/install.sh
	scripts/install.sh $(CONFIG)

install-run: install stop
	open "$(HOME)/Applications/WriterFlow.app"
	@echo ""
	@echo "WriterFlow launched from ~/Applications/WriterFlow.app"
	@echo "  (stable path — permissions persist across rebuilds)"
	@echo ""

clean:
	rm -rf .build build
