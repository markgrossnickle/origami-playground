#!/bin/bash
# template-sync.sh — Syncs updates from roblox-template into a game repo
# Usage: template-sync.sh [template-path] [target-game-path]
# If no args, assumes template is at ../roblox-template and target is current dir

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${1:-$(dirname "$SCRIPT_DIR")}"
TARGET_PATH="${2:-.}"

# Resolve to absolute paths
TEMPLATE_PATH="$(cd "$TEMPLATE_PATH" && pwd)"
TARGET_PATH="$(cd "$TARGET_PATH" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
UPDATED=0
CREATED=0
MERGED=0
SKIPPED=0
NEEDS_REVIEW=0

# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------

if [ ! -f "$TEMPLATE_PATH/CLAUDE.md" ]; then
    echo -e "${RED}Error: Template not found at $TEMPLATE_PATH${NC}"
    exit 1
fi

if [ ! -f "$TARGET_PATH/wally.toml" ] && [ ! -f "$TARGET_PATH/default.project.json" ]; then
    echo -e "${RED}Error: Target doesn't look like a Roblox project at $TARGET_PATH${NC}"
    exit 1
fi

if [ "$TEMPLATE_PATH" = "$TARGET_PATH" ]; then
    echo -e "${RED}Error: Template and target are the same directory${NC}"
    exit 1
fi

# --------------------------------------------------------------------------
# Version check
# --------------------------------------------------------------------------

TEMPLATE_VERSION="$(cat "$TEMPLATE_PATH/GameVersion.txt" 2>/dev/null || echo "unknown")"
TARGET_VERSION="$(cat "$TARGET_PATH/.template-version" 2>/dev/null || echo "none")"

echo -e "${CYAN}Template Sync${NC}"
echo "  Template: $TEMPLATE_PATH (v$TEMPLATE_VERSION)"
echo "  Target:   $TARGET_PATH (synced: v$TARGET_VERSION)"
echo ""

if [ "$TEMPLATE_VERSION" = "$TARGET_VERSION" ] && [ "$TEMPLATE_VERSION" != "unknown" ]; then
    echo -e "${GREEN}Already up to date (v$TEMPLATE_VERSION).${NC}"
    echo "Use --force to sync anyway."
    if [ "${3:-}" != "--force" ]; then
        exit 0
    fi
fi

# --------------------------------------------------------------------------
# Load config
# --------------------------------------------------------------------------

source "$SCRIPT_DIR/sync-config.sh"

# --------------------------------------------------------------------------
# Helper: check if file matches always-sync list
# --------------------------------------------------------------------------
is_always_sync() {
    local file="$1"
    for pattern in "${ALWAYS_SYNC[@]}"; do
        if [ "$file" = "$pattern" ]; then
            return 0
        fi
    done
    return 1
}

# --------------------------------------------------------------------------
# Helper: check if file matches never-sync patterns
# --------------------------------------------------------------------------
is_never_sync() {
    local file="$1"
    for pattern in "${NEVER_SYNC_PATTERNS[@]}"; do
        # Exact match
        if [ "$file" = "$pattern" ]; then
            return 0
        fi
        # Glob match using bash pattern matching
        # shellcheck disable=SC2254
        case "$file" in
            $pattern) return 0 ;;
        esac
    done
    return 1
}

# --------------------------------------------------------------------------
# Helper: check if file is a merge file
# --------------------------------------------------------------------------
is_merge_file() {
    local file="$1"
    for mf in "${MERGE_FILES[@]}"; do
        if [ "$file" = "$mf" ]; then
            return 0
        fi
    done
    return 1
}

# --------------------------------------------------------------------------
# Merge: append_missing_targets (Makefile)
# --------------------------------------------------------------------------
merge_makefile() {
    local template_file="$1"
    local target_file="$2"

    if [ ! -f "$target_file" ]; then
        cp "$template_file" "$target_file"
        echo -e "${GREEN}[CREATE]${NC} $3 (copied from template)"
        CREATED=$((CREATED + 1))
        return
    fi

    # Extract target names from both Makefiles
    local template_targets target_targets added
    template_targets=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_-]*:' "$template_file" | sed 's/:.*//' | sort -u)
    target_targets=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_-]*:' "$target_file" | sed 's/:.*//' | sort -u)

    added=0
    # Also extract full target blocks from template
    for target_name in $template_targets; do
        if ! echo "$target_targets" | grep -qx "$target_name"; then
            # Extract the target block (target line + following indented lines)
            echo "" >> "$target_file"
            echo "# Added by template-sync" >> "$target_file"
            sed -n "/^${target_name}:/,/^[^	]/{ /^[^	]/!p; /^${target_name}:/p; }" "$template_file" >> "$target_file"
            added=$((added + 1))
        fi
    done

    if [ "$added" -gt 0 ]; then
        echo -e "${BLUE}[MERGE]${NC}  $3 (added $added new target(s))"
    else
        echo -e "${BLUE}[MERGE]${NC}  $3 (no new targets)"
    fi
    MERGED=$((MERGED + 1))
}

