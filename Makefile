.PHONY: build run clean test

APP = ScreenManager.app
BINARY_NAME = ScreenManager
BUILD_DIR = .build/release
CORE = Sources/ScreenManagerCore
HEADER = $(CORE)/include/BridgingHeader.h
FRAMEWORKS = -framework AppKit -framework Carbon -framework ApplicationServices -framework ServiceManagement

build:
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@if swift build -c release; then \
		cp $(BUILD_DIR)/$(BINARY_NAME) $(APP)/Contents/MacOS/; \
	else \
		echo "SwiftPM unavailable — compiling with swiftc directly."; \
		mkdir -p .build/swiftc; \
		printf 'ScreenManagerApp.main()\n' > .build/swiftc/main.swift; \
		swiftc -O -target arm64-apple-macosx13.0 \
			-import-objc-header $(HEADER) $(FRAMEWORKS) \
			-o $(APP)/Contents/MacOS/$(BINARY_NAME) \
			$(CORE)/*.swift .build/swiftc/main.swift; \
	fi
	cp Info.plist $(APP)/Contents/
	codesign --force --deep --sign - $(APP)

run: build
	open $(APP)

test:
	swift test

clean:
	rm -rf .build $(APP)
