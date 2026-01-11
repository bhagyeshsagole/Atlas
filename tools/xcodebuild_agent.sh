#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME="$PWD/.agent_home"
export XDG_CACHE_HOME="$PWD/.agent_cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.agent_cache/swift-module-cache"
export LLVM_MODULE_CACHE_PATH="$PWD/.agent_cache/llvm-module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.agent_cache/clang-module-cache"
export TMPDIR="$PWD/.agent_tmp"
DERIVED="$PWD/.derivedData"
SPM_CACHE="$PWD/.spm"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$SWIFT_MODULE_CACHE_PATH" "$LLVM_MODULE_CACHE_PATH" "$CLANG_MODULE_CACHE_PATH" "$TMPDIR" "$DERIVED" "$SPM_CACHE"
CMD=${1:-build}
shift || true
xcodebuild -project Atlas.xcodeproj -scheme Atlas -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -clonedSourcePackagesDirPath "$SPM_CACHE" \
  -resolvePackageDependencies \
  $CMD "$@"
