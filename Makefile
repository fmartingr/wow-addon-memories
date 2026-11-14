SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

LUA_COVERAGE_MIN ?= 80
DART_COVERAGE_MIN ?= 80
SERVER_COVERAGE_MIN ?= 80
CORE := packages/memories_core
COMPANION_DEVICE ?= $(if $(filter Darwin,$(shell uname -s)),macos,$(if $(filter Linux,$(shell uname -s)),linux,windows))
BUSTED_FLAGS ?=
ADDONS := $(notdir $(wildcard addons/*))

LR_PATH := $(shell luarocks --lua-version=5.1 --local path --lr-path 2>/dev/null)
LR_CPATH := $(shell luarocks --lua-version=5.1 --local path --lr-cpath 2>/dev/null)
export PATH := $(HOME)/.luarocks/bin:$(PATH)
export LUA_PATH := $(LR_PATH);$(LUA_PATH);;
export LUA_CPATH := $(LR_CPATH);$(LUA_CPATH);;

.PHONY: app-viewer app-viewer-check help check-tools deps lint lint-lua lint-no-go lint-actions server-lint dart-lint app-lint fmt-check fmt test test-lua test-scripts server-test dart-test app-test companion coverage coverage-lua server-coverage dart-coverage server-run server-build local-up local-down local-logs companion-local export upload e2e link install clean web-assets web-lint web-test app-theme theme-check app-shots

help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-16s %s\n", $$1, $$2}'

check-tools: ## Report each missing tool
	@missing=0; for t in lua5.1 luarocks busted luacheck luacov stylua go fvm curl jq python3; do \
		if ! command -v $$t >/dev/null; then echo "missing: $$t"; missing=1; fi; \
	done; exit $$missing

deps: ## Install the Lua test and lint tools with luarocks
	luarocks --lua-version=5.1 --local install busted 2.3.0-1
	luarocks --lua-version=5.1 --local install luacov 0.17.0-1
	luarocks --lua-version=5.1 --local install luacheck 1.2.0-1

lint: lint-lua lint-no-go lint-actions server-lint web-lint theme-check dart-lint app-lint app-viewer-check fmt-check ## Run all linters

lint-lua: ## Run luacheck
	luacheck .

lint-no-go: ## Fail when a Go file, go.mod or go.sum is tracked outside server/ (and test that check)
	bash scripts/no-go_test.sh
	bash scripts/no-go.sh

lint-actions: ## Check the GitHub workflows with actionlint, when it is installed (CI always runs it)
	@if command -v actionlint >/dev/null; then actionlint; else echo "lint-actions: actionlint is not installed, skipped"; fi

server-lint: ## Run gofmt and go vet on the Go server
	@cd server && unformatted="$$(gofmt -l .)" && if [ -n "$$unformatted" ]; then echo "server-lint: run gofmt -w on:" >&2; echo "$$unformatted" >&2; exit 1; fi
	cd server && go vet ./...

web-lint: ## Check the syntax of each web/**/*.mjs file
	@find web -name '*.mjs' -not -path 'web/map/*' -print0 | xargs -0 -n1 node --check

web-test: ## Run the node tests of the viewer logic with a coverage threshold (lines of web/lib/ at least 80 %)
	node --test --experimental-test-coverage --test-coverage-lines=80 --test-coverage-include='web/lib/**' 'web/test/*.test.mjs'

app-theme: ## Write app/lib/src/theme/tokens.dart from the website tokens (web/base.css)
	node scripts/gen-app-theme.mjs

theme-check: ## Check that the app tokens are up to date and that the website and app themes match (node only)
	node scripts/gen-app-theme.mjs --check
	node scripts/theme-parity.mjs

app-viewer: ## Copy the viewer files of web/ into app/assets/viewer/
	cd app && fvm dart run tool/viewer_assets.dart

# With -j, make lint or make test makes the copy in the same run; the check waits for it.
app-viewer-check: | $(if $(filter lint test,$(MAKECMDGOALS)),app-viewer)
app-viewer-check: ## Check that app/assets/viewer/ matches web/ and that pubspec.yaml lists every folder of it
	cd app && fvm dart run tool/viewer_assets.dart --check

app-shots: app-viewer ## Write PNG pictures of the app screens to THEME_SHOTS (default build/theme-shots) for the theme review
	cd app && THEME_PREVIEW_DIR="$(abspath $(or $(THEME_SHOTS),build/theme-shots))" fvm flutter test test/theme_preview_test.dart

dart-lint: ## Analyze and check the format of the Dart core
	cd $(CORE) && fvm dart pub get
	cd $(CORE) && fvm dart analyze --fatal-infos
	cd $(CORE) && fvm dart format --output=none --set-exit-if-changed .

app-lint: app-viewer ## Analyze and check the format of the Flutter app
	cd app && fvm flutter analyze
	cd app && fvm dart format --output=none --set-exit-if-changed .

fmt-check: ## Check the Lua format
	stylua --check .

fmt: ## Format the Lua, Dart and Go code
	stylua .
	cd $(CORE) && fvm dart format .
	cd app && fvm dart format .
	cd server && gofmt -w .

test: test-lua test-scripts server-test web-test dart-test app-test ## Run all tests

test-lua: ## Run the busted tests
	busted $(BUSTED_FLAGS)

test-scripts: ## Test the release scripts (addon zip, release version, addon changes)
	bash scripts/test-package-addons.sh
	bash scripts/test-release-version.sh
	bash scripts/test-addons-changed.sh

server-test: ## Run the Go server tests with the race detector (FUZZ=1 also fuzzes the upload check for 30 s)
	cd server && go test -race ./...
	@if [ "$(FUZZ)" = 1 ]; then cd server && go test -run '^$$' -fuzz '^FuzzUpload$$' -fuzztime 30s ./internal/validate; fi

dart-test: ## Run the Dart core tests
	cd $(CORE) && fvm dart test

app-test: app-viewer ## Run the Flutter app tests
	cd app && fvm flutter test

companion: app-viewer ## Run the WoW Journey companion app on this system (COMPANION_DEVICE overrides the device)
	cd app && fvm flutter run -d $(COMPANION_DEVICE)

coverage: coverage-lua server-coverage dart-coverage ## Run tests with coverage thresholds

coverage-lua: ## Run busted with luacov and check the coverage of the addon files
	rm -f luacov.stats.out luacov.report.out
	busted --coverage $(BUSTED_FLAGS)
	luacov
	LUA_COVERAGE_MIN=$(LUA_COVERAGE_MIN) bash scripts/coverage.sh luacov.report.out

server-coverage: ## Run the Go server tests with the coverage threshold
	@cd server && go test -coverprofile=coverage.out ./internal/...; \
	total=$$(go tool cover -func=coverage.out | awk '$$1 == "total:" { gsub("%", "", $$NF); print $$NF }'); \
	echo "Go server coverage: $$total% (min $(SERVER_COVERAGE_MIN)%)"; \
	awk -v t="$$total" -v m="$(SERVER_COVERAGE_MIN)" 'BEGIN { exit (t + 0 < m + 0) }'

dart-coverage: ## Run the Dart core tests with the coverage threshold
	DART_COVERAGE_MIN=$(DART_COVERAGE_MIN) bash scripts/dart-coverage.sh $(CORE)

server-run: ## Run the Go server (settings come from MEMORIES_* environment variables)
	cd server && go run ./cmd/memories-server

LOCAL_NAME ?= memories-local
LOCAL_PORT ?= 8080
LOCAL_ADMIN_PORT ?= 8081

local-up: ## Build the Docker image and run a local test server (open registration, data in a Docker volume)
	docker build -f server/Dockerfile -t memories-server .
	-docker rm -f $(LOCAL_NAME) >/dev/null 2>&1
	docker run -d --name $(LOCAL_NAME) \
		-p 127.0.0.1:$(LOCAL_PORT):8080 -p 127.0.0.1:$(LOCAL_ADMIN_PORT):8081 \
		-v $(LOCAL_NAME)-data:/data \
		-e MEMORIES_SITE_URL=http://localhost:$(LOCAL_PORT) \
		-e MEMORIES_REGISTRATION=open \
		memories-server >/dev/null
	@echo "Site:  http://localhost:$(LOCAL_PORT)/"
	@echo "Admin: http://localhost:$(LOCAL_ADMIN_PORT)/"
	@echo "App:   make companion-local"

local-down: ## Stop the local test server and delete its data (volume)
	-docker rm -f $(LOCAL_NAME)
	-docker volume rm $(LOCAL_NAME)-data

local-logs: ## Follow the log of the local test server
	docker logs -f $(LOCAL_NAME)

companion-local: app-viewer ## Run the companion app with http://localhost:$(LOCAL_PORT) as the default website
	cd app && fvm flutter run -d $(COMPANION_DEVICE) --dart-define=WOWJOURNEY_SITE=http://localhost:$(LOCAL_PORT)

server-build: ## Build the static Go server into build/memories-server
	cd server && CGO_ENABLED=0 go build -o ../build/memories-server ./cmd/memories-server

export: ## Run the converter on WOW_DIR (a flavor folder); DIST, BACKUP and DEFAULT are optional
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_forever_" >&2; exit 2; fi
	@fvm dart pub get --directory=$(CORE) >/dev/null
	fvm dart run $(CORE)/bin/memories_export.dart --wow-dir "$(WOW_DIR)" \
		$(if $(DIST),--dist "$(DIST)") $(if $(BACKUP),--backup "$(BACKUP)") $(if $(DEFAULT),--default "$(DEFAULT)")

upload: ## Run memories-upload for SITE; LATEST, KEY, STATE, INVITE, DELETE, ONLY (paths separated by spaces) and REQUEST_SCREENSHOTS=1 are optional
	@if [ -z "$${SITE:-}" ]; then echo "SITE is required, for example https://wowjourney.xyz" >&2; exit 2; fi
	@fvm dart pub get --directory=$(CORE) >/dev/null
	fvm dart run $(CORE)/bin/memories_upload.dart --site "$(SITE)" \
		$(if $(LATEST),--latest "$(LATEST)") $(if $(KEY),--key "$(KEY)") $(if $(STATE),--state "$(STATE)") \
		$(if $(INVITE),--invite "$(INVITE)") $(if $(DELETE),--delete "$(DELETE)") $(foreach path,$(ONLY),--only "$(path)") $(if $(filter 1,$(REQUEST_SCREENSHOTS)),--request-screenshots)

e2e: ## Build the server and run memories-upload against it (needs go, fvm, curl, jq, python3)
	bash scripts/e2e-upload.sh

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
	rm -rf luacov.*.out $(CORE)/coverage app/build app/coverage server/coverage.out build/memories-server

web-assets: ## Copy the map art from MAP_SRC (a map art folder with assets/world.js) into web/map/, and keep web/map/README.md
	@for f in art mini tiles world.js; do if [ ! -e "$(MAP_SRC)/assets/$$f" ]; then echo "web-assets: MAP_SRC must be a map art folder with assets/art, assets/mini, assets/tiles and assets/world.js, for example MAP_SRC=~/Code/map-art" >&2; exit 2; fi; done
	mkdir -p web/map
	rm -rf web/map/art web/map/mini web/map/tiles web/map/world.js
	cp -R "$(MAP_SRC)/assets/art" "$(MAP_SRC)/assets/mini" "$(MAP_SRC)/assets/tiles" "$(MAP_SRC)/assets/world.js" web/map/
