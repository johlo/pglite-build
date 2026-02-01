# WASI Build Changes for pglite-build

This document describes the changes made to enable building PostgreSQL 17.4 to WebAssembly (WASI target) on macOS using Docker.

## Overview

The goal was to compile the `pglite-build` repository (PostgreSQL 17.4 compiled to WebAssembly) using a Docker-based build environment on macOS (ARM64/Apple Silicon). The build uses:

- **wasi-sdk 25.0** - Clang-19 based toolchain for WASI compilation
- **python-wasm-sdk** - pygame-web's SDK containing toolchains and hotfix headers
- **wasmtime** - WebAssembly runtime for running WASI binaries during build

## Build Artifacts

After successful build:

| File | Size | Description |
|------|------|-------------|
| `pglite.wasi` | 23MB | Main PostgreSQL WASI binary |
| `pg_dump.wasi` | 1.6MB | pg_dump utility |
| `pglite-wasi.tar.gz` | 5.1MB | PostgreSQL data files (share, lib, etc.) |

---

## Changes Made

### 1. Docker Build Environment

**File:** `Dockerfile.wasi-builder`

**What:** Created a new Dockerfile for ARM64-based WASI builds.

**Why:** The existing build scripts assume a Linux environment with specific toolchains. macOS cannot natively run the wasi-sdk toolchain, so Docker provides a consistent Linux build environment.

**Details:**
- Based on `debian:bookworm-slim` for ARM64
- Installs python-wasm-sdk (3.1.74.7bi) with pre-built toolchains
- Installs wasi-sdk 25.0 (both the SDK structure and ARM64 binaries)
- Installs wasmtime 33.0.0 for running WASI binaries during build (e.g., zic timezone compiler)
- Creates symlinks for clang tools (clang-19 → clang, llvm-ar → ar, etc.)
- Sets up cross-compilation config.site for autoconf

```dockerfile
# Key setup: ARM64 architecture mapping
RUN sed -i 's|/tmp/sdk/devices/x86_64|/tmp/sdk/devices/aarch64|g' /tmp/sdk/wasm32-wasi-shell.sh
```

---

### 2. Makefile.shlib Patch for WASI

**File:** `patches-REL_17_4_WASM/postgresql-emscripten/src-Makefile.shlib.diff`

**What:** Copied the Makefile.shlib patch from `patches-REL_17_5_WASM` to `patches-REL_17_4_WASM`.

**Why:** This patch is critical for WASI builds. It:
1. Adds WASI as a recognized `PORTNAME` in PostgreSQL's shared library build system
2. Makes WASI builds create static libraries (`.a`) instead of shared libraries (`.so`)
3. Defines the `wasi-shared` linker wrapper for extension builds

**Key change in patch:**
```makefile
ifdef wasi
all-shared-lib: all-static-lib
else
all-shared-lib: $(shlib)
endif
```

Without this patch, `libdict_snowball.a` and `libplpgsql.a` were not being built.

---

### 3. Patches Symlink

**File:** `patches` (symlink)

**What:** Created symlink from `patches` → `patches-REL_17_4_WASM`

**Why:** The `build-pgcore.sh` script looks for patches at `../patches/$patchdir/*.diff`. The symlink ensures patches are found regardless of the working directory structure.

```bash
ln -s patches-REL_17_4_WASM patches
```

---

### 4. Removed Redundant Patches

**Files removed:**
- `patches-REL_17_4_WASM/postgresql-emscripten/src-backend-commands-async.c.diff`
- `patches-REL_17_4_WASM/postgresql-pglite/src-port-pqsignal.c.diff`
- `patches-REL_17_4_WASM/postgresql-wasi/*.diff` (all files)

**Why:** The `postgres-pglite` fork (electric-sql/postgres-pglite) already contains these changes. Applying the patches again caused "already applied" errors that failed the build.

The patches were originally needed when building from vanilla PostgreSQL, but the fork has them pre-integrated.

---

### 5. Fixed wasi.h Header Conflicts

**File:** `postgresql-REL_17_4_WASM/src/include/port/wasi.h`

**What:** Removed function definitions that conflict with the SDK's hotfix headers.

**Why:** The python-wasm-sdk provides its own implementations of several POSIX functions in `hotfix/patch.h` and `hotfix/sdk_socket.c`. Having duplicate definitions caused redefinition errors.

**Removed functions:**

