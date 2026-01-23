#!/bin/bash
#
# Patch management tool for pglite-build
#
# Usage:
#   ./manage-patches.sh check <PG_BRANCH>      - Check if patches apply cleanly
#   ./manage-patches.sh apply <PG_BRANCH>      - Apply patches to source tree
#   ./manage-patches.sh new-version <PG_BRANCH> - Create patch dir for new version
#   ./manage-patches.sh generate <file>        - Generate patch from modified file
#   ./manage-patches.sh list [PG_BRANCH]       - List patches for version
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get patches for a given version
# Returns: common patches first, then version-specific
get_patches_for_version() {
    local pg_branch="$1"
    local category="$2"

    # Common patches (if they exist)
    if [ -d "$PATCHES_DIR/common/$category" ]; then
        find "$PATCHES_DIR/common/$category" -name "*.diff" 2>/dev/null | sort
    fi

    # Version-specific patches
    if [ -d "$PATCHES_DIR/$pg_branch/$category" ]; then
        find "$PATCHES_DIR/$pg_branch/$category" -name "*.diff" 2>/dev/null | sort
    fi

    # Legacy location (patches-REL_XX_X_WASM)
    local legacy_dir="$WORKSPACE/patches-$pg_branch/$category"
    if [ -d "$legacy_dir" ]; then
        find "$legacy_dir" -name "*.diff" 2>/dev/null | sort
    fi
}

# Check if patches apply cleanly
cmd_check() {
    local pg_branch="${1:-$PG_BRANCH}"

    if [ -z "$pg_branch" ]; then
        log_error "Usage: $0 check <PG_BRANCH>"
        log_error "Example: $0 check REL_17_4_WASM"
        exit 1
    fi

    local source_dir="$WORKSPACE/postgresql-$pg_branch"

    if [ ! -d "$source_dir" ]; then
        log_error "Source directory not found: $source_dir"
        log_info "Clone it first: git clone --branch $pg_branch https://github.com/electric-sql/postgres-pglite postgresql-$pg_branch"
        exit 1
    fi

    log_info "Checking patches for $pg_branch"
    log_info "Source: $source_dir"
    echo ""

    local total=0
    local passed=0
    local failed=0
    local skipped=0

    for category in postgresql-debug postgresql-emscripten postgresql-wasi postgresql-pglite; do
        local patches=$(get_patches_for_version "$pg_branch" "$category")

        if [ -z "$patches" ]; then
            continue
        fi

        echo "=== $category ==="

        for patch in $patches; do
            ((total++))
            local patch_name=$(basename "$patch")

            # Check if patch applies (dry-run)
            if (cd "$source_dir" && patch -p1 --dry-run < "$patch") &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $patch_name"
                ((passed++))
            else
                # Check if already applied (reverse dry-run)
                if (cd "$source_dir" && patch -R -p1 --dry-run < "$patch") &>/dev/null; then
                    echo -e "  ${YELLOW}○${NC} $patch_name (already applied)"
                    ((skipped++))
                else
                    echo -e "  ${RED}✗${NC} $patch_name (FAILED)"
                    ((failed++))
                fi
            fi
        done
        echo ""
    done

    echo "========================================"
    echo "Total: $total | Passed: $passed | Already applied: $skipped | Failed: $failed"

    if [ $failed -gt 0 ]; then
        exit 1
    fi
}

# Apply patches to source tree
cmd_apply() {
    local pg_branch="${1:-$PG_BRANCH}"
    local force="${2:-false}"

    if [ -z "$pg_branch" ]; then
        log_error "Usage: $0 apply <PG_BRANCH> [--force]"
        exit 1
    fi

    local source_dir="$WORKSPACE/postgresql-$pg_branch"

    if [ ! -d "$source_dir" ]; then
        log_error "Source directory not found: $source_dir"
        exit 1
    fi

    # Check if already patched
    if [ -f "$source_dir/postgresql-$pg_branch.patched" ] && [ "$force" != "--force" ]; then
        log_warn "Already patched. Use --force to re-apply."
        exit 0
    fi

    log_info "Applying patches for $pg_branch"

    for category in postgresql-debug postgresql-emscripten postgresql-wasi postgresql-pglite; do
        local patches=$(get_patches_for_version "$pg_branch" "$category")

        if [ -z "$patches" ]; then
            continue
        fi

        log_info "Applying $category patches..."

        for patch in $patches; do
            local patch_name=$(basename "$patch")

            # Check if already applied
            if (cd "$source_dir" && patch -R -p1 --dry-run < "$patch") &>/dev/null; then
                log_warn "Skipping $patch_name (already applied)"
                continue
            fi

            # Apply patch
            if (cd "$source_dir" && patch -p1 < "$patch"); then
                log_info "Applied: $patch_name"
            else
                log_error "Failed to apply: $patch_name"
                exit 1
            fi
        done
    done

    touch "$source_dir/postgresql-$pg_branch.patched"
    log_info "Patches applied successfully"
}

