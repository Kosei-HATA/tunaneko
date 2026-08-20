APP_NAME := tunaneko
VERSION := 0.1.0

.PHONY: core build dist release run clean

core:
	Scripts/build_core.sh

build:
	swift build -c release

dist: core build
	Scripts/bundle_app.sh

release: dist
	Scripts/package_release.sh $(VERSION)

run: dist
	open dist/$(APP_NAME).app

clean:
	rm -rf .build dist build
