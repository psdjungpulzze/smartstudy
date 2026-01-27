#!/bin/bash

# fix-submodules.sh - Repair broken submodules after copy/paste operations
#
# When a repo with submodules is copied (not cloned), submodules break because:
# - The .git file inside submodule points to non-existent .git/modules/<path>
# - The git module data doesn't exist
# - Sometimes .gitmodules itself gets corrupted
#
# This script detects and repairs broken submodules by re-initializing them.
#
# Usage:
#   ./scripts/i-i/fix-submodules.sh          # Fix all broken submodules
#   ./scripts/i-i/fix-submodules.sh --check  # Only check, don't fix

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECK_ONLY=false
if [[ "$1" == "--check" ]]; then
    CHECK_ONLY=true
fi

cd "$PROJECT_ROOT"

echo -e "${BLUE}=== Submodule Health Check ===${NC}"
echo ""

# =============================================================================
# CORRECT SUBMODULE CONFIGURATION (hardcoded fallback)
# Update this section if submodules change
# =============================================================================
read -r -d '' CORRECT_GITMODULES << 'GITMODULES_EOF' || true
[submodule "docs/i/account-server-docs"]
	path = docs/i/account-server-docs
	url = https://github.com/pulzze/account-server-docs.git
[submodule "docs/i/interactor-docs"]
	path = docs/i/interactor-docs
	url = https://github.com/pulzze/interactor-docs.git
[submodule "docs/i-i/interactor-workspace-docs"]
	path = docs/i-i/interactor-workspace-docs
	url = https://github.com/pulzze/interactor-workspace.git
GITMODULES_EOF

# Known submodules (hardcoded for reliability)
declare -a SUBMODULE_PATHS=(
    "docs/i/account-server-docs"
    "docs/i/interactor-docs"
    "docs/i-i/interactor-workspace-docs"
)

declare -A SUBMODULE_URLS=(
    ["docs/i/account-server-docs"]="https://github.com/pulzze/account-server-docs.git"
    ["docs/i/interactor-docs"]="https://github.com/pulzze/interactor-docs.git"
    ["docs/i-i/interactor-workspace-docs"]="https://github.com/pulzze/interactor-workspace.git"
)

# =============================================================================
# STEP 1: Check and fix .gitmodules
# =============================================================================
echo -e "${BLUE}[Step 1] Checking .gitmodules...${NC}"

gitmodules_ok=true
gitmodules_reason=""

if [[ ! -f ".gitmodules" ]]; then
    gitmodules_ok=false
    gitmodules_reason="File does not exist"
elif ! grep -q "docs/i/account-server-docs" .gitmodules 2>/dev/null; then
    gitmodules_ok=false
    gitmodules_reason="Missing expected submodule entries (possibly corrupted)"
elif grep -q '\[submodule "account-server"\]' .gitmodules 2>/dev/null; then
    gitmodules_ok=false
    gitmodules_reason="Contains wrong submodule names (corrupted with nested .gitmodules content)"
elif grep -q '\[submodule "interactor"\]' .gitmodules 2>/dev/null; then
    gitmodules_ok=false
    gitmodules_reason="Contains wrong submodule names (corrupted with nested .gitmodules content)"
fi

if [[ "$gitmodules_ok" == "false" ]]; then
    echo -e "  ${RED}BROKEN${NC}: $gitmodules_reason"

    if [[ "$CHECK_ONLY" == "false" ]]; then
        echo -e "  ${YELLOW}Restoring correct .gitmodules...${NC}"
        echo "$CORRECT_GITMODULES" > .gitmodules
        echo -e "  ${GREEN}FIXED${NC}"
    fi
else
    echo -e "  ${GREEN}OK${NC}"
fi
echo ""

# =============================================================================
# STEP 2: Clean up corrupted .git/modules if needed
# =============================================================================
if [[ "$CHECK_ONLY" == "false" ]]; then
    echo -e "${BLUE}[Step 2] Cleaning up stale git module data...${NC}"

    # Remove any modules that don't match our expected submodules
    if [[ -d ".git/modules" ]]; then
        # Check for wrong module paths (from corrupted .gitmodules)
        for wrong_path in "account-server" "interactor" "knowledge-base" "interactor-client-example"; do
            if [[ -d ".git/modules/$wrong_path" ]]; then
                echo -e "  ${YELLOW}Removing stale module: $wrong_path${NC}"
                rm -rf ".git/modules/$wrong_path"
            fi
        done
    fi
    echo -e "  ${GREEN}Done${NC}"
    echo ""
fi

# =============================================================================
# STEP 3: Check and fix each submodule
# =============================================================================
echo -e "${BLUE}[Step 3] Checking submodules...${NC}"
echo ""

BROKEN_COUNT=0
FIXED_COUNT=0

