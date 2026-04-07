# ---------------------------
# 常量配置
# ---------------------------
SIGN_IDENTITY := "Apple Development"

# ---------------------------
# 路径配置
# ---------------------------
PROJECT := DFU-Tools.xcodeproj
DERIVED_DATA_PATH := $(HOME)/Library/Developer/Xcode/DerivedData/DFU-Tools
APP_PATH := $(DERIVED_DATA_PATH)/Build/Products/Release/DFU-Tools.app
APP_DEBUG_PATH := $(DERIVED_DATA_PATH)/Build/Products/Debug/DFU-Tools.app
DMG_TEMP_DIR := /tmp/DFU-Tools-dmg

# ---------------------------
# 输出文件名
# ---------------------------
VERSION := 1.2.0
DMG_EN_NAME := DFU-Tools-EN-$(VERSION).dmg
DMG_ZH_NAME := DFU-Tools-ZH-$(VERSION).dmg

# ---------------------------
# 声明伪目标
# ---------------------------
.PHONY: list build build-debug debug sign dmg dmg-en dmg-zh dev push

# ---------------------------
# 列出 Xcode 工程
# ---------------------------
list:
	@xcodebuild -project $(PROJECT) -list

# ---------------------------
# 编译应用
# ---------------------------
build:
	@xcodebuild -project $(PROJECT) -scheme "DFU-Tools" \
	-configuration Release -arch arm64 \
	-derivedDataPath $(DERIVED_DATA_PATH) \
	clean build

build-debug:
	@xcodebuild -project $(PROJECT) -scheme "DFU-Tools" \
	-configuration Debug -arch arm64 \
	-derivedDataPath $(DERIVED_DATA_PATH) \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO clean build

# ---------------------------
# 调试应用
# ---------------------------
debug:
	@killall DFU-Tools 2>/dev/null || true
	@open "$(APP_PATH)"

# ---------------------------
# 签名应用
# ---------------------------
sign:
	@echo "开始签名应用..."
	@codesign --force --sign $(SIGN_IDENTITY) "$(APP_PATH)/Contents/Resources/DFUToolsHelper"
	@codesign --force --sign $(SIGN_IDENTITY) "./dmg-assets/打不开修复"
	@codesign --force --deep --sign $(SIGN_IDENTITY) "$(APP_PATH)"
	@echo "签名完成"

# ---------------------------
# 打包 DMG
# ---------------------------
dmg: build sign
	@echo "开始打包 DMG..."
	@rm -rf $(DMG_TEMP_DIR)
	@mkdir -p $(DMG_TEMP_DIR)
	@cp -R "$(APP_PATH)" $(DMG_TEMP_DIR)/
	@cp -R "dmg-assets/.background" $(DMG_TEMP_DIR)/
	@cp "dmg-assets/.VolumeIcon.icns" $(DMG_TEMP_DIR)/
	@cp "dmg-assets/打不开修复" $(DMG_TEMP_DIR)/
	@cp "dmg-assets/安装说明.rtf" $(DMG_TEMP_DIR)/

	@rm -f $(DMG_ZH_NAME)
	@create-dmg \
		--volname "DFU工具" \
		--volicon "$(DMG_TEMP_DIR)/.VolumeIcon.icns" \
		--window-size 540 410 \
		--icon-size 64 \
		--background "$(DMG_TEMP_DIR)/.background/background.tiff" \
		--app-drop-link 407 100 \
		--icon "DFU-Tools.app" 135 100 \
		--icon "打不开修复" 135 250 \
		--icon "安装说明.rtf" 407 250 \
		$(DMG_ZH_NAME) \
		$(DMG_TEMP_DIR)
	@echo "中文 DMG 打包完成"

	@rm -rf $(DMG_TEMP_DIR)
	@mkdir -p $(DMG_TEMP_DIR)
	@cp -R "$(APP_PATH)" $(DMG_TEMP_DIR)/
	@cp -R "dmg-assets/.background" $(DMG_TEMP_DIR)/
	@cp "dmg-assets/.VolumeIcon.icns" $(DMG_TEMP_DIR)/
	@cp "dmg-assets/Fix Cannot Open" $(DMG_TEMP_DIR)/
	@cp "dmg-assets/Installation Instructions.rtf" $(DMG_TEMP_DIR)/

	@rm -f $(DMG_EN_NAME)
	@create-dmg \
		--volname "DFU Tools" \
		--volicon "$(DMG_TEMP_DIR)/.VolumeIcon.icns" \
		--window-size 540 410 \
		--icon-size 64 \
		--background "$(DMG_TEMP_DIR)/.background/background.tiff" \
		--app-drop-link 407 100 \
		--icon "DFU-Tools.app" 135 100 \
		--icon "Fix Cannot Open" 135 250 \
		--icon "Installation Instructions.rtf" 407 250 \
		$(DMG_EN_NAME) \
		$(DMG_TEMP_DIR)
	@echo "英文 DMG 打包完成"

	@rm -rf $(DMG_TEMP_DIR)
	@echo "DMG 打包全部完成"

# ---------------------------
# 开发一键运行
# ---------------------------
dev: build-debug
	@$(APP_DEBUG_PATH)/Contents/MacOS/DFU-Tools

# ---------------------------
# 推送到远程仓库
# ---------------------------
push:
	git push git@github.com:XRSec/DFU-Tools.git main:main
	git push
