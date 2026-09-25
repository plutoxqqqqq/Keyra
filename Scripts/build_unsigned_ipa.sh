#!/usr/bin/env bash
#
# Build Keyra for a real iPhone and package an unsigned .ipa.
#
# Why unsigned: SideStore installs an IPA by signing it on the device with your
# own Apple ID. An unsigned IPA is therefore the correct, honest artefact — no
# certificate, profile or team identifier is required, and nothing in this
# repository pretends the binary is already signed.
#
# The app is built with the entitlements files still referenced in the project,
# so SideStore can sign it *with* the App Group entitlement (enable "App Groups"
# for Keyra in SideStore) and the keyboard extension will then share the layout
# file with the host app.
#
# Requirements: macOS with Xcode (the GitHub Actions runner provides both).
#
# Environment overrides:
#   KEYRA_CONFIGURATION   Debug | Release            (default Release)
#   KEYRA_DERIVED_DATA    derived data directory     (default build/DerivedData)
#   KEYRA_OUTPUT_DIR      artefact directory         (default build/Artifacts)
#   KEYRA_MARKETING_VERSION / KEYRA_BUILD_NUMBER     (optional version stamp)
#   KEYRA_SKIP_TESTS      set to 1 to skip `swift test`
#   KEYRA_SKIP_VALIDATION set to 1 to skip Scripts/validate_ipa.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

mkdir -p "${REPO_ROOT}/build"

CONFIGURATION="${KEYRA_CONFIGURATION:-Release}"
DERIVED_DATA="${KEYRA_DERIVED_DATA:-${REPO_ROOT}/build/DerivedData}"
OUTPUT_DIR="${KEYRA_OUTPUT_DIR:-${REPO_ROOT}/build/Artifacts}"
PROJECT="${REPO_ROOT}/CustomKeyboard.xcodeproj"
SCHEME="CustomKeyboard"
APP_NAME="CustomKeyboard.app"
EXT_NAME="CustomKeyboardKeyboard.appex"
IPA_NAME="CustomKeyboard.ipa"

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning: %s\033[0m\n' "$*" >&2; }
fail() { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Platform checks
# ---------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  fail "this script builds a real iOS app and must run on macOS with Xcode.
       On Windows, push the repository to GitHub and run the 'Build Keyra IPA'
       workflow (.github/workflows/build-ios.yml), which does exactly this
       script on a macOS runner and uploads CustomKeyboard.ipa as an artifact."
fi

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild was not found. Install Xcode and run: xcode-select --install"

log "Toolchain"
xcode-select -p || true
xcodebuild -version
echo "--- available iOS SDKs ---"
xcodebuild -showsdks 2>/dev/null | grep -i -E 'ios|iphoneos' || warn "no iOS SDK was listed by xcodebuild -showsdks"

SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 'unknown')"
echo "iphoneos SDK version: ${SDK_VERSION}"
if [ "${SDK_VERSION}" = "unknown" ]; then
  fail "the iphoneos SDK is missing; this runner cannot build a device app."
fi

# ---------------------------------------------------------------------------
# 1. Regenerate and validate the project
# ---------------------------------------------------------------------------
log "Regenerating the Xcode project"
PYTHON_BIN="$(command -v python3 || command -v python || true)"
if [ -n "${PYTHON_BIN}" ]; then
  "${PYTHON_BIN}" Scripts/generate_xcodeproj.py
  "${PYTHON_BIN}" Scripts/validate_project.py
  "${PYTHON_BIN}" Scripts/check_swift_safety.py
else
  warn "python3 is unavailable, skipping the project generator and validators"
fi

[ -d "${PROJECT}" ] || fail "missing ${PROJECT}"

# ---------------------------------------------------------------------------
# 2. Unit tests for the shared engine (pure Foundation, no simulator needed)
# ---------------------------------------------------------------------------
if [ "${KEYRA_SKIP_TESTS:-0}" != "1" ]; then
  log "Running the shared model / engine tests"
  if command -v swift >/dev/null 2>&1; then
    swift test --package-path "${REPO_ROOT}" 2>&1 | tee "${REPO_ROOT}/build/swift-test.log" || {
      warn "swift test failed — see build/swift-test.log"
      exit 1
    }
  else
    warn "the swift command is unavailable, skipping the SwiftPM tests"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Build for a physical iPhone
# ---------------------------------------------------------------------------
mkdir -p "${DERIVED_DATA}" "${OUTPUT_DIR}/Payload"
BUILD_LOG="${OUTPUT_DIR}/xcodebuild.log"

VERSION_ARGS=()
if [ -n "${KEYRA_MARKETING_VERSION:-}" ]; then
  VERSION_ARGS+=("MARKETING_VERSION=${KEYRA_MARKETING_VERSION}")
fi
if [ -n "${KEYRA_BUILD_NUMBER:-}" ]; then
  VERSION_ARGS+=("CURRENT_PROJECT_VERSION=${KEYRA_BUILD_NUMBER}")
fi

log "Building ${SCHEME} (${CONFIGURATION}) for a device"
set +e
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_STYLE=Manual \
  ${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"} \
  build 2>&1 | tee "${BUILD_LOG}"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "${BUILD_STATUS}" -ne 0 ]; then
  echo ""
  echo "----- last 120 lines of the build log -----"
  tail -n 120 "${BUILD_LOG}" || true
  fail "xcodebuild failed with status ${BUILD_STATUS} (full log: ${BUILD_LOG})"
fi

PRODUCTS_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos"
APP_PATH="${PRODUCTS_DIR}/${APP_NAME}"
EXT_PATH="${APP_PATH}/PlugIns/${EXT_NAME}"

log "Checking the built products"
[ -d "${APP_PATH}" ] || fail "the host app was not produced at ${APP_PATH}"
[ -d "${EXT_PATH}" ] || fail "the keyboard extension is NOT embedded at ${EXT_PATH}"
[ -f "${APP_PATH}/CustomKeyboard" ] || fail "the host app executable is missing"
[ -f "${EXT_PATH}/CustomKeyboardKeyboard" ] || fail "the keyboard extension executable is missing"

echo "--- architectures ---"
HOST_ARCHS="$(xcrun lipo -archs "${APP_PATH}/CustomKeyboard")"
EXT_ARCHS="$(xcrun lipo -archs "${EXT_PATH}/CustomKeyboardKeyboard")"
echo "host app          : ${HOST_ARCHS}"
echo "keyboard extension: ${EXT_ARCHS}"

case "${HOST_ARCHS}" in
  *arm64*) ;;
  *) fail "the host app is not arm64 (found: ${HOST_ARCHS}); a simulator build must never be shipped as an IPA" ;;
