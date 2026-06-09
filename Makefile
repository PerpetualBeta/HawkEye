# HawkEye — magnifier callout utility.
#
# Menu-bar app. Hotkey captures the active display (or user loads an
# image), and the editor window lets the user draw a source rectangle
# and reposition/resize a magnified callout that's tied to the source
# by a high-contrast arrow. Save flattens the result to PNG.

# Project identity
BUNDLE_NAME      := HawkEye
BUNDLE_TYPE      := app
PRODUCT_NAME     := HawkEye.app
BUNDLE_ID        := cc.jorviksoftware.HawkEye
BUILD_SYSTEM     := swiftc

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true

SWIFT_FRAMEWORKS := Cocoa CoreGraphics ScreenCaptureKit Carbon ServiceManagement UniformTypeIdentifiers
SWIFT_SOURCES    := App/main.swift App/AppDelegate.swift \
                    App/StatusItem.swift \
                    App/HotkeyManager.swift App/HotkeyRecorder.swift \
                    App/CaptureCoordinator.swift \
                    App/Screenshot.swift App/ImageLoader.swift App/ImageSaver.swift \
                    App/EditorWindow.swift App/EditorCanvas.swift App/CalloutGeometry.swift \
                    App/HUDWindow.swift \
                    App/HawkEyeSettings.swift App/SparkleDelegate.swift \
                    App/Log.swift \
                    $(wildcard App/JorvikKit/*.swift)

EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS        := HawkEye.entitlements

# Stable signing identity for dev — same identity production uses;
# ad-hoc (`-`) breaks TCC grants and Sparkle's hardened-runtime
# requirements for its XPC services.
DEV_SIGN_IDENTITY := Developer ID Application: Jonthan Hollin (EG86BCGUE7)

# Release.mk lives in a sibling repo (PerpetualBeta/jorvik-release).
# It owns stamping, notarisation, and appcast generation, and processes
# EMBEDDED_FRAMEWORKS for proper Sparkle embedding/signing.
include ../jorvik-release/release.mk

.DEFAULT_GOAL := dev-build

.PHONY: dev-build run icon

# Dev iteration targets

dev-build:
	@echo "→ dev build (arm64, signed Developer ID, Sparkle embedded)"
	@rm -rf "$(PRODUCT_NAME)"
	@mkdir -p "$(PRODUCT_NAME)/Contents/MacOS" "$(PRODUCT_NAME)/Contents/Resources" "$(PRODUCT_NAME)/Contents/Frameworks"
	swiftc -O -target arm64-apple-macos14.0 -sdk $(SDK) \
		$(addprefix -framework ,$(SWIFT_FRAMEWORKS)) \
		-F . \
		-Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
		-module-name $(BUNDLE_NAME) \
		-o "$(PRODUCT_NAME)/Contents/MacOS/$(BUNDLE_NAME)" \
		$(SWIFT_SOURCES)
	cp Info.plist "$(PRODUCT_NAME)/Contents/Info.plist"
	@echo "→ Copying Resources/ contents..."
	@cp -R Resources/* "$(PRODUCT_NAME)/Contents/Resources/" 2>/dev/null || echo "  (Resources/ is empty — run 'make icon' to generate AppIcon.icns)"
	@echo "→ Embedding Sparkle.framework..."
	@cp -R Sparkle.framework "$(PRODUCT_NAME)/Contents/Frameworks/"
	@echo "→ Signing framework leaves-first..."
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework" 2>&1 | tail -1
	@echo "→ Signing app bundle (entitlements + hardened runtime)..."
	codesign --force --options runtime --timestamp \
		--entitlements "$(ENTITLEMENTS)" \
		--sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)"
	@echo "→ Done: $(PRODUCT_NAME) (signed: $(DEV_SIGN_IDENTITY))"

run: dev-build
	pkill -f "/$(PRODUCT_NAME)/" 2>/dev/null || true
	open "$(PRODUCT_NAME)"

icon:
	@echo "→ Generating icon..."
	swift generate_icon.swift
