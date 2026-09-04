SCHEME := PostHog
PROJECT := PostHog.xcodeproj
DESTINATION := platform=iOS Simulator,name=iPhone 17
DERIVED := .build/DerivedData
SPM_CLONES := .spm-packages

.PHONY: generate build test lint format snapshot-record api-lock check-api clean

generate:
	xcodegen generate --spec project.yml --project .

build: generate
	xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM_CLONES) \
		-quiet

test: generate
	xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM_CLONES) \
		-quiet

lint:
	swiftlint lint --strict
	swift format lint --strict --recursive Packages App/Sources UITests

format:
	swift format format --in-place --recursive Packages App/Sources UITests

snapshot-record: generate
	SNAPSHOT_RECORD=1 xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM_CLONES) \
		-only-testing PostHogKitTests/DesignSystemSnapshotTests -quiet || true

api-lock:
	python3 scripts/update-api-lock.py

check-api:
	python3 scripts/check-api-drift.py

clean:
	rm -rf $(PROJECT) $(DERIVED) $(SPM_CLONES)
