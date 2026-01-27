#!/bin/bash

# fix-submodules.sh - Repair broken submodules after copy/paste operations
#
# When a repo with submodules is copied (not cloned), submodules break because:
# - The .git file inside submodule points to non-existent .git/modules/<path>
# - The git module data doesn't exist
#
# This script detects and repairs broken submodules by re-initializing them.
#
# Usage:
#   ./scripts/setup/fix-submodules.sh          # Fix all broken submodules
#   ./scripts/setup/fix-submodules.sh --check  # Only check, don't fix

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

# Check if .gitmodules exists
if [[ ! -f ".gitmodules" ]]; then
    echo -e "${YELLOW}No .gitmodules file found. No submodules configured.${NC}"
    exit 0
fi

# Parse .gitmodules to get submodule info
declare -A SUBMODULES
current_name=""
while IFS= read -r line; do
    if [[ $line =~ ^\[submodule\ \"(.+)\"\]$ ]]; then
        current_name="${BASH_REMATCH[1]}"
    elif [[ $line =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        path="${BASH_REMATCH[1]}"
        SUBMODULES["$path,path"]="$path"
        SUBMODULES["$path,name"]="$current_name"
    elif [[ $line =~ ^[[:space:]]*url[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        url="${BASH_REMATCH[1]}"
        if [[ -n "$current_name" ]]; then
            # Find the path for this name
            for key in "${!SUBMODULES[@]}"; do
                if [[ "${SUBMODULES[$key]}" == "$current_name" && $key == *",name" ]]; then
                    p="${key%,name}"
                    SUBMODULES["$p,url"]="$url"
                fi
            done
        fi
    fi
done < .gitmodules

# Get unique paths
PATHS=()
for key in "${!SUBMODULES[@]}"; do
    if [[ $key == *",path" ]]; then
        PATHS+=("${SUBMODULES[$key]}")
    fi
done

BROKEN_COUNT=0
FIXED_COUNT=0

for submodule_path in "${PATHS[@]}"; do
    name="${SUBMODULES["$submodule_path,name"]}"
    url="${SUBMODULES["$submodule_path,url"]}"

    echo -e "${BLUE}Checking:${NC} $submodule_path"

    is_broken=false
    reason=""

    # Check 1: Directory exists
    if [[ ! -d "$submodule_path" ]]; then
        is_broken=true
        reason="Directory does not exist"
    # Check 2: Has .git file or directory
    elif [[ ! -e "$submodule_path/.git" ]]; then
        is_broken=true
        reason="No .git file/directory in submodule"
    # Check 3: If .git is a file, check if it points to valid location
    elif [[ -f "$submodule_path/.git" ]]; then
        gitdir=$(cat "$submodule_path/.git" | sed 's/gitdir: //')
        # Resolve relative path
        abs_gitdir="$submodule_path/$gitdir"
        if [[ ! -d "$abs_gitdir" ]]; then
            is_broken=true
            reason=".git file points to non-existent path: $gitdir"
        fi
    fi

    # Check 4: Can git operate in the submodule
    if [[ "$is_broken" == "false" ]]; then
        if ! git -C "$submodule_path" rev-parse --git-dir > /dev/null 2>&1; then
            is_broken=true
            reason="Git cannot operate in submodule directory"
        fi
    fi

    if [[ "$is_broken" == "true" ]]; then
        ((BROKEN_COUNT++))
        echo -e "  ${RED}BROKEN${NC}: $reason"

        if [[ "$CHECK_ONLY" == "false" ]]; then
            echo -e "  ${YELLOW}Fixing...${NC}"

            # Remove broken submodule directory
            rm -rf "$submodule_path"

            # Remove from .git/modules if exists
            modules_path=".git/modules/$submodule_path"
            if [[ -d "$modules_path" ]]; then
                rm -rf "$modules_path"
            fi

            # Remove git config entries
            git config --remove-section "submodule.$name" 2>/dev/null || true

            # Re-initialize and update the submodule
            git submodule update --init "$submodule_path"

            if [[ $? -eq 0 ]]; then
                ((FIXED_COUNT++))
                echo -e "  ${GREEN}FIXED${NC}"
            else
                echo -e "  ${RED}FAILED TO FIX${NC}"
            fi
        fi
    else
        echo -e "  ${GREEN}OK${NC}"
    fi
    echo ""
done

echo -e "${BLUE}=== Summary ===${NC}"
echo "Total submodules: ${#PATHS[@]}"
echo "Broken: $BROKEN_COUNT"

if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ $BROKEN_COUNT -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Run without --check to fix broken submodules${NC}"
        exit 1
    fi
else
    echo "Fixed: $FIXED_COUNT"
fi

if [[ $BROKEN_COUNT -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}All submodules are healthy!${NC}"
fi
