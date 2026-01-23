# PostgreSQL Version Upgrade Guide

Quick guide for adding support for a new PostgreSQL version in pglite-build.

> **Detailed patch documentation:** See [`patches/README.md`](patches/README.md)

## Prerequisites

1. **postgres-pglite branch must exist** for your target version:
   ```bash
   git ls-remote --heads https://github.com/electric-sql/postgres-pglite | grep WASM
   ```

2. **Docker environment** must be set up (see `Dockerfile.wasi-builder`)

## Quick Steps

### 1. Create patch directory for new version

```bash
./patches/manage-patches.sh new-version REL_17_6_WASM REL_17_5_WASM
```

### 2. Clone the PostgreSQL source

```bash
git clone --branch REL_17_6_WASM \
  https://github.com/electric-sql/postgres-pglite \
  postgresql-REL_17_6_WASM
```

### 3. Check which patches apply

```bash
./patches/manage-patches.sh check REL_17_6_WASM
```

Output legend:
- `✓` - Patch applies cleanly
- `○` - Already applied (in postgres-pglite fork) → **delete the patch**
- `✗` - Failed → needs fixing

### 4. Fix failed patches

**If already applied** (common case):
```bash
rm patches-REL_17_6_WASM/category/failing-patch.diff
```

**If line numbers changed:**
```bash
# Edit patch file and update @@ line numbers
vim patches-REL_17_6_WASM/category/patch.diff
```

**If code changed significantly:**
```bash
cd postgresql-REL_17_6_WASM
# Make changes manually
git diff path/to/file.c > ../patches-REL_17_6_WASM/category/file.diff
```

### 5. Test the build

```bash
# WASI build
docker run --rm \
  -v "$(pwd)":/workspace \
  -v "$(pwd)/output:/tmp/sdk/dist" \
  pglite-wasi-builder \
  bash -c ". /tmp/sdk/wasm32-wasi-shell.sh && \
    PG_BRANCH=REL_17_6_WASM PG_VERSION=17.6 WASI=true ./wasm-build.sh"
```

### 6. Verify output

```bash
file output/pglite.wasi
# Should show: WebAssembly (wasm) binary module version 0x1 (MVP)
```

## Version-Dependent Components

| Component | Location | Action for New Version |
|-----------|----------|------------------------|
| PostgreSQL source | `postgresql-${PG_BRANCH}/` | Clone from postgres-pglite |
| Patches | `patches-${PG_BRANCH}/` | Copy & fix from previous version |
| Common patches | `patches/common/` | Usually no changes needed |
| pglite-wasm code | `pglite-${PG_BRANCH}/` | May need updates for API changes |

## Environment Variables

```bash
export PG_VERSION=17.6              # Semantic version
export PG_BRANCH=REL_17_6_WASM      # Git branch name
export WASI=true                     # Build for WASI (vs Emscripten)
```

## Troubleshooting

### Patch fails with "already applied"

The postgres-pglite fork already includes this change. Delete the patch:
```bash
rm patches-REL_17_X_WASM/category/patch.diff
```

### Undefined symbols at link time

Check if function was renamed/removed in new PostgreSQL. Add stub to:
- `wasm-build/sdk_port-wasi/sdk_port-wasi.c`

### Build works locally but fails in Docker

Docker clones fresh from git. Reset local to match:
```bash
cd postgresql-REL_17_X_WASM
git fetch && git reset --hard origin/REL_17_X_WASM
rm postgresql-REL_17_X_WASM.patched
```

## Available Versions

| PostgreSQL | Branch | Status |
|------------|--------|--------|
| 16.6 | `REL_16_6_WASM` | Untested |
| 17.4 | `REL_17_4_WASM` | **Working** |
| 17.5 | `REL_17_5_WASM` | Untested |
