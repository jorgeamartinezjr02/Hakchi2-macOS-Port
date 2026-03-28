APP_NAME = Hakchi
BUNDLE_ID = com.hakchi-gui.macos
VERSION = 1.0.0
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: all build app dmg clean install run

all: app

build:
	swift build -c release

app: build
	@echo "Creating $(APP_NAME).app bundle..."
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp Info.plist "$(APP_BUNDLE)/Contents/"
	@cp "$(BUILD_DIR)/release/Hakchi" "$(APP_BUNDLE)/Contents/MacOS/Hakchi"
	@cp Resources/game_db.json "$(APP_BUNDLE)/Contents/Resources/"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources/boot"
	@cp Resources/boot/boot.img "$(APP_BUNDLE)/Contents/Resources/boot/" 2>/dev/null || true
	@cp Resources/boot/uboot.bin "$(APP_BUNDLE)/Contents/Resources/boot/" 2>/dev/null || true
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@echo "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	@echo "✅ $(APP_NAME).app created at $(APP_BUNDLE)"
	@echo "   Drag it to /Applications to install."

dmg: app
	@echo "Creating DMG installer..."
	@hdiutil create -volname "$(APP_NAME)" \
		-srcfolder "$(APP_BUNDLE)" \
		-ov -format UDZO \
		"$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"
	@echo "✅ DMG created at $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"

install: app
	@echo "Installing to /Applications..."
	@cp -R "$(APP_BUNDLE)" /Applications/
	@echo "✅ $(APP_NAME).app installed to /Applications"

run: app
	@open "$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
	rm -f "$(BUILD_DIR)/$(APP_NAME)-*.dmg"
