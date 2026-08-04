#!/bin/bash
# Automated, headless subset of the M8-02 beta matrix. Real IME composition
# and VoiceOver navigation remain manual because synthetic key events cannot
# establish those system integrations.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift test --filter 'EncodingDetectorTests|TextEncodingTests|TextFileLoaderTests|TextFileSaverTests|LineEndingDetectorTests|ExternalChangeDetectorTests|DocumentControllerTests|GrepServiceTests|MacroPermissionStoreTests|CJKIMETests|FindBarViewTests|GrepUITests|StatusBarViewTests'
