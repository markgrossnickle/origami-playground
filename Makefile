ifeq ($(OS),Windows_NT)
	TOUCH := type NUL >>
else
	TOUCH := touch
endif

SRC := src
SRC_FILES := $(wildcard $(SRC)/**/*.luau)

ROJO := rojo
SOURCEMAP_FILE := sourcemap.json

WALLY := wally
WALLY_INSTALLED := .wally-installed

WALLY_PACKAGE_TYPES := wally-package-types
WALLY_PACKAGES_FIXED := Packages/.wally-package-types-fixed
WALLY_SERVER_PACKAGES_FIXED := ServerPackages/.wally-package-types-fixed

.PHONY: wally-package-types wally-install clean test test-watch

wally-package-types: $(WALLY_PACKAGES_FIXED) $(WALLY_SERVER_PACKAGES_FIXED)

$(WALLY_PACKAGES_FIXED): $(WALLY_INSTALLED) $(SOURCEMAP_FILE)
	$(WALLY_PACKAGE_TYPES) --sourcemap $(SOURCEMAP_FILE) Packages
	$(TOUCH) $@

$(WALLY_SERVER_PACKAGES_FIXED): $(WALLY_INSTALLED) $(SOURCEMAP_FILE)
	$(WALLY_PACKAGE_TYPES) --sourcemap $(SOURCEMAP_FILE) ServerPackages
	$(TOUCH) $@

wally-install: $(WALLY_INSTALLED)

$(WALLY_INSTALLED): wally.toml
	$(WALLY) install
	$(TOUCH) $@

$(SOURCEMAP_FILE): $(SRC_FILES) | $(WALLY_INSTALLED)
	$(ROJO) sourcemap --output $(SOURCEMAP_FILE)
	$(TOUCH) $@

clean:
	$(RM) -f $(SOURCEMAP_FILE)
	$(RM) -rf $(WALLY_INSTALLED)
	$(RM) -rf $(WALLY_PACKAGES_FIXED)
	$(RM) -rf $(WALLY_SERVER_PACKAGES_FIXED)
	$(RM) -rf Packages
	$(RM) -rf ServerPackages

test:
	lune run tests/runner

test-watch:
	fswatch -o src/ tests/ | xargs -I{} lune run tests/runner

# Documentation
include docs.mk
