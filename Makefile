SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
CONFIG ?= debug

.PHONY: help build test lint bundle compatibility-build run clean stop relaunch install install-run dmg verify-release release xcodeproj scan-v2-release

help:
	@echo "WriterFlow build targets:"
	@echo "  make xcodeproj   — (re)generate WriterFlow.xcodeproj from project.yml (needs 'brew install xcodegen')"
	@echo "  make build       — swift build (CONFIG=debug|release)"
	@echo "  make test        — swift test"
	@echo "  make lint        — swiftlint (requires 'brew install swiftlint')"
	@echo "  make bundle      — build + wrap as build/WriterFlow.app"
	@echo "  make compatibility-build — compile macOS 14 Release slices for arm64 + x86_64"
	@echo "  make install     — install to ~/Applications/WriterFlow.app (stable permissions)"
	@echo "  make install-run — install + quit old + launch from ~/Applications"
	@echo "  make run         — install to ~/Applications + launch (stable TCC path)"
	@echo "  make stop        — quit all running WriterFlow instances"
	@echo "  make relaunch    — clean + install + launch (fresh build)"
	@echo "  make clean       — remove .build and build/"
	@echo "  make release     — V2 ONLY: Developer ID sign + notarize + staple (not a v1 requirement)"
	@echo "  make dmg         — package build/WriterFlow.app into a drag-to-Applications DMG (branded installer window)"
	@echo "  make verify-release — clean + universal release bundle + verify identity/secrets + DMG + checksum"

xcodeproj:
	@if command -v xcodegen >/dev/null; then \
		xcodegen generate ; \
		echo "Generated WriterFlow.xcodeproj — open it in Xcode for Signing & Capabilities." ; \
	else \
		echo "xcodegen not installed — run: brew install xcodegen" ; \
		exit 1 ; \
	fi

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

compatibility-build:
	scripts/check-macos-compatibility.sh --build

stop:
	@pkill -x WriterFlow 2>/dev/null && echo "Stopped WriterFlow." || echo "No WriterFlow process running."
	@sleep 0.5

# Prefer ~/Applications so Accessibility / Input Monitoring survive rebuilds.
# Opening build/WriterFlow.app directly often looks granted but TCC is stale.
run: install-run

relaunch: clean install-run
	@echo "  Note: after clean builds, re-pair Accessibility to ~/Applications/WriterFlow.app if needed."

install:
	chmod +x scripts/install.sh
	scripts/install.sh $(CONFIG)

install-run: install stop
	open "$(HOME)/Applications/WriterFlow.app"
	@echo ""
	@echo "WriterFlow launched from ~/Applications/WriterFlow.app"
	@echo "  (stable path — permissions persist across rebuilds)"
	@echo ""

release:
	scripts/release.sh

dmg:
	scripts/make-dmg.sh

verify-release:
	scripts/release-v1.sh

scan-v2-release:
	node scripts/scan-v2-release.mjs build/WriterFlow.app

clean:
	rm -rf .build build
