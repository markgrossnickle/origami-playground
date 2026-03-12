#!/bin/bash
# sync-config.sh — Defines what files to sync from roblox-template to game repos
# Source this file from template-sync.sh

# Files that are ALWAYS overwritten from template (shared infrastructure)
ALWAYS_SYNC=(
    # Toolchain
    "aftman.toml"
    "stylua.toml"
    "selene.toml"
    ".github/workflows/analyze.yml"
    ".gitignore"
    ".gitattributes"
    "docs.mk"

    # VSCode config
    ".vscode/extensions.json"
    ".vscode/settings.json"
    ".vscode/Knit.code-snippets"
    ".vscode/Component.code-snippets"
    ".vscode/Cmdr.code-snippets"
    ".vscode/Moonwave.code-snippets"
    ".vscode/Shortcuts.code-snippets"

    # Shared source modules (non-config)
    "src/ReplicatedStorage/Shared/Environment.luau"
    "src/ReplicatedStorage/Shared/GameVersion.luau"
    "src/ReplicatedStorage/Shared/CmdrHelper.luau"

    # Bootstrap / entry points
    "src/ServerScriptService/Server/Main.server.luau"
    "src/ServerScriptService/Server/init.luau"
    "src/ReplicatedStorage/Client/ClientEntry.server.luau"
    "src/ReplicatedStorage/Client/init.luau"

    # Template services (shared infrastructure)
    "src/ServerScriptService/Server/Services/PlayerDataService/init.luau"
    "src/ServerScriptService/Server/Services/MonetizationService/init.luau"
    "src/ServerScriptService/Server/Services/AnalyticsService/init.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/init.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/SetConfig.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/SetConfigServer.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/GetConfig.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/GetConfigServer.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/ResetConfig.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/ResetConfigServer.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/ListConfigs.luau"
    "src/ServerScriptService/Server/Services/LiveConfigService/Commands/ListConfigsServer.luau"
    "src/ServerScriptService/Server/Services/ShopService/init.luau"
    "src/ServerScriptService/Server/Services/CmdrService/init.luau"
    "src/ServerScriptService/Server/Services/CmdrService/Commands/GameEnvironment.luau"
    "src/ServerScriptService/Server/Services/CmdrService/Commands/GameVersion.luau"

    # Template controllers
    "src/ReplicatedStorage/Client/Controllers/DailyRewardController/init.luau"
    "src/ReplicatedStorage/Client/Controllers/ShopController/init.luau"

    # Sync tool itself
    "tools/sync-config.sh"
    "tools/template-sync.sh"
    "tools/sync-all-games.sh"
)

# Glob patterns for files that are NEVER synced (game-specific)
NEVER_SYNC_PATTERNS=(
    "README.md"
    "default.project.json"
    "wally.lock"
    "GameVersion.txt"
    ".template-version"
    "src/ReplicatedStorage/Shared/MonetizationConfig.luau"
    "src/ReplicatedStorage/Shared/ShopConfig.luau"
    "src/ReplicatedStorage/Shared/GameConfig.luau"
    "CONTRIBUTING.md"
    "moonwave.toml"
    ".vscode/mcp.json"
)

# Files that get merged instead of overwritten
MERGE_FILES=(
    "Makefile"
    "wally.toml"
    "CLAUDE.md"
)

# Merge strategies for each merge file
# Makefile      -> append_missing_targets
# wally.toml    -> merge_dependencies
# CLAUDE.md     -> append_sections

# Directories to create if missing (but don't overwrite contents)
ENSURE_DIRECTORIES=(
    ".github/workflows"
    "tools"
    "src/ReplicatedStorage/Shared/Components"
    "src/ReplicatedStorage/Shared/Enums"
    "src/ReplicatedStorage/Client/Components"
    "src/ReplicatedStorage/Client/Controllers"
    "src/ServerScriptService/Server/Components"
    "src/ServerScriptService/Server/Services"
)
