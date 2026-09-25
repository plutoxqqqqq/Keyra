#!/usr/bin/env bash
#
# Validate an .ipa before it is handed to SideStore.
#
# Fails with a non-zero status when anything required is missing, so a broken
# build can never be published as "the IPA".
#
# Usage:
#   bash Scripts/validate_ipa.sh [path/to/CustomKeyboard.ipa]
#
set -euo pipefail

IPA_PATH="${1:-build/Artifacts/CustomKeyboard.ipa}"
KEYBOARD_EXTENSION_POINT="com.apple.keyboard-service"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

ok()   { PASS_COUNT=$((PASS_COUNT + 1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); printf '  \033[33mWARN\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# plutil value lookup that never aborts the script.
plist_value() {
  local file="$1" key="$2"
  plutil -extract "${key}" raw -o - "${file}" 2>/dev/null || echo ""
}

step "Validating ${IPA_PATH}"

[ -f "${IPA_PATH}" ] || { bad "the IPA does not exist"; exit 1; }
ok "the IPA exists ($(wc -c < "${IPA_PATH}" | tr -d ' ') bytes)"

if unzip -tqq "${IPA_PATH}" >/dev/null 2>&1; then
  ok "the IPA is a readable zip archive"
else
  bad "the IPA is corrupt (unzip -t failed)"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if ! unzip -qq "${IPA_PATH}" -d "${WORK_DIR}"; then
  bad "the IPA could not be extracted"
  exit 1
fi

# ---------------------------------------------------------------------------
step "Payload structure"
# ---------------------------------------------------------------------------
[ -d "${WORK_DIR}/Payload" ] || { bad "Payload/ is missing"; exit 1; }
ok "Payload/ exists"

APP_COUNT=0
APP_BUNDLE=""
for candidate in "${WORK_DIR}"/Payload/*.app; do
  [ -d "${candidate}" ] || continue
  APP_COUNT=$((APP_COUNT + 1))
  APP_BUNDLE="${candidate}"
done

if [ "${APP_COUNT}" -eq 1 ]; then
  ok "exactly one app bundle: $(basename "${APP_BUNDLE}")"
elif [ "${APP_COUNT}" -eq 0 ]; then
  bad "Payload does not contain any .app bundle"
  exit 1
else
  bad "Payload contains ${APP_COUNT} app bundles; SideStore expects one"
fi

APP_INFO="${APP_BUNDLE}/Info.plist"
[ -f "${APP_INFO}" ] || { bad "the app bundle has no Info.plist"; exit 1; }
ok "the app Info.plist exists"

APP_BUNDLE_ID="$(plist_value "${APP_INFO}" CFBundleIdentifier)"
APP_EXECUTABLE="$(plist_value "${APP_INFO}" CFBundleExecutable)"
APP_PACKAGE_TYPE="$(plist_value "${APP_INFO}" CFBundlePackageType)"
APP_MIN_OS="$(plist_value "${APP_INFO}" MinimumOSVersion)"

[ -n "${APP_BUNDLE_ID}" ] && ok "CFBundleIdentifier = ${APP_BUNDLE_ID}" || bad "the app has no CFBundleIdentifier"
[ "${APP_PACKAGE_TYPE}" = "APPL" ] && ok "CFBundlePackageType = APPL" || bad "CFBundlePackageType is '${APP_PACKAGE_TYPE}', expected APPL"
[ -n "${APP_MIN_OS}" ] && ok "MinimumOSVersion = ${APP_MIN_OS}" || warn "MinimumOSVersion is missing from the packaged Info.plist"
[ -n "${APP_EXECUTABLE}" ] && ok "CFBundleExecutable = ${APP_EXECUTABLE}" || bad "the app has no CFBundleExecutable"

APP_BINARY="${APP_BUNDLE}/${APP_EXECUTABLE}"
if [ -f "${APP_BINARY}" ]; then
  ok "the app executable exists"
else
  bad "the app executable '${APP_EXECUTABLE}' is missing"
  APP_BINARY=""
fi

# A payload that still carries a signature or profile of somebody else's team
# would be wrong for a re-signing workflow.
if [ -d "${APP_BUNDLE}/_CodeSignature" ]; then
  warn "the app contains _CodeSignature (it will be replaced when SideStore re-signs)"
else
  ok "the app is unsigned, as expected for SideStore"
fi
if [ -f "${APP_BUNDLE}/embedded.mobileprovision" ]; then
  warn "the app carries an embedded provisioning profile; it will be replaced on install"
fi

# ---------------------------------------------------------------------------
step "Keyboard extension"
# ---------------------------------------------------------------------------
PLUGINS_DIR="${APP_BUNDLE}/PlugIns"
if [ -d "${PLUGINS_DIR}" ]; then
  ok "PlugIns/ exists inside the app"
else
  bad "PlugIns/ is missing: the keyboard extension is NOT embedded"
fi

EXT_COUNT=0
EXT_BUNDLE=""
if [ -d "${PLUGINS_DIR}" ]; then
  for candidate in "${PLUGINS_DIR}"/*.appex; do
    [ -d "${candidate}" ] || continue
    EXT_COUNT=$((EXT_COUNT + 1))
    EXT_BUNDLE="${candidate}"
  done
fi

if [ "${EXT_COUNT}" -eq 1 ]; then
  ok "exactly one app extension: $(basename "${EXT_BUNDLE}")"
elif [ "${EXT_COUNT}" -eq 0 ]; then
  bad "no .appex was found inside PlugIns/ — the IPA has no keyboard"
else
  bad "${EXT_COUNT} app extensions found; Keyra embeds exactly one"
fi

if [ -n "${EXT_BUNDLE}" ]; then
  EXT_INFO="${EXT_BUNDLE}/Info.plist"
  [ -f "${EXT_INFO}" ] && ok "the extension Info.plist exists" || bad "the extension has no Info.plist"

  EXT_POINT="$(plist_value "${EXT_INFO}" NSExtension.NSExtensionPointIdentifier)"
  if [ "${EXT_POINT}" = "${KEYBOARD_EXTENSION_POINT}" ]; then
    ok "NSExtensionPointIdentifier = ${KEYBOARD_EXTENSION_POINT}"
  else
    bad "NSExtensionPointIdentifier is '${EXT_POINT}', expected '${KEYBOARD_EXTENSION_POINT}'"
  fi

  EXT_PRINCIPAL="$(plist_value "${EXT_INFO}" NSExtension.NSExtensionPrincipalClass)"
  if [ -n "${EXT_PRINCIPAL}" ]; then
    ok "NSExtensionPrincipalClass = ${EXT_PRINCIPAL}"
  else
    bad "NSExtensionPrincipalClass is missing"
  fi

  EXT_OPEN_ACCESS="$(plist_value "${EXT_INFO}" NSExtension.NSExtensionAttributes.RequestsOpenAccess)"
  if [ "${EXT_OPEN_ACCESS}" = "true" ]; then
    ok "RequestsOpenAccess = true (needed for the shared App Group container)"
  else
    warn "RequestsOpenAccess is '${EXT_OPEN_ACCESS}'; the keyboard will not read the shared container"
  fi

  EXT_BUNDLE_ID="$(plist_value "${EXT_INFO}" CFBundleIdentifier)"
  [ -n "${EXT_BUNDLE_ID}" ] && ok "extension CFBundleIdentifier = ${EXT_BUNDLE_ID}" || bad "the extension has no CFBundleIdentifier"

  if [ -n "${APP_BUNDLE_ID}" ] && [ -n "${EXT_BUNDLE_ID}" ]; then
    case "${EXT_BUNDLE_ID}" in
      "${APP_BUNDLE_ID}."*) ok "the extension identifier is prefixed by the app identifier" ;;
      *) bad "the extension identifier '${EXT_BUNDLE_ID}' is not prefixed by '${APP_BUNDLE_ID}'" ;;
    esac
  fi

  EXT_EXECUTABLE="$(plist_value "${EXT_INFO}" CFBundleExecutable)"
  EXT_BINARY="${EXT_BUNDLE}/${EXT_EXECUTABLE}"
  if [ -n "${EXT_EXECUTABLE}" ] && [ -f "${EXT_BINARY}" ]; then
    ok "the extension executable exists (${EXT_EXECUTABLE})"
  else
    bad "the extension executable is missing"
    EXT_BINARY=""
  fi

  # The keyboard must be able to find its layout data.
  EXT_CONTAINER="$(plist_value "${EXT_INFO}" KeyraSharedContainerID)"
  APP_CONTAINER="$(plist_value "${APP_INFO}" KeyraSharedContainerID)"
  if [ -n "${EXT_CONTAINER}" ] && [ "${EXT_CONTAINER}" = "${APP_CONTAINER}" ]; then
    ok "the app and extension agree on the App Group (${EXT_CONTAINER})"
  else
    bad "the app and extension disagree about the App Group ('${APP_CONTAINER}' vs '${EXT_CONTAINER}')"
  fi
fi

# ---------------------------------------------------------------------------
step "Architecture (must be a device build)"
# ---------------------------------------------------------------------------
check_archs() {
  local binary="$1" label="$2"
  [ -n "${binary}" ] || return 0
  [ -f "${binary}" ] || return 0
  local archs
  archs="$(xcrun lipo -archs "${binary}" 2>/dev/null || echo "")"
  if [ -z "${archs}" ]; then
    warn "could not read the architecture of ${label}"
    return 0
  fi
  case "${archs}" in
    *arm64*) ok "${label} contains arm64 (${archs})" ;;
    *) bad "${label} is not arm64 (${archs})" ;;
  esac
  case "${archs}" in
    *x86_64*|*i386*) bad "${label} contains a simulator slice (${archs}) — a simulator build must never be shipped" ;;
  esac

  # Prove the binary was linked against the device platform, not the simulator.
  local platform
  platform="$(otool -l "${binary}" 2>/dev/null | grep -A4 'LC_BUILD_VERSION' | grep -m1 'platform' | awk '{print $2}')"
  if [ -n "${platform}" ]; then
    if [ "${platform}" = "IOS" ] || [ "${platform}" = "2" ]; then
      ok "${label} is linked for the iOS device platform"
    else
      bad "${label} is linked for platform '${platform}', expected IOS"
    fi
  else
    warn "could not determine the link platform of ${label}"
  fi
}
check_archs "${APP_BINARY:-}" "the host app"
check_archs "${EXT_BINARY:-}" "the keyboard extension"

# ---------------------------------------------------------------------------
step "Entitlements and signing"
# ---------------------------------------------------------------------------
if command -v codesign >/dev/null 2>&1 && [ -n "${APP_BINARY:-}" ]; then
  if codesign -d -v "${APP_BUNDLE}" >/dev/null 2>&1; then
    warn "the app is signed; SideStore will replace this signature"
    ENTITLEMENTS="$(codesign -d --entitlements :- "${APP_BUNDLE}" 2>/dev/null || echo "")"
    if printf '%s' "${ENTITLEMENTS}" | grep -q "application-groups"; then
      ok "the existing signature carries the App Group entitlement"
    else
      warn "the existing signature does not contain the App Group entitlement"
    fi
  else
    ok "the app is unsigned: SideStore will sign it with your Apple ID and the App Group entitlement from the project"
  fi
fi

# The entitlement sources must still be in the repository: the project must not
# silently drop App Groups just to make the build succeed.
# The entitlement key itself contains dots, so PlistBuddy's ':' separator is used.
entitlement_group() {
  local file="$1"
  /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "${file}" 2>/dev/null || echo ""
}

if [ -f "CustomKeyboardApp/CustomKeyboardApp.entitlements" ] && [ -f "CustomKeyboardExtension/CustomKeyboardExtension.entitlements" ]; then
  APP_GROUP_APP="$(entitlement_group CustomKeyboardApp/CustomKeyboardApp.entitlements)"
  APP_GROUP_EXT="$(entitlement_group CustomKeyboardExtension/CustomKeyboardExtension.entitlements)"
  if [ -n "${APP_GROUP_APP}" ] && [ "${APP_GROUP_APP}" = "${APP_GROUP_EXT}" ]; then
    ok "both targets keep the same App Group entitlement (${APP_GROUP_APP})"
  else
    bad "the targets' App Group entitlements differ or are missing ('${APP_GROUP_APP}' vs '${APP_GROUP_EXT}')"
  fi
else
  bad "the entitlements files are missing from the repository"
fi

# ---------------------------------------------------------------------------
step "Result"
# ---------------------------------------------------------------------------
printf '  %d passed, %d failed, %d warnings\n' "${PASS_COUNT}" "${FAIL_COUNT}" "${WARN_COUNT}"
if [ "${FAIL_COUNT}" -gt 0 ]; then
  printf '\033[31mIPA VALIDATION FAILED\033[0m\n'
  exit 1
fi
printf '\033[32mIPA VALIDATION PASSED\033[0m\n'
