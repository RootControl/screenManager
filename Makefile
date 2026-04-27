.PHONY: build run clean

APP = ScreenManager.app
BINARY_NAME = ScreenManager
BUILD_DIR = .build/release

build:
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp $(BUILD_DIR)/$(BINARY_NAME) $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	codesign --force --deep --sign - $(APP)

run: build
	open $(APP)

clean:
	rm -rf .build $(APP)
