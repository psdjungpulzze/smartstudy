#!/bin/bash
#
# Sync Interactor documentation submodules
#
# Usage: ./sync-interactor-docs.sh [submodule]
#
# Submodules:
#   all          - Sync all Interactor doc submodules (default)
#   account      - Sync account-server-docs only
#   interactor   - Sync interactor-docs only
#
# Options:
#   --init       - Initialize submodules if not already done
#   --status     - Show submodule status without syncing
#   --help       - Show this help message
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Interactor Documentation - Submodule Sync           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help() {
    echo "Usage: $0 [submodule] [options]"
    echo ""
    echo "Submodules:"
    echo "  all          Sync all Interactor doc submodules (default)"
    echo "  account      Sync account-server-docs only"
    echo "  interactor   Sync interactor-docs only"
    echo ""
    echo "Options:"
    echo "  --init       Initialize submodules if not already done"
    echo "  --status     Show submodule status without syncing"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Sync all submodules"
    echo "  $0 account            # Sync only account-server-docs"
    echo "  $0 --init             # Initialize and sync all"
    echo "  $0 --status           # Show current status"
}

# Find project root (directory containing .git)
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.git" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Submodule paths
ACCOUNT_DOCS="docs/i/account-server-docs"
INTERACTOR_DOCS="docs/i/interactor-docs"

# Parse arguments
SUBMODULE="all"
INIT_MODE=false
STATUS_MODE=false

for arg in "$@"; do
    case $arg in
        --init)
            INIT_MODE=true
            ;;
        --status)
            STATUS_MODE=true
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        all|account|interactor)
            SUBMODULE="$arg"
            ;;
        *)
            print_error "Unknown argument: $arg"
            show_help
            exit 1
            ;;
    esac
done

# Find and change to project root
PROJECT_ROOT=$(find_project_root) || {
    print_error "Could not find project root (no .git directory found)"
    exit 1
}
cd "$PROJECT_ROOT"

print_header

# Check if submodules exist in .gitmodules
if [[ ! -f ".gitmodules" ]]; then
    print_error "No .gitmodules file found. Submodules may not be configured."
    print_info "Run this from a project that has Interactor doc submodules set up."
    exit 1
fi

# Status mode - just show status and exit
if [[ "$STATUS_MODE" == true ]]; then
    print_info "Submodule status:"
    echo ""
    git submodule status
    echo ""

    print_info "Submodule details:"
    echo ""
    if [[ -d "$ACCOUNT_DOCS" ]]; then
        echo -e "  ${GREEN}●${NC} account-server-docs"
        echo "    Path: $ACCOUNT_DOCS"
        if [[ -d "$ACCOUNT_DOCS/.git" ]] || [[ -f "$ACCOUNT_DOCS/.git" ]]; then
            COMMIT=$(cd "$ACCOUNT_DOCS" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            BRANCH=$(cd "$ACCOUNT_DOCS" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            echo "    Commit: $COMMIT ($BRANCH)"
        fi
    else
        echo -e "  ${RED}○${NC} account-server-docs (not initialized)"
    fi
    echo ""
    if [[ -d "$INTERACTOR_DOCS" ]]; then
        echo -e "  ${GREEN}●${NC} interactor-docs"
        echo "    Path: $INTERACTOR_DOCS"
        if [[ -d "$INTERACTOR_DOCS/.git" ]] || [[ -f "$INTERACTOR_DOCS/.git" ]]; then
            COMMIT=$(cd "$INTERACTOR_DOCS" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            BRANCH=$(cd "$INTERACTOR_DOCS" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            echo "    Commit: $COMMIT ($BRANCH)"
        fi
    else
        echo -e "  ${RED}○${NC} interactor-docs (not initialized)"
    fi
    echo ""
    exit 0
fi

# Initialize submodules if requested or if they don't exist
init_submodules() {
    print_info "Initializing submodules..."
    git submodule init
    git submodule update
    print_success "Submodules initialized"
}

if [[ "$INIT_MODE" == true ]]; then
    init_submodules
fi

# Check if submodules are initialized
check_submodule() {
    local path="$1"
    local name="$2"

    if [[ ! -d "$path" ]] || [[ ! -f "$path/.git" && ! -d "$path/.git" ]]; then
        print_warning "$name is not initialized"
        print_info "Run with --init to initialize submodules"
        return 1
    fi
    return 0
}

# Sync a single submodule
sync_submodule() {
    local path="$1"
    local name="$2"

    print_info "Syncing $name..."

    # Get current commit before update
    OLD_COMMIT=$(cd "$path" && git rev-parse --short HEAD 2>/dev/null || echo "none")

    # Fetch and update
    git submodule update --remote --merge "$path"

    # Get new commit after update
    NEW_COMMIT=$(cd "$path" && git rev-parse --short HEAD 2>/dev/null || echo "none")

    if [[ "$OLD_COMMIT" == "$NEW_COMMIT" ]]; then
        print_success "$name is up to date ($NEW_COMMIT)"
    else
        print_success "$name updated: $OLD_COMMIT → $NEW_COMMIT"

        # Show what changed
        echo ""
        print_info "Changes in $name:"
        (cd "$path" && git log --oneline "$OLD_COMMIT..$NEW_COMMIT" 2>/dev/null | head -10) || true
        echo ""
    fi
}

# Sync based on selection
echo ""
case $SUBMODULE in
    all)
        print_info "Syncing all Interactor documentation submodules..."
        echo ""

        if check_submodule "$ACCOUNT_DOCS" "account-server-docs"; then
            sync_submodule "$ACCOUNT_DOCS" "account-server-docs"
        fi

        echo ""

        if check_submodule "$INTERACTOR_DOCS" "interactor-docs"; then
            sync_submodule "$INTERACTOR_DOCS" "interactor-docs"
        fi
        ;;

    account)
        if check_submodule "$ACCOUNT_DOCS" "account-server-docs"; then
            sync_submodule "$ACCOUNT_DOCS" "account-server-docs"
        fi
        ;;

    interactor)
        if check_submodule "$INTERACTOR_DOCS" "interactor-docs"; then
            sync_submodule "$INTERACTOR_DOCS" "interactor-docs"
        fi
        ;;
esac

echo ""
print_info "Sync complete!"
echo ""

# Check if there are changes to commit
if git diff --quiet && git diff --staged --quiet; then
    print_info "No changes to commit"
else
    print_warning "Submodule references have changed"
    print_info "Review changes with: git status"
    print_info "Commit with: git add -A && git commit -m 'Update Interactor docs submodules'"
fi

echo ""
