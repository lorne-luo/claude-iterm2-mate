APP_NAME := ClaudeItermMate
APP_BUNDLE := $(APP_NAME).app
# Local builds carry a dev version; real releases get their version from the
# git tag via `make release` (see scripts/release.sh).
VERSION ?= 0.0.0-dev

.PHONY: build run install uninstall clean test release

## Build the .app bundle into dist/ (ad-hoc signed).
build:
	./scripts/make-app.sh "$(VERSION)"

## Build and launch straight from dist/.
run: build
	open "dist/$(APP_BUNDLE)"

## Build and install to /Applications (quits any running instance first).
install: build
	-pkill -f "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	rm -rf "/Applications/$(APP_BUNDLE)"
	cp -R "dist/$(APP_BUNDLE)" /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE) (version $(VERSION))"

## Remove the installed app.
uninstall:
	-pkill -f "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	rm -rf "/Applications/$(APP_BUNDLE)"
	@echo "✅ Removed /Applications/$(APP_BUNDLE)"

## Remove build artifacts.
clean:
	swift package clean
	rm -rf dist

## Run the test suite.
test:
	swift test

## Tag a release; CI builds the dmg and publishes it. Usage: make release VERSION=1.2.0
release:
	./scripts/release.sh "$(VERSION)"
