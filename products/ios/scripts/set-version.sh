#!/usr/bin/env bash
# Stamps the marketing version and build number into Config/Shared.xcconfig.
# Used by the ios-release workflow: set-version.sh <marketing-version> <build-number>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <marketing-version> <build-number>" >&2
  exit 2
fi

MARKETING="$1"
BUILD="$2"
XCCONFIG="$(dirname "$0")/../Config/Shared.xcconfig"

sed -i '' \
  -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${MARKETING}/" \
  -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD}/" \
  "$XCCONFIG"

grep -E "^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)" "$XCCONFIG"
