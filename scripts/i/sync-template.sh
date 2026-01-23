#!/bin/bash
#
# Sync updates from the product-dev-template to your project
#
# Usage: ./sync-template.sh [component]
#
# Components:
#   all       - Sync everything (use with caution)
#   agents    - Sync .claude/agents/i/
#   assets    - Sync .claude/assets/i/ (brand assets + icons)
#   commands  - Sync .claude/commands/i/
#   rules     - Sync .claude/rules/i/
#   skills    - Sync .claude/skills/i/
#   scripts   - Sync scripts/i/ (template scripts)
#   docs      - Sync docs/i/ (phases, checklists, templates)
#   validator - Sync validator skill and validation checklist
#
# IMPORTANT: The "/i/" folder convention
# ======================================
# Files inside "/i/" directories are template-owned and safe to sync.
# Files OUTSIDE "/i/" directories are user-owned and will NOT be synced.
#
# Protected by design (not in /i/ paths):
#   - docs/project-idea-intake.md  (your project idea - never overwritten)
#   - CLAUDE.md                    (your project config - never overwritten)
#   - docs/setup/                  (proprietary setup methodology - never synced)
#   - .claude/commands/setup/      (proprietary setup commands - never synced)
#   - .claude/skills/setup/        (proprietary setup skills - never synced)
#   - .claude/agents/setup/        (proprietary setup agents - never synced)
#   - scripts/setup/               (proprietary setup scripts - never synced)
#   - Any files you create outside /i/ directories
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Header
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Product Dev Template - Sync Updates               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Template repository URL
TEMPLATE_REPO_URL="https://github.com/pulzze/product-dev-template.git"

# Protected files - these should NEVER be overwritten by sync
# These are user-specific files that live outside /i/ directories
PROTECTED_FILES=(
    "docs/project-idea-intake.md"
    "CLAUDE.md"
    "docs/setup/"
    ".claude/commands/setup/"
    ".claude/skills/setup/"
    ".claude/agents/setup/"
    "scripts/setup/"
)

# Check if a file is protected
is_protected() {
    local file=$1
    for protected in "${PROTECTED_FILES[@]}"; do
        if [[ "$file" == "$protected" ]]; then
            return 0
        fi
    done
    return 1
}

# Warn if any protected files would be affected
check_protected_files() {
    local path=$1
    local has_protected=false

    for protected in "${PROTECTED_FILES[@]}"; do
        if [[ "$protected" == "$path"* ]] || git diff --name-only HEAD template/main -- "$path" 2>/dev/null | grep -q "^$protected$"; then
            print_warning "Protected file would be affected: $protected"
            has_protected=true
        fi
    done

    if $has_protected; then
        print_warning "Protected files are user-specific and should not be synced."
        return 1
    fi
    return 0
}

# Check if template remote exists, add if missing
if ! git remote | grep -q "template"; then
    print_info "Adding template remote..."
    git remote add template "$TEMPLATE_REPO_URL"
    print_success "Added template remote: $TEMPLATE_REPO_URL"
    echo ""
fi

COMPONENT=${1:-"interactive"}

# Fetch latest from template
print_info "Fetching latest template updates..."
# Prevent hanging on credential prompts; fail fast with timeout
if ! GIT_TERMINAL_PROMPT=0 timeout 30 git fetch template 2>&1; then
    print_error "Failed to fetch from template remote."
    print_info "This may be due to network issues or missing credentials."
    print_info "Try: git fetch template --verbose"
    exit 1
fi
print_success "Fetched template updates"
echo ""

# Show what's changed
print_info "Changes available from template:"
echo ""
git log --oneline HEAD..template/main -- .claude/ docs/ 2>/dev/null | head -20 || echo "  (no new commits)"
echo ""

