# ⚠️ BEFORE STARTING

1. Add your development place Id to the list of serverPlaceIds in `default.project.json`
2. Update project name and urls:
    1. `default.project.json`
    2. `wally.toml`
    3. `moonwave.toml`
3. Configure experience badges (if applicable) and badge data as soon as possible in `ReplicatedStorage/Shared/BadgeData`
4. Update game IDs in `src/ReplicatedStorage/Shared/Environment.luau`


# mindtrustlabs/roblox-template

This is a [Roblox](https://create.roblox.com/docs) project which uses a partially-managed Rojo project to sync code into Roblox Studio using Team Create enabled places.

## Development

### Tools

Install [aftman 0.3.0](https://github.com/LPGhatguy/aftman/releases/tag/v0.3.0), then run `aftman install` on the root directory of this repository. Aftman will install correct versions of command line tools needed for this project, such as:

* [Rojo](https://rojo.space) - Sync tool
* [selene](https://github.com/Kampfkarren/selene) - Linter
* [StyLua](https://github.com/JohnnyMorganz/StyLua) - Formatter
* [Wally](https://wally.run/) - Package manager

Running the [Makefile](Makefile) will automatically install Wally dependencies and fix the exported Luau types within them using the [Wally Package Types Fixer](https://github.com/JohnnyMorganz/wally-package-types).

### Documentation

Documentation is built using [Moonwave](https://eryn.io/moonwave), which builds the documentation from in-code doc comments. See [docs/intro.md](docs/intro.md) for more information.

### Environments

Various experiences which house copies of the game to be worked on. The kind of environment you are playing is visible at the top of the screen.

* Developer: For use by individuals as they work on the game. These follow a "Dev: Name" convention.
* Asset Storage is where game assets are stored
* Staging is where individuals' work comes together in one place.

### Framework

This game uses Knit.
