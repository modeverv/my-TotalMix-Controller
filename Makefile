.PHONY: build run test clean project icon
build:
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouch -configuration Release -derivedDataPath build build
run: build
	open build/Build/Products/Release/TotalMixSnapshotTouch.app
test:
	swift test
project:
	python3 scripts/generate-project.py
clean:
	swift package clean
	xcodebuild -project TotalMixSnapshotTouch.xcodeproj -scheme TotalMixSnapshotTouch -derivedDataPath build clean

icon:
	swift scripts/generate-icon.swift
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