esac
case "${HOST_ARCHS}" in
  *x86_64*|*i386*) fail "the host app contains a simulator slice (${HOST_ARCHS})" ;;
esac
case "${EXT_ARCHS}" in
  *arm64*) ;;
  *) fail "the keyboard extension is not arm64 (found: ${EXT_ARCHS})" ;;
esac

# ---------------------------------------------------------------------------
# 4. Package the IPA
# ---------------------------------------------------------------------------
log "Packaging ${IPA_NAME}"
rm -rf "${OUTPUT_DIR}/Payload"
mkdir -p "${OUTPUT_DIR}/Payload"
cp -R "${APP_PATH}" "${OUTPUT_DIR}/Payload/"

rm -f "${OUTPUT_DIR}/${IPA_NAME}"
if command -v ditto >/dev/null 2>&1; then
  (cd "${OUTPUT_DIR}" && ditto -c -k --sequesterRsrc --keepParent Payload "${IPA_NAME}")
else
  (cd "${OUTPUT_DIR}" && zip -qry "${IPA_NAME}" Payload)
fi

[ -f "${OUTPUT_DIR}/${IPA_NAME}" ] || fail "the IPA was not created"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${OUTPUT_DIR}/${IPA_NAME}" | tee "${OUTPUT_DIR}/${IPA_NAME}.sha256"
fi

{
  echo "built_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "configuration=${CONFIGURATION}"
  echo "xcode=$(xcodebuild -version | tr '\n' ' ')"
  echo "iphoneos_sdk=${SDK_VERSION}"
  echo "host_archs=${HOST_ARCHS}"
  echo "extension_archs=${EXT_ARCHS}"
  echo "ipa=${OUTPUT_DIR}/${IPA_NAME}"
  echo "ipa_bytes=$(wc -c < "${OUTPUT_DIR}/${IPA_NAME}" | tr -d ' ')"
  echo "signed=no (unsigned on purpose: SideStore signs on device)"
} > "${OUTPUT_DIR}/build-info.txt"

cat "${OUTPUT_DIR}/build-info.txt"

# ---------------------------------------------------------------------------
# 5. Validate the packaged IPA
# ---------------------------------------------------------------------------
if [ "${KEYRA_SKIP_VALIDATION:-0}" != "1" ]; then
  log "Validating the IPA structure"
  bash "${SCRIPT_DIR}/validate_ipa.sh" "${OUTPUT_DIR}/${IPA_NAME}"
fi

log "Done"
echo "IPA      : ${OUTPUT_DIR}/${IPA_NAME}"
echo "Build log: ${BUILD_LOG}"