# --------------------------------------------------------------------------
# Merge: merge_dependencies (wally.toml)
# --------------------------------------------------------------------------
merge_wally() {
    local template_file="$1"
    local target_file="$2"

    if [ ! -f "$target_file" ]; then
        cp "$template_file" "$target_file"
        echo -e "${GREEN}[CREATE]${NC} $3 (copied from template)"
        CREATED=$((CREATED + 1))
        return
    fi

    local added=0
    local current_section=""

    while IFS= read -r line; do
        # Track section headers
        if [[ "$line" =~ ^\[.*\] ]]; then
            current_section="$line"
            continue
        fi

        # Skip non-dependency lines
        if [ "$current_section" != "[dependencies]" ] && [ "$current_section" != "[server-dependencies]" ]; then
            continue
        fi

        # Skip empty/comment lines
        if [[ -z "$line" ]] || [[ "$line" =~ ^# ]]; then
            continue
        fi

        # Extract dependency name (left side of =)
        local dep_name
        dep_name=$(echo "$line" | sed 's/[[:space:]]*=.*//')

        # Check if this dep exists in target
        if ! grep -q "^${dep_name}[[:space:]]*=" "$target_file"; then
            # Find or create the section in target
            if ! grep -q "^\\${current_section}" "$target_file" 2>/dev/null; then
                echo "" >> "$target_file"
                echo "$current_section" >> "$target_file"
            fi
            # Append the dependency under the correct section
            # Find the section and append after it (before next section or EOF)
            local section_escaped
            section_escaped=$(echo "$current_section" | sed 's/\[/\\[/g; s/\]/\\]/g')
            # Use awk to insert the line after the section
            awk -v section="$current_section" -v newline="$line" '
                $0 == section { print; found=1; next }
                found && (/^\[/ || /^$/) { print newline; found=0 }
                { print }
                END { if (found) print newline }
            ' "$target_file" > "${target_file}.tmp"
            mv "${target_file}.tmp" "$target_file"
            added=$((added + 1))
        fi
    done < "$template_file"

    if [ "$added" -gt 0 ]; then
        echo -e "${BLUE}[MERGE]${NC}  $3 (added $added new dep(s))"
    else
        echo -e "${BLUE}[MERGE]${NC}  $3 (no new deps)"
    fi
    MERGED=$((MERGED + 1))
}

# --------------------------------------------------------------------------
# Merge: append_sections (CLAUDE.md)
# --------------------------------------------------------------------------
merge_claude_md() {
    local template_file="$1"
    local target_file="$2"

    if [ ! -f "$target_file" ]; then
        cp "$template_file" "$target_file"
        echo -e "${GREEN}[CREATE]${NC} $3 (copied from template)"
        CREATED=$((CREATED + 1))
        return
    fi

    # Extract ## section headers from both files
    local template_sections target_sections added
    template_sections=$(grep -E '^## ' "$template_file" | sort -u)
    target_sections=$(grep -E '^## ' "$target_file" | sort -u)

    added=0

    while IFS= read -r section_header; do
        [ -z "$section_header" ] && continue

        if ! echo "$target_sections" | grep -qxF "$section_header"; then
            # Extract full section from template (from header to next ## or EOF)
            local section_escaped
            section_escaped=$(echo "$section_header" | sed 's/[[\.*^$()+?{|]/\\&/g')
            echo "" >> "$target_file"
            sed -n "/^${section_escaped}$/,/^## /{ /^## /!p; /^${section_escaped}$/p; }" "$template_file" >> "$target_file"
            added=$((added + 1))
        fi
    done <<< "$template_sections"

    # Update template-managed sections (marked with <!-- template-managed -->)
    while IFS= read -r section_header; do
        [ -z "$section_header" ] && continue

        # Check if this section is template-managed in the template
        local section_escaped
        section_escaped=$(echo "$section_header" | sed 's/[[\.*^$()+?{|]/\\&/g')
        local template_section
        template_section=$(sed -n "/^${section_escaped}$/,/^## /{ /^## /!p; /^${section_escaped}$/p; }" "$template_file")

        if echo "$template_section" | grep -q '<!-- template-managed -->'; then
            # Check if this section exists in target
            if echo "$target_sections" | grep -qxF "$section_header"; then
                # Replace the section in target with template version
                local temp_file="${target_file}.tmp"
                awk -v header="$section_header" '
                    BEGIN { skip=0 }
                    $0 == header { skip=1; next }
                    skip && /^## / { skip=0 }
                    !skip { print }
                ' "$target_file" > "$temp_file"

                # Now insert the template section at the end (or we could try to maintain position)
                echo "" >> "$temp_file"
                echo "$template_section" >> "$temp_file"
                mv "$temp_file" "$target_file"
                added=$((added + 1))
            fi
        fi
    done <<< "$template_sections"

    if [ "$added" -gt 0 ]; then
        echo -e "${BLUE}[MERGE]${NC}  $3 (added/updated $added section(s))"
    else
        echo -e "${BLUE}[MERGE]${NC}  $3 (no new sections)"
    fi
    MERGED=$((MERGED + 1))
}

# --------------------------------------------------------------------------
# Ensure directories
# --------------------------------------------------------------------------
echo "Ensuring directories..."
for dir in "${ENSURE_DIRECTORIES[@]}"; do
    if [ ! -d "$TARGET_PATH/$dir" ]; then
        mkdir -p "$TARGET_PATH/$dir"
        echo -e "${GREEN}[MKDIR]${NC}  $dir"
    fi
done
echo ""

# --------------------------------------------------------------------------
# Process always-sync files
# --------------------------------------------------------------------------
echo "Syncing files..."
for file in "${ALWAYS_SYNC[@]}"; do
    if [ ! -f "$TEMPLATE_PATH/$file" ]; then
        echo -e "${YELLOW}[WARN]${NC}   Template missing: $file"
        continue
    fi

    target_dir=$(dirname "$TARGET_PATH/$file")
    mkdir -p "$target_dir"

    if [ ! -f "$TARGET_PATH/$file" ]; then
        cp "$TEMPLATE_PATH/$file" "$TARGET_PATH/$file"
        echo -e "${GREEN}[CREATE]${NC} $file"
        CREATED=$((CREATED + 1))
    elif ! diff -q "$TEMPLATE_PATH/$file" "$TARGET_PATH/$file" > /dev/null 2>&1; then
        cp "$TEMPLATE_PATH/$file" "$TARGET_PATH/$file"
        echo -e "${GREEN}[SYNC]${NC}   $file"
        UPDATED=$((UPDATED + 1))
    else
        SKIPPED=$((SKIPPED + 1))
    fi
done

# --------------------------------------------------------------------------
# Process merge files
# --------------------------------------------------------------------------
echo ""
echo "Merging files..."
for file in "${MERGE_FILES[@]}"; do
    if [ ! -f "$TEMPLATE_PATH/$file" ]; then
        echo -e "${YELLOW}[WARN]${NC}   Template missing: $file"
        continue
    fi

    case "$file" in
        Makefile)
            merge_makefile "$TEMPLATE_PATH/$file" "$TARGET_PATH/$file" "$file"
            ;;
        wally.toml)
            merge_wally "$TEMPLATE_PATH/$file" "$TARGET_PATH/$file" "$file"
            ;;
        CLAUDE.md)
            merge_claude_md "$TEMPLATE_PATH/$file" "$TARGET_PATH/$file" "$file"
            ;;
    esac
