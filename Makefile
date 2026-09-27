APP := Reelcut
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP).app
# The Distribution configuration's product (`make dist`): Release without
# REELCUT_DEV_TOOLS, in its own products folder beside Release's.
DIST_PATH := $(BUILD_DIR)/Build/Products/Distribution/$(APP).app

# `xcodebuild` records every task's ENVIRONMENT in its build database under
# build/Build/Intermediates.noindex/XCBuildData/, so a `make app` from a shell
# that exports the AssemblyAI key writes that key to disk
# (road map 6 §10.12, measured). `unexport` covers every
# recipe in this file, which is what the proofs' own `child_env()` already
# does for themselves; `tools/proof/makefile_env_proof.py` measures `app`.
unexport RC_ASSEMBLYAI_KEY

.PHONY: all app dist rust test lint fmt typecheck project run clean

all: app

rust:
	cd core && cargo build --release

test:
	cd core && cargo test --release
	cd graphic && cargo test --release

lint:
	cd core && cargo clippy --all-targets -- -D warnings
	cd graphic && cargo clippy --all-targets -- -D warnings

fmt:
	cd core && cargo fmt
	cd graphic && cargo fmt

project:
	xcodegen generate

app: rust project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

# Builds the Distribution configuration (Release without REELCUT_DEV_TOOLS,
# spec §11 V-1) beside Release's product, then runs the binary check: the
# dev-tools marker must be absent from Distribution's binary and present in
# Release's, which is its positive control. The file-wide
# `unexport RC_ASSEMBLYAI_KEY` above covers this recipe too.
dist: app
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Distribution \
		-derivedDataPath $(BUILD_DIR) build
	python3 tools/proof/dist_check.py --release "$(APP_PATH)" --dist "$(DIST_PATH)"

# Fast compile check of the Swift sources without a full Xcode build.
# `-D REELCUT_DEV_TOOLS` as Debug and Release set it (project.yml); the
# flag-OFF path, what Distribution ships, is compiled only by `make dist`.
typecheck:
	swiftc -typecheck \
		-D REELCUT_DEV_TOOLS \
		-sdk "$$(xcrun --show-sdk-path --sdk macosx)" \
		-target arm64-apple-macos26.0 \
		-import-objc-header app/Bridging/Reelcut-Bridging-Header.h \
		app/Sources/*.swift

run: app
	open "$(APP_PATH)"

clean:
	rm -rf $(BUILD_DIR) $(APP).xcodeproj app/Info.plist
	cd core && cargo clean
	cd graphic && cargo clean
