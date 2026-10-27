APP := FrameJob
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/Frame Job.app
# The Distribution configuration's product (`make dist`): Release without
# FRAMEJOB_DEV_TOOLS, in its own products folder beside Release's.
DIST_PATH := $(BUILD_DIR)/Build/Products/Distribution/Frame Job.app
# The Debug configuration's product (`make app-debug`): "Frame Job Debug",
# com.kgalligan.FrameJob.debug (spec §11 V-5), in its own products folder.
DEBUG_APP_PATH := $(BUILD_DIR)/Build/Products/Debug/Frame Job Debug.app

# `xcodebuild` records every task's ENVIRONMENT in its build database under
# build/Build/Intermediates.noindex/XCBuildData/, so a `make app` from a shell
# that exports the AssemblyAI key or the Anthropic key writes that key to disk
# (road map 6 §10.12, measured). `unexport` covers every
# recipe in this file, which is what the proofs' own `child_env()` already
# does for themselves; `tools/proof/makefile_env_proof.py` measures `app`,
# one "holds the dummy" row per key.
unexport RC_ASSEMBLYAI_KEY
unexport ANTHROPIC_API_KEY

.PHONY: all app app-debug dist rust codecs test lint fmt typecheck project run clean prices gate

all: app

rust:
	cd core && cargo build --release

# The bundled encoders (road map "codec-export" C0, spec §11 CX-4, CX-5): SVT-AV1
# and libvpx from pinned, SHA-256-checked tarballs, built arm64, static and
# encoder-only into build/codecs/ (headers, archives, licence texts), reused
# by its stamp — like cargo, a no-op when nothing changed. Needs cmake
# (`brew install cmake`), the system perl, and the network for the first
# fetch. project.yml's "Build Codecs" step runs the same script.
codecs:
	python3 tools/codecs/build_codecs.py

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
# `mcp-proxy` is road map 14's `framejob-mcp`, its tests black-box over the
# built binary's stdin and stdout. `name_residue.py` (spec §11 NM-8) fails
# on any line or path spelling the old name that its allow-list does not
# hold; its selftest runs first. `appcast.py --selftest` (spec §11 PUB-6, PUB-8)
# is the publish workflow's appcast writer over a stand-in `sign_update`: no
# network, no key. `build_codecs.py --selftest` (codec-export C0) is the
# encoder build's key, reuse and digest rules, no network and no cmake; `codecs`
# first, because swift_build.py's selftest links the archives.
test: rust codecs
	cd core && cargo test --release
	cd graphic && cargo test --release
	cd mcp-proxy && cargo test --release
	python3 tools/proof/assistant_lane_proof.py
	python3 tools/proof/assistant_prompt_proof.py --probe
	python3 tools/proof/prices_proof.py
	python3 tools/proof/budget_proof.py
	python3 tools/proof/capture_spike/inventory.py --check
	python3 tools/proof/spec_index_proof.py
	python3 tools/codecs/build_codecs.py --selftest
	python3 tools/proof/swift_build.py --selftest
	python3 tools/proof/proof_app.py --selftest
	python3 tools/proof/gate.py --selftest
	python3 tools/proof/appcast.py --selftest
	python3 tools/proof/proof_defaults.py --ran assistant_lane_probe --ran assistant_prompt_probe
	python3 tools/proof/name_residue.py --selftest
	python3 tools/proof/name_residue.py

lint:
	cd core && cargo clippy --all-targets -- -D warnings
	cd graphic && cargo clippy --all-targets -- -D warnings
	cd mcp-proxy && cargo clippy --all-targets -- -D warnings

fmt:
	cd core && cargo fmt
	cd graphic && cargo fmt
	cd mcp-proxy && cargo fmt

# The base version is the VERSION file (spec §11 PUB-2, Rasterize's scheme),
# passed to xcodegen as RC_BASE_VERSION for project.yml's MARKETING_VERSION. A
# missing VERSION stops here rather than generating a project with a blank
# version; a bare `xcodegen generate` has no such guard, so never run it.
project:
	base="$$(cat VERSION)" && RC_BASE_VERSION="$$base" xcodegen generate

