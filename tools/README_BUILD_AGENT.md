## xcodebuild agent wrapper

Use `tools/xcodebuild_agent.sh` to build/test with repo-local caches and generic iOS destination (no simulator service needed).

Examples:
```
./tools/xcodebuild_agent.sh build
./tools/xcodebuild_agent.sh test
```

The script sets:
- `HOME`, `XDG_CACHE_HOME`, `SWIFT_MODULE_CACHE_PATH`, `LLVM_MODULE_CACHE_PATH`, `CLANG_MODULE_CACHE_PATH`, `TMPDIR` → repo-local paths
- `-derivedDataPath` → `.derivedData`
- `-clonedSourcePackagesDirPath` → `.spm`

If package fetch fails due to offline network, vendor or pre-populate `.spm`/SourcePackages, then rerun the wrapper.
