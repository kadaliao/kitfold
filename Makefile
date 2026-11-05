# Kitfold developer tasks. Run `make help` for the list.
.DEFAULT_GOAL := help
SWIFT ?= swift
BIN = $(shell $(SWIFT) build --show-bin-path)

.PHONY: help build test run cli app release demo screenshots tutorial-shots video format lint clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

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

release: ## Signed, notarized DMG in build/release, e.g. make release NOTARY_PROFILE=notary
	NOTARY_PROFILE="$(NOTARY_PROFILE)" scripts/release.sh

demo: ## Build the fictional demo home, e.g. make demo DIR=/tmp/kf-demo
	scripts/demo/make-demo-home.sh $(or $(DIR),/tmp/kitfold-demo)

screenshots: ## Regenerate release screenshots
	scripts/screenshots/make.sh

tutorial-shots: ## Regenerate the tutorials' screenshots (English and Chinese)
	scripts/tutorials/make.sh

video: ## Render the launch video and GIFs, e.g. make video VARIANTS="en zh zh-portrait" MUSIC=~/music.mp3
	MUSIC="$(MUSIC)" scripts/video/make.sh $(VARIANTS)

format: ## Format sources in place with swift-format
	$(SWIFT) format --in-place --recursive Sources Tests Package.swift

lint: ## Check formatting without changing files
	$(SWIFT) format lint --recursive Sources Tests Package.swift

clean: ## Remove build products
	rm -rf .build build
