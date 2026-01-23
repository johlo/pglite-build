# PostgreSQL WASM Patches

This directory contains patches organized by category and version.

## Structure

```
patches/
├── common/                    # Patches that work across versions
│   ├── postgresql-emscripten/ # Build system patches
│   └── postgresql-wasi/       # WASI-specific patches
├── REL_17_4_WASM/            # Version-specific patches
│   ├── postgresql-pglite/
│   └── postgresql-wasi/
├── REL_17_5_WASM/
│   └── ...
└── manage-patches.sh          # Patch management tool
```

## Patch Categories

| Category | Purpose |
|----------|---------|
| `postgresql-debug` | Debug helpers (optional) |
| `postgresql-emscripten` | Build system for WASM (Makefile.shlib, etc.) |
| `postgresql-wasi` | WASI-specific compatibility |
| `postgresql-pglite` | pglite functionality (IPC, query handling) |

## Usage

Patches are applied automatically by `build-pgcore.sh`. The script:
1. First applies common patches (work across versions)
2. Then applies version-specific patches

## Adding a New Version

```bash
./patches/manage-patches.sh new-version REL_17_6_WASM
```

## Checking Patch Status

```bash
./patches/manage-patches.sh check REL_17_5_WASM
```

## Notes

- Some patches may already be in the `postgres-pglite` fork
- Use `--dry-run` with patch to test before applying
- Patches use unified diff format (`diff -u`)
