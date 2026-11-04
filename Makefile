# Kitfold developer tasks. Run `make help` for the list.
.DEFAULT_GOAL := help
SWIFT ?= swift
BIN = $(shell $(SWIFT) build --show-bin-path)

.PHONY: help build test run cli app demo screenshots video format lint clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Debug build of all targets
	$(SWIFT) build

test: ## Run the test suite (sandboxed; never touches your home folder)
	$(SWIFT) test

run: build ## Launch the app from the build folder
	"$(BIN)/KitfoldApp"

cli: build ## Run the CLI, e.g. make cli ARGS="status"
	"$(BIN)/kitfold" $(ARGS)

app: ## Release build: build/Kitfold.app
	scripts/bundle.sh

demo: ## Build the fictional demo home, e.g. make demo DIR=/tmp/kf-demo
	scripts/demo/make-demo-home.sh $(or $(DIR),/tmp/kitfold-demo)

screenshots: ## Regenerate release screenshots
	scripts/screenshots/make.sh

video: ## Render the launch video and GIFs, e.g. make video MUSIC=~/music.mp3
	scripts/video/make.sh $(MUSIC)

format: ## Format sources in place with swift-format
	$(SWIFT) format --in-place --recursive Sources Tests Package.swift

lint: ## Check formatting without changing files
	$(SWIFT) format lint --recursive Sources Tests Package.swift

clean: ## Remove build products
	rm -rf .build build
