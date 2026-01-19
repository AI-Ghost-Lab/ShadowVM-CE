# ShadowVM-CE Makefile

.PHONY: help ShadowVM-CE ShadowVM-CE-release ShadowVM-CE-release-build ShadowVM-CE-release-sign ShadowVM-CE-release-dmg ShadowVM-CE-release-notarize clean

.DEFAULT_GOAL := help

# Release version parsing for `make ShadowVM-CE-release <version>`
ifneq ($(filter ShadowVM-CE-release ShadowVM-CE-release-build ShadowVM-CE-release-dmg ShadowVM-CE-release-notarize,$(MAKECMDGOALS)),)
CE_RELEASE_VERSION := $(word 2,$(MAKECMDGOALS))
ifneq ($(strip $(CE_RELEASE_VERSION)),)
$(eval $(CE_RELEASE_VERSION):;@:)
endif
endif

CE_ROOT := $(shell pwd)
OUTPUT_DIR ?= $(CE_ROOT)/output
SWIFT_BUILD_CONFIG ?= debug
SWIFT_BUILD_CONFIG_LOWER := $(if $(filter release Release,$(SWIFT_BUILD_CONFIG)),release,debug)
SHADOWVMCE_XCODEPROJ := $(CE_ROOT)/src/ShadowVM-CE.xcodeproj
SHADOWVMCE_SCHEME := ShadowVM
SHADOWVMCE_CONFIGURATION ?= $(if $(filter release,$(SWIFT_BUILD_CONFIG_LOWER)),Release,Debug)
SHADOWVMCE_OUTPUT_DIR := $(OUTPUT_DIR)/ShadowVM-CE
SHADOWVMCE_DERIVED_DATA := $(SHADOWVMCE_OUTPUT_DIR)/DerivedData
SHADOWVMCE_SPM_DIR := $(SHADOWVMCE_OUTPUT_DIR)/SourcePackages
SHADOWVMCE_APP := $(SHADOWVMCE_OUTPUT_DIR)/ShadowVM-CE.app
OUTPUT_BIN_DIR := $(OUTPUT_DIR)/bin/$(SWIFT_BUILD_CONFIG_LOWER)
RELEASE_SCRIPT := $(CE_ROOT)/scripts/releaseShadowVMCE
SHADOWVMCORE_INTERFACE := $(CE_ROOT)/3rd_party/ShadowVMCore.swiftinterface

## help: Show this help message
help:
	@echo "ShadowVM-CE Makefile"
	@echo ""
	@echo "Usage: make <target> [VAR=value ...]"
	@echo ""
	@echo "Build targets:"
	@echo "  ShadowVM-CE    Build ShadowVM-CE app (SWIFT_BUILD_CONFIG)"
	@echo "  ShadowVM-CE-release <version>  Build signed+notarized ShadowVM-CE dmg (uses .env)"
	@echo "  ShadowVM-CE-release-build <version>     Build ShadowVM-CE app + inject agent img"
	@echo "  ShadowVM-CE-release-sign               Codesign ShadowVM-CE app"
	@echo "  ShadowVM-CE-release-dmg <version>       Package ShadowVM-CE dmg"
	@echo "  ShadowVM-CE-release-notarize <version>  Notarize/staple ShadowVM-CE dmg"
	@echo "  clean           Clean build artifacts (output build dirs)"
	@echo ""
	@echo "Build variables:"
	@echo "  SWIFT_BUILD_CONFIG=<debug|release>  Build config (default: debug)"
	@echo "  OUTPUT_DIR=<path>                   Build output root (default: ./output)"
	@echo "  CE_VERSION=<x.y.z>                  ShadowVM-CE release version"
	@echo "  CE_AGENT_IMG=<path>                 Override ShadowVMAgent img path for release builds"

## ShadowVM-CE: Build ShadowVM-CE (SWIFT_BUILD_CONFIG)
ShadowVM-CE:
	@mkdir -p $(SHADOWVMCE_OUTPUT_DIR)
	@if [ -f "$(SHADOWVMCORE_INTERFACE)" ]; then \
		perl -pi -e 's/IOSurface\.IOSurface/IOSurface/g' "$(SHADOWVMCORE_INTERFACE)"; \
	fi
	@rm -rf $(SHADOWVMCE_DERIVED_DATA)
	xcodebuild -project $(SHADOWVMCE_XCODEPROJ) -scheme $(SHADOWVMCE_SCHEME) -configuration $(SHADOWVMCE_CONFIGURATION) CONFIGURATION_BUILD_DIR=$(SHADOWVMCE_OUTPUT_DIR) -derivedDataPath $(SHADOWVMCE_DERIVED_DATA) -clonedSourcePackagesDirPath $(SHADOWVMCE_SPM_DIR) build
	@mkdir -p $(OUTPUT_BIN_DIR)
	@rm -rf $(OUTPUT_BIN_DIR)/ShadowVM-CE.app
	@cp -R $(SHADOWVMCE_APP) $(OUTPUT_BIN_DIR)/ShadowVM-CE.app

## ShadowVM-CE-release: Build, sign, notarize, and package ShadowVM-CE into DMG
ShadowVM-CE-release: ShadowVM-CE-release-build ShadowVM-CE-release-sign ShadowVM-CE-release-dmg ShadowVM-CE-release-notarize

## ShadowVM-CE-release-build: Build ShadowVM-CE app and inject agent image
ShadowVM-CE-release-build:
	@CE_VERSION=$(if $(strip $(CE_RELEASE_VERSION)),$(strip $(CE_RELEASE_VERSION)),$(strip $(CE_VERSION))) CE_OUTPUT_ROOT=$(OUTPUT_DIR) CE_STEP=build bash $(RELEASE_SCRIPT)

## ShadowVM-CE-release-sign: Codesign ShadowVM-CE app
ShadowVM-CE-release-sign:
	@CE_OUTPUT_ROOT=$(OUTPUT_DIR) CE_STEP=sign bash $(RELEASE_SCRIPT)

## ShadowVM-CE-release-dmg: Package ShadowVM-CE dmg
ShadowVM-CE-release-dmg:
	@CE_VERSION=$(if $(strip $(CE_RELEASE_VERSION)),$(strip $(CE_RELEASE_VERSION)),$(strip $(CE_VERSION))) CE_OUTPUT_ROOT=$(OUTPUT_DIR) CE_STEP=dmg bash $(RELEASE_SCRIPT)

## ShadowVM-CE-release-notarize: Notarize/staple ShadowVM-CE dmg
ShadowVM-CE-release-notarize:
	@CE_VERSION=$(if $(strip $(CE_RELEASE_VERSION)),$(strip $(CE_RELEASE_VERSION)),$(strip $(CE_VERSION))) CE_OUTPUT_ROOT=$(OUTPUT_DIR) CE_STEP=notarize bash $(RELEASE_SCRIPT)

## clean: Clean build artifacts
clean:
	@rm -rf $(OUTPUT_DIR)/ShadowVM-CE $(OUTPUT_DIR)/bin
