SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

LUA_COVERAGE_MIN ?= 80
GO_COVERAGE_MIN ?= 80
BUSTED_FLAGS ?=
ADDONS := $(notdir $(wildcard addons/*))

LR_PATH := $(shell luarocks --lua-version=5.1 --local path --lr-path 2>/dev/null)
LR_CPATH := $(shell luarocks --lua-version=5.1 --local path --lr-cpath 2>/dev/null)
export PATH := $(HOME)/.luarocks/bin:$(PATH)
export LUA_PATH := $(LR_PATH);$(LUA_PATH);;
export LUA_CPATH := $(LR_CPATH);$(LUA_CPATH);;

.PHONY: help check-tools deps lint lint-lua lint-go fmt-check fmt test test-lua test-go coverage coverage-lua coverage-go build export link install clean web-data web web-demo

help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-16s %s\n", $$1, $$2}'

check-tools: ## Report each missing tool
	@missing=0; for t in lua5.1 luarocks busted luacheck luacov stylua go; do \
		if ! command -v $$t >/dev/null; then echo "missing: $$t"; missing=1; fi; \
	done; exit $$missing

deps: ## Install the Lua test and lint tools with luarocks
	luarocks --lua-version=5.1 --local install busted 2.3.0-1
	luarocks --lua-version=5.1 --local install luacov 0.17.0-1
	luarocks --lua-version=5.1 --local install luacheck 1.2.0-1

lint: lint-lua lint-go fmt-check ## Run all linters

lint-lua: ## Run luacheck
	luacheck .

lint-go: ## Run gofmt and go vet
	test -z "$$(gofmt -l .)"
	go vet ./...

fmt-check: ## Check the Lua format
	stylua --check .

fmt: ## Format the Lua and Go code
	stylua .
	gofmt -w .

test: test-lua test-go ## Run all tests

test-lua: ## Run the busted tests
	busted $(BUSTED_FLAGS)

test-go: ## Run the Go tests with the race detector
	go test -race ./...

coverage: coverage-lua coverage-go ## Run tests with coverage thresholds

coverage-lua: ## Run busted with luacov and check the core coverage
	rm -f luacov.stats.out luacov.report.out
	busted --coverage $(BUSTED_FLAGS)
	luacov
	LUA_COVERAGE_MIN=$(LUA_COVERAGE_MIN) bash scripts/coverage.sh luacov.report.out

coverage-go: ## Run Go tests with the coverage threshold
	@if [ -z "$$(go list ./internal/... 2>/dev/null)" ]; then echo "Go coverage: no packages in internal/"; exit 0; fi; \
	go test -coverprofile=coverage.out ./internal/...; \
	total=$$(go tool cover -func=coverage.out | awk '$$1 == "total:" { gsub("%", "", $$NF); print $$NF }'); \
	echo "Go coverage: $$total% (min $(GO_COVERAGE_MIN)%)"; \
	awk -v t="$$total" -v m="$(GO_COVERAGE_MIN)" 'BEGIN { exit (t + 0 < m + 0) }'

build: ## Build the converter into build/
	CGO_ENABLED=0 go build -o build/memories-export ./cmd/memories-export

export: ## Run the converter on WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_forever_" >&2; exit 2; fi
	go run ./cmd/memories-export --wow-dir "$(WOW_DIR)"

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
	rm -rf build luacov.*.out coverage.out

WEB_PORT ?= 8765

web-data: ## Run the converter into dist-characters/ for the viewer (needs WOW_DIR)
	@$(MAKE) --no-print-directory export

web: ## Serve the viewer in web/ with dist-characters/ at http://localhost:$(WEB_PORT)
	@if [ ! -f dist-characters/index.json ]; then echo "web: run 'make web-data WOW_DIR=...' first, or 'make web-demo'" >&2; exit 1; fi
	ln -sfn "$(CURDIR)/dist-characters" web/characters
	@echo "Serving at http://localhost:$(WEB_PORT)"
	python3 -m http.server $(WEB_PORT) --directory web

web-demo: ## Serve the viewer with the converter test data
	ln -sfn "$(CURDIR)/cmd/memories-export/testdata/expected" web/characters
	@echo "Serving at http://localhost:$(WEB_PORT)"
	python3 -m http.server $(WEB_PORT) --directory web
