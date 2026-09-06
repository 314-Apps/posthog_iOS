SCHEME := PostHog
PROJECT := PostHog.xcodeproj
DESTINATION := platform=iOS Simulator,name=iPhone 17
DERIVED := .build/DerivedData
SPM_CLONES := .spm-packages

.PHONY: generate build test lint format snapshot-record api-lock check-api check-player player clean

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
	TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM_CLONES) \
		-only-testing DesignSystemSnapshotTests -quiet || true

api-lock:
	python3 scripts/update-api-lock.py

check-api:
	python3 scripts/check-api-drift.py

check-player:
	python3 scripts/check-player-freshness.py

clean:
	rm -rf $(PROJECT) $(DERIVED) $(SPM_CLONES)

# Rebuilds the replay player and installs it into the app bundle. Needs npm.
# The artifact is committed because iOS CI checks out only this tree. The build writes
# the bundled copy itself, so there is no window in which the two can disagree.
player:
	cd player && npm install --silent && npm run build
	python3 scripts/check-player-freshness.py --write