sync_component() {
    local component=$1
    local path=$2

    print_info "Syncing $component..."

    # Get list of files in template (source of truth)
    local template_files
    template_files=$(git ls-tree -r --name-only template/main -- "$path" 2>/dev/null | sort)

    # Get list of local files
    local local_files=""
    if [[ -d "$path" ]]; then
        local_files=$(find "$path" -type f 2>/dev/null | sort)
    fi

    # Determine files to add/update (files in template)
    echo ""
    echo "Files to add/update from template:"
    if [[ -n "$template_files" ]]; then
        echo "$template_files" | head -20 | sed 's/^/  /'
        local template_count
        template_count=$(echo "$template_files" | wc -l)
        if [[ $template_count -gt 20 ]]; then
            echo "  ... and $((template_count - 20)) more files"
        fi
    else
        echo "  (none)"
    fi

    # Determine files to delete (local files not in template)
    # Use comm for efficient set difference (O(n) instead of O(n²))
    echo ""
    echo "Files to delete (not in template):"
    local deleted=""
    if [[ -n "$local_files" && -n "$template_files" ]]; then
        # comm -23: lines only in file1 (local) not in file2 (template)
        deleted=$(comm -23 <(echo "$local_files") <(echo "$template_files"))
    elif [[ -n "$local_files" ]]; then
        # No template files, all local files would be deleted
        deleted="$local_files"
    fi

    if [[ -n "$deleted" ]]; then
        echo "$deleted" | head -20 | sed 's/^/  /'
    else
        echo "  (none)"
    fi
    echo ""

    # Check if there are any changes
    if [[ -z "$template_files" && -z "$deleted" ]]; then
        print_info "No changes to sync for $component"
        return 0
    fi

    read -p "Proceed with sync? (y/n) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove files not in template first
        if [[ -n "$deleted" ]]; then
            echo "$deleted" | while IFS= read -r file; do
                if [[ -n "$file" && -f "$file" ]]; then
                    rm -f "$file"
                    print_info "Deleted: $file"
                fi
            done
        fi

        # Checkout all files from template (creates dirs as needed)
        if [[ -n "$template_files" ]]; then
            git checkout template/main -- "$path"
        fi

        # Clean up empty directories
        if [[ -d "$path" ]]; then
            find "$path" -type d -empty -delete 2>/dev/null || true
        fi

        print_success "Synced $component"
    else
        print_warning "Skipped $component"
    fi
}

sync_all_paths() {
    local paths=(
        ".claude/agents/i/"
        ".claude/assets/i/"
        ".claude/commands/i/"
        ".claude/rules/i/"
        ".claude/skills/i/"
        ".claude/templates/i/"
        "scripts/i/"
        "docs/i/"
    )

    # For each path, remove files not in template, then checkout from template
    for path in "${paths[@]}"; do
        # Get template files for this path
        local template_files
        template_files=$(git ls-tree -r --name-only template/main -- "$path" 2>/dev/null | sort)

        # Get local files
        if [[ -d "$path" ]]; then
            local local_files
            local_files=$(find "$path" -type f 2>/dev/null | sort)

            # Delete files not in template (use comm for efficiency)
            if [[ -n "$local_files" && -n "$template_files" ]]; then
                local to_delete
                to_delete=$(comm -23 <(echo "$local_files") <(echo "$template_files"))
                if [[ -n "$to_delete" ]]; then
                    while IFS= read -r local_file; do
                        if [[ -n "$local_file" && -f "$local_file" ]]; then
                            rm -f "$local_file"
                            print_info "Deleted: $local_file"
                        fi
                    done <<< "$to_delete"
                fi
            elif [[ -n "$local_files" && -z "$template_files" ]]; then
                # No template files for this path, delete all local
                while IFS= read -r local_file; do
                    if [[ -n "$local_file" && -f "$local_file" ]]; then
                        rm -f "$local_file"
                        print_info "Deleted: $local_file"
                    fi
                done <<< "$local_files"
            fi
        fi

        # Checkout from template
        if [[ -n "$template_files" ]]; then
            git checkout template/main -- "$path" 2>/dev/null || true
        fi

        # Clean up empty directories
        if [[ -d "$path" ]]; then
            find "$path" -type d -empty -delete 2>/dev/null || true
        fi
    done
}