| Function | Provided by SDK |
|----------|-----------------|
| `sigsetjmp` | `hotfix/patch.h` |
| `siglongjmp` | `hotfix/patch.h` |
| `gai_strerror` | `hotfix/sdk_socket.c` |
| `getaddrinfo` | `hotfix/sdk_socket.c` |
| `freeaddrinfo` | `hotfix/sdk_socket.c` |
| `getrusage` | `hotfix/patch.h` |
| `getsockname` | `hotfix/sdk_socket.c` |

**After changes, wasi.h contains comments indicating SDK provides these:**
```c
// sigsetjmp and siglongjmp provided by SDK hotfix/patch.h
// gai_strerror provided by SDK hotfix/sdk_socket.c
// getaddrinfo and freeaddrinfo provided by SDK hotfix/sdk_socket.c
// getrusage provided by SDK hotfix/patch.h
// getsockname provided by SDK hotfix/sdk_socket.c
```

---

### 6. Added WASI Socket Stubs

**File:** `wasm-build/sdk_port-wasi/sdk_port-wasi.c`

**What:** Added stub implementations for pglite-specific symbols and socket functions.

**Why:** The PostgreSQL code (specifically `pqcomm.c`) references several symbols that are part of the pglite IPC system:
- `sockfiles` - boolean flag for socket file mode
- `cma_rsize` - shared memory size variable
- `sock_flush()` - flush socket data
- `recvfrom_bc()` - blocking receive with callback

**Changes made:**

```c
#include <stdbool.h>
#include <errno.h>

// Note: cma_rsize is defined in postgres.c
// sockfiles - weak definition that can be overridden by pglite-wasm/interactive_one.c
__attribute__((weak)) volatile bool sockfiles = false;

// Minimal socket stubs for standalone WASI builds
void sock_flush(void) {
    // No-op stub - socket flushing not supported in standalone WASI build
}

ssize_t recvfrom_bc(int socket, void *buffer, size_t length, int flags,
                    void *address, socklen_t *address_len) {
    // Stub - return error as networking not supported in standalone WASI build
    errno = ENOTSUP;
    return -1;
}
```

**Key design decisions:**

1. **`sockfiles` is weak:** The `__attribute__((weak))` allows `interactive_one.c` (in pglite-wasm) to override this definition. Without weak linkage, there would be duplicate symbol errors.

2. **`cma_rsize` not defined here:** It's already defined in `postgres.c` under `#if !defined(PGL_MAIN)` guard.

3. **Socket stubs return errors:** Networking is not supported in standalone WASI builds, so these stubs simply return error codes rather than attempting complex IPC.

---

## Build Command

```bash
# Build the Docker image
docker build -f Dockerfile.wasi-builder -t pglite-wasi-builder .

# Run the WASI build
mkdir -p output
docker run --rm \
  -v "$(pwd)":/workspace \
  -v "$(pwd)/output:/tmp/sdk/dist" \
  pglite-wasi-builder \
  bash -c ". /tmp/sdk/wasm32-wasi-shell.sh && cd /workspace && PG_BRANCH=REL_17_4_WASM WASI=true ./wasm-build.sh"
```

---

## Known Warnings

The build produces several warnings that are expected and non-fatal:

1. **"creating shared libraries, with -shared, is not yet stable"** - wasm-ld warning about experimental shared library support
2. **Macro redefinition warnings** - `chmod`, `getpid` macros defined in both wasi.h and SDK hotfix
3. **Unused variable warnings** - Minor code quality issues in PostgreSQL source
4. **tar "Cannot stat" errors** - Some optional files (llvmjit.so, locale) not present in minimal build

---

## Improved Patch System

The patch system was redesigned for better version management. See [`patches/README.md`](patches/README.md) for full documentation.

### Key Improvements

1. **Dynamic patch resolution** based on `${PG_BRANCH}` environment variable
2. **Common patches** shared across versions in `patches/common/`
3. **Auto-skip** for already-applied patches (detects via reverse-patch test)
4. **Management tool** (`patches/manage-patches.sh`) for validation and new versions

### Patch Application Flow

```
patches/common/{category}/*.diff       →  Applied first (all versions)
patches/{PG_BRANCH}/{category}/*.diff  →  Version-specific (new location)
patches-{PG_BRANCH}/{category}/*.diff  →  Version-specific (legacy location)
```

### Build Output

