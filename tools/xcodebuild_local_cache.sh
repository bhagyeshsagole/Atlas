#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CI_HOME="$ROOT/.ci_home"
CI_CACHE="$ROOT/.ci_cache"
CI_DERIVED="$ROOT/.ci_derived"
CI_MODULE="$ROOT/.ci_module_cache"
CI_TMP="$ROOT/.ci_tmp"
CI_PACKAGES="$ROOT/.sourcepackages/SourcePackages"

mkdir -p "$CI_HOME/Library/Caches" "$CI_CACHE" "$CI_DERIVED" "$CI_MODULE/swift" "$CI_MODULE/clang" "$CI_TMP"

export HOME="$CI_HOME"
export XDG_CACHE_HOME="$CI_CACHE"
export TMPDIR="$CI_TMP"
export SWIFT_MODULE_CACHE_PATH="$CI_MODULE/swift"
export CLANG_MODULE_CACHE_PATH="$CI_MODULE/clang"
export LLVM_MODULE_CACHE_PATH="$CI_MODULE/clang"
export SOURCEPACKAGES_DIR="$CI_PACKAGES"

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16e}"
ACTION="${1:-build}"
shift || true

echo "[CI] HOME=$HOME"
echo "[CI] XDG_CACHE_HOME=$XDG_CACHE_HOME"
echo "[CI] TMPDIR=$TMPDIR"
echo "[CI] SWIFT_MODULE_CACHE_PATH=$SWIFT_MODULE_CACHE_PATH"
echo "[CI] CLANG_MODULE_CACHE_PATH=$CLANG_MODULE_CACHE_PATH"
echo "[CI] DERIVED=$CI_DERIVED"
echo "[CI] SOURCEPACKAGES=$CI_PACKAGES"
echo "[CI] DESTINATION=$DESTINATION"
echo "[CI] ACTION=$ACTION"

# Best-effort simulator service reset; ignore failures.
xcrun simctl shutdown all >/dev/null 2>&1 || true
killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
xcrun simctl list devices >/dev/null 2>&1 || true

exec xcodebuild \
  -scheme Atlas \
  -sdk iphonesimulator \
  -destination "$DESTINATION" \
  -derivedDataPath "$CI_DERIVED" \
  -clonedSourcePackagesDirPath "$CI_PACKAGES" \
  "$ACTION" "$@"

