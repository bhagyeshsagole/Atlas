#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME="$PWD/.agent_home"
export XDG_CACHE_HOME="$PWD/.agent_cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.agent_cache/swift-module-cache"
export LLVM_MODULE_CACHE_PATH="$PWD/.agent_cache/llvm-module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.agent_cache/clang-module-cache"
export MODULE_CACHE_DIR="$CLANG_MODULE_CACHE_PATH"
export DARWIN_USER_CACHE_DIR="$XDG_CACHE_HOME"
export DARWIN_USER_TEMP_DIR="$PWD/.agent_tmp"
export SWIFTPM_CUSTOM_CACHE_PATH="$XDG_CACHE_HOME/swiftpm"
export TMPDIR="$PWD/.agent_tmp"
DERIVED="$PWD/.derivedData"
SPM_CACHE="$PWD/.spm"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$SWIFT_MODULE_CACHE_PATH" "$LLVM_MODULE_CACHE_PATH" "$CLANG_MODULE_CACHE_PATH" "$TMPDIR" "$DERIVED" "$SPM_CACHE" "$MODULE_CACHE_DIR" "$SWIFTPM_CUSTOM_CACHE_PATH"
CMD=${1:-build}
shift || true
xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -clonedSourcePackagesDirPath "$SPM_CACHE" \
  -resolvePackageDependencies \
  $CMD "$@"
