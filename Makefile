.PHONY: build debug release sign app run-app test verify format-check benchmark-inventory homebrew-stage clean

PREFIX ?= $(CURDIR)/dist/homebrew

build: debug

debug:
	swift build

release:
	swift build -c release

sign: debug
	codesign --force --sign - --entitlements Resources/lunchpail.entitlements .build/debug/lunchpail

app:
	./script/build_and_run.sh --build-only

run-app:
	./script/build_and_run.sh

test:
	swift test

verify: test
	Scripts/verify-metal-artifacts.sh

format-check:
	swift format lint --recursive --strict Package.swift Sources Tests Guest

benchmark-inventory: release
	python3 Scripts/benchmark-inventory.py --lunchpail .build/release/lunchpail

homebrew-stage:
	Scripts/stage-homebrew-install.sh "$(PREFIX)"

clean:
	swift package clean
