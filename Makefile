.PHONY: build run test clean project icon ios-build ios-device ios-test

# Override for another installed simulator, e.g. make ios-test IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17'
IOS_TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro

build:
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouch -configuration Release -derivedDataPath build build
run: build
	open build/Build/Products/Release/TotalMixSnapshotTouch.app
test:
	swift test
project:
	python3 scripts/generate-project.py

ios-build: project
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouchIOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build

ios-device: project
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouchIOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/ios-device CODE_SIGNING_ALLOWED=NO build

ios-test: project
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouchIOS -configuration Debug -destination '$(IOS_TEST_DESTINATION)' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO test

clean:
	swift package clean
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouch -derivedDataPath build clean

icon:
	swift scripts/generate-icon.swift
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
