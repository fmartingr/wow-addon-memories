SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

LUA_COVERAGE_MIN ?= 80
DART_COVERAGE_MIN ?= 80
CORE := packages/memories_core
COMPANION_DEVICE ?= $(if $(filter Darwin,$(shell uname -s)),macos,$(if $(filter Linux,$(shell uname -s)),linux,windows))
BUSTED_FLAGS ?=
ADDONS := $(notdir $(wildcard addons/*))

LR_PATH := $(shell luarocks --lua-version=5.1 --local path --lr-path 2>/dev/null)
LR_CPATH := $(shell luarocks --lua-version=5.1 --local path --lr-cpath 2>/dev/null)
export PATH := $(HOME)/.luarocks/bin:$(PATH)
export LUA_PATH := $(LR_PATH);$(LUA_PATH);;
export LUA_CPATH := $(LR_CPATH);$(LUA_CPATH);;

.PHONY: help check-tools deps lint lint-lua lint-no-go lint-actions dart-lint app-lint fmt-check fmt test test-lua test-scripts dart-test app-test companion coverage coverage-lua dart-coverage export link install clean web-data web web-demo

help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-16s %s\n", $$1, $$2}'

check-tools: ## Report each missing tool
	@missing=0; for t in lua5.1 luarocks busted luacheck luacov stylua fvm; do \
		if ! command -v $$t >/dev/null; then echo "missing: $$t"; missing=1; fi; \
	done; exit $$missing

deps: ## Install the Lua test and lint tools with luarocks
	luarocks --lua-version=5.1 --local install busted 2.3.0-1
	luarocks --lua-version=5.1 --local install luacov 0.17.0-1
	luarocks --lua-version=5.1 --local install luacheck 1.2.0-1

lint: lint-lua lint-no-go lint-actions dart-lint app-lint fmt-check ## Run all linters

lint-lua: ## Run luacheck
	luacheck .

lint-no-go: ## Fail when a Go file, go.mod or go.sum is tracked
	bash scripts/no-go.sh

lint-actions: ## Check the GitHub workflows with actionlint, when it is installed (CI always runs it)
	@if command -v actionlint >/dev/null; then actionlint; else echo "lint-actions: actionlint is not installed, skipped"; fi

dart-lint: ## Analyze and check the format of the Dart core
	cd $(CORE) && fvm dart pub get
	cd $(CORE) && fvm dart analyze --fatal-infos
	cd $(CORE) && fvm dart format --output=none --set-exit-if-changed .

app-lint: ## Analyze and check the format of the Flutter app
	cd app && fvm flutter analyze
	cd app && fvm dart format --output=none --set-exit-if-changed .

fmt-check: ## Check the Lua format
	stylua --check .

fmt: ## Format the Lua and Dart code
	stylua .
	cd $(CORE) && fvm dart format .
	cd app && fvm dart format .

test: test-lua test-scripts dart-test app-test ## Run all tests

test-lua: ## Run the busted tests
	busted $(BUSTED_FLAGS)

test-scripts: ## Test the release scripts (addon zip, release version)
	bash scripts/test-package-addons.sh
	bash scripts/test-release-version.sh

dart-test: ## Run the Dart core tests
	cd $(CORE) && fvm dart test

app-test: ## Run the Flutter app tests
	cd app && fvm flutter test

companion: ## Run the WoW Journey companion app on this system (COMPANION_DEVICE overrides the device)
	cd app && fvm flutter run -d $(COMPANION_DEVICE)

coverage: coverage-lua dart-coverage ## Run tests with coverage thresholds

coverage-lua: ## Run busted with luacov and check the core coverage
	rm -f luacov.stats.out luacov.report.out
	busted --coverage $(BUSTED_FLAGS)
	luacov
	LUA_COVERAGE_MIN=$(LUA_COVERAGE_MIN) bash scripts/coverage.sh luacov.report.out

dart-coverage: ## Run the Dart core tests with the coverage threshold
	DART_COVERAGE_MIN=$(DART_COVERAGE_MIN) bash scripts/dart-coverage.sh $(CORE)

export: ## Run the converter on WOW_DIR (a flavor folder); DIST, BACKUP and DEFAULT are optional
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_forever_" >&2; exit 2; fi
	@fvm dart pub get --directory=$(CORE) >/dev/null
	fvm dart run $(CORE)/bin/memories_export.dart --wow-dir "$(WOW_DIR)" \
		$(if $(DIST),--dist "$(DIST)") $(if $(BACKUP),--backup "$(BACKUP)") $(if $(DEFAULT),--default "$(DEFAULT)")

link: ## Link each addon folder into WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_forever_" >&2; exit 2; fi
	@if [ ! -d "$(WOW_DIR)/Interface/AddOns" ]; then echo "link: $(WOW_DIR)/Interface/AddOns does not exist" >&2; exit 1; fi
	for a in $(ADDONS); do \
		d="$(WOW_DIR)/Interface/AddOns/$$a"; \
		if [ -e "$$d" ] && [ ! -L "$$d" ]; then rm -rf "$$d"; fi; \
		ln -sfn "$(CURDIR)/addons/$$a" "$$d"; \
	done

install: ## Copy each addon folder into WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_forever_" >&2; exit 2; fi
	@if [ ! -d "$(WOW_DIR)/Interface/AddOns" ]; then echo "install: $(WOW_DIR)/Interface/AddOns does not exist" >&2; exit 1; fi
	for a in $(ADDONS); do rm -rf "$(WOW_DIR)/Interface/AddOns/$$a"; cp -R "addons/$$a" "$(WOW_DIR)/Interface/AddOns/$$a"; done

clean: ## Remove build output
	rm -rf luacov.*.out $(CORE)/coverage app/build app/coverage

WEB_PORT ?= 8765

web-data: ## Run the converter into dist-characters/ for the viewer (needs WOW_DIR)
	@$(MAKE) --no-print-directory export

web: ## Serve the viewer in web/ with dist-characters/ at http://localhost:$(WEB_PORT)
	@if [ ! -f dist-characters/index.json ]; then echo "web: run 'make web-data WOW_DIR=...' first, or 'make web-demo'" >&2; exit 1; fi
	ln -sfn "$(CURDIR)/dist-characters" web/characters
	@echo "Serving at http://localhost:$(WEB_PORT)"
	python3 -m http.server $(WEB_PORT) --directory web

web-demo: ## Serve the viewer with the converter golden files in testdata/expected
	ln -sfn "$(CURDIR)/testdata/expected" web/characters
	@echo "Serving at http://localhost:$(WEB_PORT)"
	python3 -m http.server $(WEB_PORT) --directory web
