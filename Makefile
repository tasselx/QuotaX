APP_NAME    = QuotaX
SCHEME      = QuotaX
CONFIG      = Release
BUILD_DIR   = build
VERSION     = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" QuotaX/Info.plist)
DMG_NAME    = $(APP_NAME)-$(VERSION).dmg
DMG_VOLUME  = $(APP_NAME) $(VERSION)
APP_PATH    = $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app

.PHONY: all clean build dmg generate

all: dmg

# 通过 XcodeGen 生成 Xcode 项目
generate:
	xcodegen generate

# 编译 Release 版本
build: generate
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=NO \
		build

# 打包 DMG（含应用程序快捷方式）
dmg: build
	@echo "==> 创建 DMG..."
	@rm -rf $(BUILD_DIR)/dmg $(BUILD_DIR)/$(DMG_NAME)
	@mkdir -p $(BUILD_DIR)/dmg
	@cp -R "$(APP_PATH)" $(BUILD_DIR)/dmg/
	@ln -s /Applications $(BUILD_DIR)/dmg/Applications
	@hdiutil makehybrid -o $(BUILD_DIR)/$(APP_NAME)-temp.iso $(BUILD_DIR)/dmg/ > /dev/null 2>&1
	@hdiutil convert -format UDZO -ov -o $(BUILD_DIR)/$(DMG_NAME) $(BUILD_DIR)/$(APP_NAME)-temp.iso > /dev/null 2>&1
	@rm -f $(BUILD_DIR)/$(APP_NAME)-temp.iso && rm -rf $(BUILD_DIR)/dmg
	@echo "==> 完成: $(BUILD_DIR)/$(DMG_NAME)"

clean:
	@rm -rf $(BUILD_DIR)
	@echo "==> 已清理"
