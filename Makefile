APP_NAME    = QuotaX
SCHEME      = QuotaX
CONFIG      = Release
BUILD_DIR   = build
VERSION     = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" QuotaX/Info.plist)
DMG_NAME    = $(APP_NAME)-$(VERSION).dmg
DMG_VOLUME  = $(APP_NAME) $(VERSION)
APP_PATH    = $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app

.PHONY: all clean build dmg generate dmg-arm64 dmg-x86_64 dmg-all

all: dmg

# 通过 XcodeGen 生成 Xcode 项目
generate:
	xcodegen generate

# 编译 Universal (x86_64 + arm64) Release 版本
build: generate
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=NO \
		build

# 编译指定架构的 Release 版本
build-arm64: generate
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR)/arm64 \
		ARCHS="arm64" \
		ONLY_ACTIVE_ARCH=NO \
		build

build-x86_64: generate
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR)/x86_64 \
		ARCHS="x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		build

# 打包 Universal DMG
dmg: build
	@echo "==> 创建 Universal DMG..."
	@rm -rf $(BUILD_DIR)/dmg $(BUILD_DIR)/$(DMG_NAME)
	@mkdir -p $(BUILD_DIR)/dmg
	@cp -R "$(APP_PATH)" $(BUILD_DIR)/dmg/
	@ln -s /Applications $(BUILD_DIR)/dmg/Applications
	@hdiutil makehybrid -o $(BUILD_DIR)/$(APP_NAME)-temp.iso $(BUILD_DIR)/dmg/ > /dev/null 2>&1
	@hdiutil convert -format UDZO -ov -o $(BUILD_DIR)/$(DMG_NAME) $(BUILD_DIR)/$(APP_NAME)-temp.iso > /dev/null 2>&1
	@rm -f $(BUILD_DIR)/$(APP_NAME)-temp.iso && rm -rf $(BUILD_DIR)/dmg
	@echo "==> 完成: $(BUILD_DIR)/$(DMG_NAME)"

# 打包指定架构 DMG（内部辅助）
define make_dmg_arch
	@echo "==> 创建 $(1) DMG..."
	@rm -rf $(BUILD_DIR)/dmg-$(1) $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-$(1).dmg
	@mkdir -p $(BUILD_DIR)/dmg-$(1)
	@cp -R "$(BUILD_DIR)/$(1)/Build/Products/$(CONFIG)/$(APP_NAME).app" $(BUILD_DIR)/dmg-$(1)/
	@ln -s /Applications $(BUILD_DIR)/dmg-$(1)/Applications
	@hdiutil makehybrid -o $(BUILD_DIR)/$(APP_NAME)-temp-$(1).iso $(BUILD_DIR)/dmg-$(1)/ > /dev/null 2>&1
	@hdiutil convert -format UDZO -ov -o $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-$(1).dmg $(BUILD_DIR)/$(APP_NAME)-temp-$(1).iso > /dev/null 2>&1
	@rm -f $(BUILD_DIR)/$(APP_NAME)-temp-$(1).iso && rm -rf $(BUILD_DIR)/dmg-$(1)
	@echo "==> 完成: $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-$(1).dmg"
endef

dmg-arm64: build-arm64
	$(call make_dmg_arch,arm64)

dmg-x86_64: build-x86_64
	$(call make_dmg_arch,x86_64)

dmg-all: dmg dmg-arm64 dmg-x86_64

clean:
	@rm -rf $(BUILD_DIR)
	@echo "==> 已清理"
