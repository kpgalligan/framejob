APP := Reelcut
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP).app

# `xcodebuild` records every task's ENVIRONMENT in its build database under
# build/Build/Intermediates.noindex/XCBuildData/, so a `make app` from a shell
# that exports the AssemblyAI key writes that key to disk
# (`designs/reelcut-remaining.md` §5, measured). `unexport` covers every
# recipe in this file, which is what the proofs' own `child_env()` already
# does for themselves; `tools/proof/makefile_env_proof.py` measures `app`.
unexport RC_ASSEMBLYAI_KEY

.PHONY: all app rust test lint fmt typecheck project run clean

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

# Fast compile check of the Swift sources without a full Xcode build.
typecheck:
	swiftc -typecheck \
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