# Create patch directory for new version
cmd_new_version() {
    local new_branch="$1"
    local base_branch="${2:-REL_17_4_WASM}"

    if [ -z "$new_branch" ]; then
        log_error "Usage: $0 new-version <NEW_PG_BRANCH> [BASE_PG_BRANCH]"
        log_error "Example: $0 new-version REL_17_5_WASM REL_17_4_WASM"
        exit 1
    fi

    local new_dir="$PATCHES_DIR/$new_branch"
    local base_dir="$PATCHES_DIR/$base_branch"

    # Check for legacy base dir
    if [ ! -d "$base_dir" ]; then
        base_dir="$WORKSPACE/patches-$base_branch"
    fi

    if [ -d "$new_dir" ]; then
        log_error "Directory already exists: $new_dir"
        exit 1
    fi

    log_info "Creating patch directory for $new_branch (based on $base_branch)"

    mkdir -p "$new_dir"

    # Copy structure from base version
    for category in postgresql-debug postgresql-emscripten postgresql-wasi postgresql-pglite; do
        if [ -d "$base_dir/$category" ]; then
            mkdir -p "$new_dir/$category"

            # Copy patches
            for patch in "$base_dir/$category"/*.diff; do
                if [ -f "$patch" ]; then
                    cp "$patch" "$new_dir/$category/"
                    log_info "Copied: $(basename "$patch")"
                fi
            done
        fi
    done

    log_info "Created $new_dir"
    log_info ""
    log_info "Next steps:"
    log_info "1. Clone new PostgreSQL version:"
    log_info "   git clone --branch $new_branch https://github.com/electric-sql/postgres-pglite postgresql-$new_branch"
    log_info ""
    log_info "2. Check if patches apply:"
    log_info "   $0 check $new_branch"
    log_info ""
    log_info "3. Fix any failed patches manually"
}

# Generate a patch from a modified file
cmd_generate() {
    local modified_file="$1"
    local pg_branch="${2:-$PG_BRANCH}"

    if [ -z "$modified_file" ] || [ -z "$pg_branch" ]; then
        log_error "Usage: $0 generate <modified_file> [PG_BRANCH]"
        log_error "Example: $0 generate src/backend/libpq/pqcomm.c REL_17_4_WASM"
        exit 1
    fi

    local source_dir="$WORKSPACE/postgresql-$pg_branch"
    local full_path="$source_dir/$modified_file"

    if [ ! -f "$full_path" ]; then
        log_error "File not found: $full_path"
        exit 1
    fi

    # Generate patch name from path
    local patch_name=$(echo "$modified_file" | tr '/' '-').diff

    log_info "Generating patch for: $modified_file"

    # Use git diff if in a git repo, otherwise show instructions
    if (cd "$source_dir" && git rev-parse --git-dir) &>/dev/null; then
        (cd "$source_dir" && git diff -- "$modified_file")
        log_info ""
        log_info "Save with: cd $source_dir && git diff -- $modified_file > $patch_name"
    else
        log_warn "Not a git repository. Use diff manually:"
        log_info "diff -u original_file $full_path > $patch_name"
    fi
}

# List patches for a version
cmd_list() {
    local pg_branch="${1:-$PG_BRANCH}"

    echo "Patches for ${pg_branch:-all versions}:"
    echo ""

    if [ -n "$pg_branch" ]; then
        for category in postgresql-debug postgresql-emscripten postgresql-wasi postgresql-pglite; do
            local patches=$(get_patches_for_version "$pg_branch" "$category")
            if [ -n "$patches" ]; then
                echo "=== $category ==="
                echo "$patches" | while read -r p; do
                    if [ -n "$p" ]; then
                        echo "  $(basename "$p")"
                    fi
                done
                echo ""
            fi
        done
    else
        # List all versions
        echo "Available versions:"
        ls -d "$PATCHES_DIR"/REL_* "$WORKSPACE"/patches-REL_* 2>/dev/null | while read -r d; do
            echo "  $(basename "$d")"
        done
    fi
}

# Show help
cmd_help() {
    echo "Patch management tool for pglite-build"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  check <PG_BRANCH>              Check if patches apply cleanly"
    echo "  apply <PG_BRANCH> [--force]    Apply patches to source tree"
    echo "  new-version <NEW> [BASE]       Create patch dir for new version"
    echo "  generate <file> [PG_BRANCH]    Generate patch from modified file"
    echo "  list [PG_BRANCH]               List patches for version"
    echo "  help                           Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 check REL_17_4_WASM"
    echo "  $0 apply REL_17_5_WASM"
    echo "  $0 new-version REL_17_6_WASM REL_17_5_WASM"
    echo "  $0 generate src/backend/libpq/pqcomm.c REL_17_4_WASM"
}

# Main
case "${1:-help}" in
    check)      cmd_check "$2" ;;
    apply)      cmd_apply "$2" "$3" ;;
    new-version) cmd_new_version "$2" "$3" ;;
    generate)   cmd_generate "$2" "$3" ;;
    list)       cmd_list "$2" ;;
    help|--help|-h) cmd_help ;;
    *)
        log_error "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