done

# --------------------------------------------------------------------------
# Detect new template files not in any list
# --------------------------------------------------------------------------
echo ""
echo "Checking for new template files..."

# Get all tracked files in template (use git ls-files if available, else find)
if [ -d "$TEMPLATE_PATH/.git" ]; then
    template_files=$(cd "$TEMPLATE_PATH" && git ls-files 2>/dev/null || find . -type f | sed 's|^\./||')
else
    template_files=$(cd "$TEMPLATE_PATH" && find . -type f | sed 's|^\./||')
fi

while IFS= read -r file; do
    [ -z "$file" ] && continue

    # Skip files in gitignored / build dirs
    case "$file" in
        .git/*|Packages/*|ServerPackages/*|node_modules/*|.wally-installed|sourcemap.json) continue ;;
        *.lock) continue ;;
    esac

    # Skip if already handled
    if is_always_sync "$file" || is_merge_file "$file" || is_never_sync "$file"; then
        continue
    fi

    # Skip if it's a directory marker
    [ -d "$TEMPLATE_PATH/$file" ] && continue

    # This file exists in template but isn't in any sync list
    if [ ! -f "$TARGET_PATH/$file" ]; then
        echo -e "${YELLOW}[NEW]${NC}    New template file not in sync config: $file"
        NEEDS_REVIEW=$((NEEDS_REVIEW + 1))
    fi
done <<< "$template_files"

# --------------------------------------------------------------------------
# Update version tracking
# --------------------------------------------------------------------------
echo "$TEMPLATE_VERSION" > "$TARGET_PATH/.template-version"

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo -e "${CYAN}Summary:${NC} $UPDATED updated, $CREATED created, $MERGED merged, $SKIPPED unchanged, $NEEDS_REVIEW needs review"
echo ""
echo -e "Synced to template version: ${GREEN}v$TEMPLATE_VERSION${NC}"

# Show git diff if target is a git repo
if [ -d "$TARGET_PATH/.git" ]; then
    echo ""
    echo "Changes in target repo:"
    (cd "$TARGET_PATH" && git diff --stat 2>/dev/null)
    echo ""
    echo -e "Review changes, then: ${CYAN}git add -A && git commit -m 'Sync from roblox-template v${TEMPLATE_VERSION}'${NC}"
fi
