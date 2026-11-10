BIN := sml-corners
APP := build/SML Corners.app
DEST := /Applications/SML Corners.app

.PHONY: build bundle install uninstall clean

build:
	swift build -c release

bundle: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp .build/release/$(BIN) "$(APP)/Contents/MacOS/$(BIN)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	bash scripts/sign.sh "$(APP)"

install: bundle
	-pkill -x $(BIN)
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	open "$(DEST)"

uninstall:
	-pkill -x $(BIN)
	rm -rf "$(DEST)"

clean:
	rm -rf .build build