app: rust codecs project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

# The Debug app the proofs can drive (tools/proof/proof_app.py): unoptimised,
# so it rebuilds in seconds after a one-file edit; never the index store.
app-debug: rust codecs project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) COMPILER_INDEX_STORE_ENABLE=NO build

# Builds the Distribution configuration (Release without FRAMEJOB_DEV_TOOLS,
# spec §11 V-1) beside Release's product, then runs the binary check: the
# dev-tools marker must be absent from Distribution's binary and present in
# Release's, which is its positive control; and each bundle's assistant helper
# (Contents/Helpers/framejob-agent) must be present, signed with the hardened
# runtime, hold exactly the allow-jit entitlement and not hold the marker
# (road map 12 A4, D6–D13); and the Distribution app must be signed with
# exactly the audio-input and camera entitlements, never get-task-allow
# (#145, spec §11 CAM-3, D14); and
# each bundle's MCP proxy (Contents/Helpers/framejob-mcp) must be present,
# signed with the hardened runtime and hold no entitlements, and its catalog
# snapshot (Contents/Resources/agent-catalog.json) must be at the bundle's
# version, Release's naming every dev tool and Distribution's none (road map
# 14 MC3, D15–D24); and the Release app must be signed with exactly Xcode's
# audio-input, camera and get-task-allow, and both apps must pass `codesign --verify
# --deep --strict` (issue batch B88, D25–D27); and the updater (spec §11
# PUB-6..PUB-9, D28–D35): Distribution's Sparkle.framework signed with the
# app's team and its helpers with the hardened runtime, its feed and a 32-byte
# EdDSA public key, Release's both empty, the updater's code
# (FRAMEJOB_UPDATER, compiled by this target alone) in Distribution's binary
# and not in Release's, and no Sparkle load command in Release's. Until the owner's public key lands, D31 and P20 fail
# by the owner's choice (PUB-8). The file-wide `unexport RC_ASSEMBLYAI_KEY`
# above covers this recipe too. `published_check.py` is the check the publish
# workflow runs over the app it is about to pack (spec §11 PUB-4), run here over
# the Distribution build so it cannot rot between two publishes; it runs even
# when `dist_check.py` fails, and the recipe exits non-zero if either failed.
dist: app
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Distribution \
		-derivedDataPath $(BUILD_DIR) build
	rc=0; python3 tools/proof/dist_check.py --release "$(APP_PATH)" --dist "$(DIST_PATH)" || rc=1; python3 tools/proof/published_check.py --app "$(DIST_PATH)" || rc=1; exit $$rc

# The one Full verification command (issue batch B88, tools/proof/gate.py):
# typecheck (exactly its four baseline warnings), fmt --check, lint, test, then
# app with dist_check's D25/D26 over the Release app; serial, stopping at the
# first failure, skipping a step whose inputs and tools are byte-identical to
# its last pass. Its state is build/gate/. `GATE_ARGS=--force` runs every step.
gate:
	python3 tools/proof/gate.py $(GATE_ARGS)

# Fast compile check of the Swift sources without a full Xcode build.
# `-D FRAMEJOB_DEV_TOOLS` as Debug and Release set it (project.yml); the
# flag-OFF path, what Distribution ships, is compiled only by `make dist`, and
# so is `FRAMEJOB_UPDATER` (AppDelegate+Updates.swift, Sparkle, Distribution
# alone, spec §11 PUB-7): this check has no Sparkle module to import.
# The last line is agent/'s `tsc --noEmit`, through bun (agent/build.sh),
# which fails rather than skips when bun is missing. `codecs` first: the
# bridging header includes the encoders' headers (CX-4), found by `-Xcc -I`.
typecheck: codecs
	swiftc -typecheck -enable-batch-mode -j "$$(sysctl -n hw.logicalcpu)" \
		-D FRAMEJOB_DEV_TOOLS \
		-sdk "$$(xcrun --show-sdk-path --sdk macosx)" \
		-target arm64-apple-macos26.0 \
		-import-objc-header app/Bridging/FrameJob-Bridging-Header.h \
		-Xcc -Ibuild/codecs/include \
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