case $COMPONENT in
    all)
        print_warning "Syncing ALL template files. This may overwrite your customizations."
        echo ""
        echo "Files to delete (local files not in template):"
        all_deleted=""
        for sync_path in .claude/agents/i/ .claude/assets/i/ .claude/commands/i/ .claude/rules/i/ .claude/skills/i/ .claude/templates/i/ scripts/i/ docs/i/; do
            if [[ -d "$sync_path" ]]; then
                template_files=$(git ls-tree -r --name-only template/main -- "$sync_path" 2>/dev/null | sort)
                local_files=$(find "$sync_path" -type f 2>/dev/null | sort)
                if [[ -n "$local_files" && -n "$template_files" ]]; then
                    # Use comm for efficient set difference
                    path_deleted=$(comm -23 <(echo "$local_files") <(echo "$template_files"))
                    if [[ -n "$path_deleted" ]]; then
                        all_deleted="${all_deleted}${path_deleted}"$'\n'
                    fi
                elif [[ -n "$local_files" ]]; then
                    all_deleted="${all_deleted}${local_files}"$'\n'
                fi
            fi
        done
        if [[ -n "$all_deleted" ]]; then
            echo "$all_deleted" | head -30 | sed 's/^/  /'
        else
            echo "  (none)"
        fi
        echo ""
        read -p "Are you sure? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sync_all_paths
            print_success "Synced all template files"
        fi
        ;;
    agents)
        sync_component "agents" ".claude/agents/i/"
        ;;
    assets)
        sync_component "assets (brand + icons)" ".claude/assets/i/"
        ;;
    commands)
        sync_component "commands" ".claude/commands/i/"
        ;;
    rules)
        sync_component "rules" ".claude/rules/i/"
        ;;
    skills)
        sync_component "skills" ".claude/skills/i/"
        ;;
    scripts)
        sync_component "scripts" "scripts/i/"
        ;;
    docs)
        sync_component "phase documentation" "docs/i/phases/"
        sync_component "checklists" "docs/i/checklists/"
        sync_component "templates" "docs/i/templates/"
        ;;
    validator)
        sync_component "validator skill" ".claude/skills/i/validator/"
        sync_component "validation checklist" "docs/i/checklists/validation-checklist.md"
        ;;
    interactive)
        echo "What would you like to sync?"
        echo ""
        echo "  1) Agents (.claude/agents/i/)"
        echo "  2) Assets (.claude/assets/i/) - brand assets + icons"
        echo "  3) Commands (.claude/commands/i/)"
        echo "  4) Rules (.claude/rules/i/)"
        echo "  5) Skills (.claude/skills/i/)"
        echo "  6) Scripts (scripts/i/)"
        echo "  7) Documentation (docs/i/) - phases, checklists, templates"
        echo "  8) Validator only"
        echo "  9) All (use with caution)"
        echo "  0) Cancel"
        echo ""
        read -p "Select option (0-9): " -n 1 -r
        echo ""
        echo ""

        case $REPLY in
            1) sync_component "agents" ".claude/agents/i/" ;;
            2) sync_component "assets (brand + icons)" ".claude/assets/i/" ;;
            3) sync_component "commands" ".claude/commands/i/" ;;
            4) sync_component "rules" ".claude/rules/i/" ;;
            5) sync_component "skills" ".claude/skills/i/" ;;
            6) sync_component "scripts" "scripts/i/" ;;
            7)
                sync_component "phase documentation" "docs/i/phases/"
                sync_component "checklists" "docs/i/checklists/"
                sync_component "templates" "docs/i/templates/"
                ;;
            8)
                sync_component "validator skill" ".claude/skills/i/validator/"
                sync_component "validation checklist" "docs/i/checklists/validation-checklist.md"
                ;;
            9)
                print_warning "Syncing ALL template files. This may overwrite your customizations."
                echo ""
                echo "Files to delete (local files not in template):"
                all_deleted=""
                for sync_path in .claude/agents/i/ .claude/assets/i/ .claude/commands/i/ .claude/rules/i/ .claude/skills/i/ .claude/templates/i/ scripts/i/ docs/i/; do
                    if [[ -d "$sync_path" ]]; then
                        template_files=$(git ls-tree -r --name-only template/main -- "$sync_path" 2>/dev/null | sort)
                        local_files=$(find "$sync_path" -type f 2>/dev/null | sort)
                        if [[ -n "$local_files" && -n "$template_files" ]]; then
                            # Use comm for efficient set difference
                            path_deleted=$(comm -23 <(echo "$local_files") <(echo "$template_files"))
                            if [[ -n "$path_deleted" ]]; then
                                all_deleted="${all_deleted}${path_deleted}"$'\n'
                            fi
                        elif [[ -n "$local_files" ]]; then
                            all_deleted="${all_deleted}${local_files}"$'\n'
                        fi
                    fi
                done
                if [[ -n "$all_deleted" ]]; then
                    echo "$all_deleted" | head -30 | sed 's/^/  /'
                else
                    echo "  (none)"
                fi
                echo ""
                read -p "Are you sure? (y/n) " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    sync_all_paths
                    print_success "Synced all template files"
                fi
                ;;
            0)
                print_info "Cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
        ;;
    *)
        print_error "Unknown component: $COMPONENT"
        echo ""
        echo "Valid components: all, agents, assets, commands, rules, skills, scripts, docs, validator"
        exit 1
        ;;
esac

echo ""
print_info "Don't forget to review changes and commit:"
echo ""
echo "  git status"
echo "  git diff --cached"
echo "  git commit -m 'Sync template updates'"
echo ""
