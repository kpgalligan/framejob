APP := Reelcut
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP).app
# The Distribution configuration's product (`make dist`): Release without
# REELCUT_DEV_TOOLS, in its own products folder beside Release's.
DIST_PATH := $(BUILD_DIR)/Build/Products/Distribution/$(APP).app

# `xcodebuild` records every task's ENVIRONMENT in its build database under
# build/Build/Intermediates.noindex/XCBuildData/, so a `make app` from a shell
# that exports the AssemblyAI key or the Anthropic key writes that key to disk
# (road map 6 §10.12, measured). `unexport` covers every
# recipe in this file, which is what the proofs' own `child_env()` already
# does for themselves; `tools/proof/makefile_env_proof.py` measures `app`,
# one "holds the dummy" row per key.
unexport RC_ASSEMBLYAI_KEY
unexport ANTHROPIC_API_KEY

.PHONY: all app dist rust test lint fmt typecheck project run clean prices

all: app

rust:
	cd core && cargo build --release

# `assistant_lane_proof.py` is spec §11 AI-3's `make test`-reachable probe
# (the agent lane); `rust` first, because it links the staticlib.
# `prices_proof.py` is road map 13 P1's price function: the Python reader and
# the helper's `bun test` (agent/build.sh test) against one fixture file, no
# network. `budget_proof.py` is P3's proofs' ledger and monthly budgets (spec
# §11 P-6), over scratch ledgers only, no network. `inventory.py --check` checks the
# menu inventory's sites against app/Sources, each found by its token and
# enclosing function rather than its line, and its other citations by
# anchor; no app, no build. `spec_index_proof.py` (issue batch B70) checks the
# spec indexes' Lines cells against `wc -l` and a row for every spec file.
# `proof_defaults.py` (issue batch B83, #238) is the defaults removal recipe
# on a throwaway domain, its refusals over scratch folders, then the sweep of
# the proofs' own idle domains, and of the two probes this target ran, out of
# `~/Library/Preferences`; no app.
# `mcp-proxy` is road map 14's `reelcut-mcp`, its tests black-box over the
# built binary's stdin and stdout.
test: rust
	cd core && cargo test --release
	cd graphic && cargo test --release
	cd mcp-proxy && cargo test --release
	python3 tools/proof/assistant_lane_proof.py
	python3 tools/proof/assistant_prompt_proof.py --probe
	python3 tools/proof/prices_proof.py
	python3 tools/proof/budget_proof.py
	python3 tools/proof/capture_spike/inventory.py --check
	python3 tools/proof/spec_index_proof.py
	python3 tools/proof/proof_defaults.py --ran assistant_lane_probe --ran assistant_prompt_probe

lint:
	cd core && cargo clippy --all-targets -- -D warnings
	cd graphic && cargo clippy --all-targets -- -D warnings
	cd mcp-proxy && cargo clippy --all-targets -- -D warnings

fmt:
	cd core && cargo fmt
	cd graphic && cargo fmt
	cd mcp-proxy && cargo fmt

project:
	xcodegen generate

app: rust project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

# Builds the Distribution configuration (Release without REELCUT_DEV_TOOLS,
# spec §11 V-1) beside Release's product, then runs the binary check: the
# dev-tools marker must be absent from Distribution's binary and present in
# Release's, which is its positive control; and each bundle's assistant helper
# (Contents/Helpers/reelcut-agent) must be present, signed with the hardened
# runtime, hold exactly the allow-jit entitlement and not hold the marker
# (road map 12 A4, D6–D13); and the Distribution app must be signed with
# exactly the audio-input entitlement, never get-task-allow (#145, D14); and
# each bundle's MCP proxy (Contents/Helpers/reelcut-mcp) must be present,
# signed with the hardened runtime and hold no entitlements, and its catalog
# snapshot (Contents/Resources/agent-catalog.json) must be at the bundle's
# version, Release's naming every dev tool and Distribution's none (road map
# 14 MC3, D15–D24). The file-wide `unexport RC_ASSEMBLYAI_KEY` above covers
# this recipe too.
dist: app
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Distribution \
		-derivedDataPath $(BUILD_DIR) build
	python3 tools/proof/dist_check.py --release "$(APP_PATH)" --dist "$(DIST_PATH)"

# Fast compile check of the Swift sources without a full Xcode build.
# `-D REELCUT_DEV_TOOLS` as Debug and Release set it (project.yml); the
# flag-OFF path, what Distribution ships, is compiled only by `make dist`.
# The last line is agent/'s `tsc --noEmit`, through bun (agent/build.sh),
# which fails rather than skips when bun is missing.
typecheck:
	swiftc -typecheck \
		-D REELCUT_DEV_TOOLS \
		-sdk "$$(xcrun --show-sdk-path --sdk macosx)" \
		-target arm64-apple-macos26.0 \
		-import-objc-header app/Bridging/Reelcut-Bridging-Header.h \
		app/Sources/*.swift
	/bin/sh agent/build.sh typecheck

# Regenerates agent/prices/anthropic.json from LiteLLM's table over the
# network (spec §11 P-1); the only writer of that file. Never a prerequisite
# of app, test, typecheck or dist.
prices:
	python3 agent/prices/update.py

run: app
	open "$(APP_PATH)"

clean:
	rm -rf $(BUILD_DIR) $(APP).xcodeproj app/Info.plist
	cd core && cargo clean
	cd graphic && cargo clean
	cd mcp-proxy && cargo clean