for submodule_path in "${SUBMODULE_PATHS[@]}"; do
    url="${SUBMODULE_URLS[$submodule_path]}"

    echo -e "${BLUE}Checking:${NC} $submodule_path"

    is_broken=false
    reason=""

    # Check 1: Directory exists
    if [[ ! -d "$submodule_path" ]]; then
        is_broken=true
        reason="Directory does not exist"
    # Check 2: Directory is not empty (has more than just .git)
    elif [[ -z "$(ls -A "$submodule_path" 2>/dev/null | grep -v '^\.git$')" ]]; then
        is_broken=true
        reason="Directory is empty (no content)"
    # Check 3: Has .git file or directory
    elif [[ ! -e "$submodule_path/.git" ]]; then
        is_broken=true
        reason="No .git file/directory in submodule"
    # Check 4: If .git is a file, check if it points to valid location
    elif [[ -f "$submodule_path/.git" ]]; then
        gitdir=$(cat "$submodule_path/.git" | sed 's/gitdir: //')
        # Resolve relative path from submodule directory
        pushd "$submodule_path" > /dev/null 2>&1
        if [[ ! -d "$gitdir" ]]; then
            is_broken=true
            reason=".git file points to non-existent path: $gitdir"
        fi
        popd > /dev/null 2>&1
    fi

    # Check 5: Can git operate in the submodule
    if [[ "$is_broken" == "false" ]]; then
        if ! git -C "$submodule_path" rev-parse --git-dir > /dev/null 2>&1; then
            is_broken=true
            reason="Git cannot operate in submodule directory"
        fi
    fi

    if [[ "$is_broken" == "true" ]]; then
        BROKEN_COUNT=$((BROKEN_COUNT + 1))
        echo -e "  ${RED}BROKEN${NC}: $reason"

        if [[ "$CHECK_ONLY" == "false" ]]; then
            echo -e "  ${YELLOW}Fixing...${NC}"

            # Remove broken submodule directory completely
            rm -rf "$submodule_path"

            # Remove from .git/modules if exists
            modules_path=".git/modules/${submodule_path}"
            if [[ -d "$modules_path" ]]; then
                rm -rf "$modules_path"
            fi

            # Remove git config entries (may fail if not present, that's ok)
            git config --remove-section "submodule.$submodule_path" 2>/dev/null || true

            # Create parent directory if needed
            mkdir -p "$(dirname "$submodule_path")"

            # Try git submodule add first
            echo -e "  ${YELLOW}Cloning from $url...${NC}"
            if git submodule add --force "$url" "$submodule_path" 2>/dev/null; then
                FIXED_COUNT=$((FIXED_COUNT + 1))
                echo -e "  ${GREEN}FIXED${NC}"
            else
                # Fallback: Try git submodule update --init
                if git submodule update --init "$submodule_path" 2>/dev/null; then
                    FIXED_COUNT=$((FIXED_COUNT + 1))
                    echo -e "  ${GREEN}FIXED${NC} (via submodule update)"
                else
                    # Last resort: direct clone
                    rm -rf "$submodule_path" 2>/dev/null || true
                    if git clone "$url" "$submodule_path" 2>/dev/null; then
                        FIXED_COUNT=$((FIXED_COUNT + 1))
                        echo -e "  ${GREEN}FIXED${NC} (via direct clone)"
                        echo -e "  ${YELLOW}Note: Run 'git submodule absorbgitdirs' to fully integrate${NC}"
                    else
                        echo -e "  ${RED}FAILED TO FIX${NC} - Could not clone from $url"
                    fi
                fi
            fi
        fi
    else
        echo -e "  ${GREEN}OK${NC}"
    fi
    echo ""
done

# =============================================================================
# STEP 4: Final initialization
# =============================================================================
if [[ "$CHECK_ONLY" == "false" ]]; then
    echo -e "${BLUE}[Step 4] Final submodule initialization...${NC}"
    git submodule init 2>/dev/null || true
    git submodule update 2>/dev/null || true
    echo -e "  ${GREEN}Done${NC}"
    echo ""
fi

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}=== Summary ===${NC}"
echo "Total submodules: ${#SUBMODULE_PATHS[@]}"
echo "Broken: $BROKEN_COUNT"

if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ $BROKEN_COUNT -gt 0 ]] || [[ "$gitmodules_ok" == "false" ]]; then
        echo ""
        echo -e "${YELLOW}Run without --check to fix issues${NC}"
        exit 1
    fi
else
    echo "Fixed: $FIXED_COUNT"
fi

if [[ $BROKEN_COUNT -eq 0 ]] && [[ "$gitmodules_ok" == "true" ]]; then
    echo ""
    echo -e "${GREEN}All submodules are healthy!${NC}"
fi
