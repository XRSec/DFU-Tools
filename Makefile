# 使用固定的 DerivedData 路径，避免路径变化
PROJECT := DFU-Tools.xcodeproj
DERIVED_DATA_PATH := $(HOME)/Library/Developer/Xcode/DerivedData/DFU-Tools
APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/Release/DFU-Tools.app
VERSION := 1.2.0
DMG_NAME := DFU-Tools-$(VERSION).dmg
DMG_TEMP_DIR := /tmp/DFU-Tools-dmg

.PHONY: list build build-debug debug dmg

list:
	@xcodebuild -project $(PROJECT) -list

build:
	@xcodebuild -project $(PROJECT) -scheme "DFU-Tools" -configuration Release -arch arm64 -derivedDataPath $(DERIVED_DATA_PATH) CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO clean build

build-debug:
	@xcodebuild -project $(PROJECT) -scheme "DFU-Tools" -configuration Debug -arch arm64 -derivedDataPath $(DERIVED_DATA_PATH) CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO clean build

debug:
	@killall DFU-Tools 2>/dev/null || true
	@open $(APP_PATH)

dmg: build
	@echo "开始打包 DMG..."
	@rm -rf $(DMG_TEMP_DIR)
	@mkdir -p $(DMG_TEMP_DIR)
	@cp -R $(APP_PATH) $(DMG_TEMP_DIR)/
	@ln -s /Applications $(DMG_TEMP_DIR)/Applications
	@rm -f $(DMG_NAME)
	@hdiutil create -volname "DFU-Tools" -srcfolder $(DMG_TEMP_DIR) -ov -format UDZO $(DMG_NAME)
	@rm -rf $(DMG_TEMP_DIR)
	@echo "DMG 打包完成: $(DMG_NAME)"
dev:
	@make build
	@/Users/xr/Library/Developer/Xcode/DerivedData/DFU-Tools/Build/Products/Release/DFU-Tools.app/Contents/MacOS/DFU-Tools
