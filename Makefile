VERSION := 1.0.0
BIN := sml-corners
APP := build/SML Corners.app
DEST := /Applications/SML Corners.app
ZIP := build/SML-Corners-$(VERSION).zip
ARCHS := --arch arm64 --arch x86_64

.PHONY: build bundle install uninstall dist release clean

# Universal binary: runs on Apple Silicon and Intel Macs.
build:
	swift build -c release $(ARCHS)

bundle: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c release $(ARCHS) --show-bin-path)/$(BIN)" "$(APP)/Contents/MacOS/$(BIN)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP)/Contents/Info.plist"
	bash scripts/sign.sh "$(APP)"

install: bundle
	-pkill -x $(BIN)
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	open "$(DEST)"

uninstall:
	-pkill -x $(BIN)
	rm -rf "$(DEST)"

# Zip for GitHub Releases and Homebrew.
dist: bundle
	rm -f "$(ZIP)"
	cd build && ditto -c -k --keepParent "SML Corners.app" "SML-Corners-$(VERSION).zip"
	@shasum -a 256 "$(ZIP)"

# Publishes the zip as a GitHub release and updates the Homebrew cask.
release: dist
	bash scripts/release.sh $(VERSION) "$(ZIP)"

clean:
	rm -rf .build build
