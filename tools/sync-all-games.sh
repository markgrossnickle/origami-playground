#!/bin/bash
# sync-all-games.sh — Syncs roblox-template into all game repos
# Run from roblox-template directory or pass template path as $1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${1:-$(dirname "$SCRIPT_DIR")}"
GAMES_DIR="/Users/Shared/Projects"

GAMES=(
    onslaught
    dig-dug
    threshold
    void-forge
    void-ascent
    void-depths
    void-racers
    void-arena
    void-pets
    Worms-playground
    forgefire
    Tower-playground
    Mining-playground
    sumo-kitties
    boopsquad
)

echo "=== Template Sync: All Games ==="
echo "Template: $TEMPLATE_PATH"
echo ""

SYNCED=0
MISSING=0

for game in "${GAMES[@]}"; do
    if [ -d "$GAMES_DIR/$game" ]; then
        echo "============================================================"
        echo "  Syncing: $game"
        echo "============================================================"
        bash "$SCRIPT_DIR/template-sync.sh" "$TEMPLATE_PATH" "$GAMES_DIR/$game"
        echo ""
        SYNCED=$((SYNCED + 1))
    else
        echo "[SKIP] $game — directory not found at $GAMES_DIR/$game"
        MISSING=$((MISSING + 1))
    fi
done

echo "============================================================"
echo "Done. Synced $SYNCED game(s), $MISSING not found."