```
=== Applying postgresql-emscripten patches ===
  [OK]   src-Makefile.shlib.diff
=== Applying postgresql-pglite patches ===
  [SKIP] src-backend-libpq-pqcomm.c.diff (already applied)
```

### Management Commands

```bash
./patches/manage-patches.sh list                    # Show all patches
./patches/manage-patches.sh check REL_17_4_WASM    # Validate patches
./patches/manage-patches.sh new-version REL_17_6_WASM REL_17_5_WASM  # New version
```

---

## Potential Improvements

### 1. Consolidate Header Definitions

**Problem:** There's duplication between `wasi.h`, `sdk_port.h`, and SDK hotfix headers.

**Improvement:** Create a single authoritative header that:
- Clearly documents which functions come from the SDK
- Uses `#ifndef` guards to prevent redefinition
- Removes dead code from wasi.h

### 2. Fix Macro Redefinition Warnings

**Problem:** `chmod` and `getpid` are defined differently in wasi.h vs SDK hotfix.

**Improvement:**
```c
#ifndef chmod
#define chmod(...) 0
#endif
```

Or better, rely entirely on the SDK's definitions and remove from wasi.h.

### 3. Proper Socket Implementation

**Problem:** Current socket stubs just return errors, limiting functionality.

**Improvement:** Implement proper file-based IPC for WASI:
- Use the existing `PGS_IN`/`PGS_OUT` file-based protocol
- Enable the disabled code in `sdk_port-wasi.c` (currently in `#if 0` block)
- Define the required macros (`PGS_OUT`, `PGS_IN`, `PGS_ILOCK`)

### 4. Build Caching

**Problem:** Each Docker build starts fresh, recompiling everything.

**Improvement:**
- Use Docker build cache layers more effectively
- Mount a persistent ccache volume
- Pre-build static libraries into the Docker image

### 5. Multi-Architecture Support

**Problem:** Current Dockerfile only supports ARM64.

**Improvement:** Create multi-arch Dockerfile:
```dockerfile
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      ARCH=x86_64; \
    else \
      ARCH=aarch64; \
    fi && \
    # Use $ARCH for downloads
```

### 6. Extension Build Support

**Problem:** Extension builds (contrib modules) are not fully integrated.

**Improvement:**
- Complete the `extensions-emsdk` tar packing
- Test building common extensions (pg_trgm, btree_gin, etc.)
- Document extension build process

### 7. Test Suite Integration

**Problem:** The build script mentions "TODO: tests" but doesn't run any.

**Improvement:**
- Run basic sanity tests with wasmtime
- Test initdb and basic SQL operations
- Add CI integration for automated testing

### 8. Documentation

**Problem:** Build requirements and process are not well documented.

**Improvement:**
- Add README for WASI builds specifically
- Document required environment variables
- Provide troubleshooting guide for common errors

---

## File Summary

| File | Status | Description |
|------|--------|-------------|
| `Dockerfile.wasi-builder` | **New** | Docker build environment |
| `patches/` | **New** | Improved patch system directory |
| `patches/common/postgresql-emscripten/` | **New** | Common patches (all versions) |
| `patches/manage-patches.sh` | **New** | Patch management tool |
| `patches/README.md` | **New** | Patch system documentation |
| `wasm-build/build-pgcore.sh` | **Modified** | Dynamic patch resolution |
| `patches-REL_17_4_WASM/postgresql-emscripten/src-backend-commands-async.c.diff` | **Removed** | Already in fork |
| `patches-REL_17_4_WASM/postgresql-pglite/src-port-pqsignal.c.diff` | **Removed** | Already in fork |
| `patches-REL_17_4_WASM/postgresql-wasi/*.diff` | **Removed** | Already in fork |
| `postgresql-REL_17_4_WASM/src/include/port/wasi.h` | **Modified** | Removed SDK conflicts |
| `wasm-build/sdk_port-wasi/sdk_port-wasi.c` | **Modified** | Added socket stubs |

---

## References

- [pglite](https://github.com/electric-sql/pglite) - Electric SQL's PostgreSQL for the browser
- [postgres-pglite](https://github.com/electric-sql/postgres-pglite) - PostgreSQL fork with WASM patches
- [python-wasm-sdk](https://github.com/pmp-p/pglite-build) - pygame-web's WebAssembly SDK
- [wasi-sdk](https://github.com/WebAssembly/wasi-sdk) - WebAssembly System Interface SDK
- [wasmtime](https://github.com/bytecodealliance/wasmtime) - WebAssembly runtime
