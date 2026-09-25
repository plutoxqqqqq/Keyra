#!/usr/bin/env bash
#
# Human-readable report about a built .app (or an extracted Payload).
#
# Usage:
#   bash Scripts/inspect_bundle.sh build/Artifacts/Payload/CustomKeyboard.app
#
set -euo pipefail

TARGET="${1:-build/Artifacts/Payload/CustomKeyboard.app}"

if [ ! -d "${TARGET}" ]; then
  echo "error: ${TARGET} is not a directory" >&2
  exit 1
fi

# Accept either the .app itself or a directory containing Payload/.
APP="${TARGET}"
if [ ! -f "${APP}/Info.plist" ] && [ -d "${TARGET}/Payload" ]; then
  for candidate in "${TARGET}"/Payload/*.app; do
    [ -d "${candidate}" ] && APP="${candidate}"
  done
fi

plist_value() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null || echo "(missing)"
}

echo "App bundle: ${APP}"
echo "=========================================================="
printf '%-28s %s\n' "CFBundleDisplayName" "$(plist_value "${APP}/Info.plist" CFBundleDisplayName)"
printf '%-28s %s\n' "CFBundleIdentifier" "$(plist_value "${APP}/Info.plist" CFBundleIdentifier)"
printf '%-28s %s\n' "CFBundleVersion" "$(plist_value "${APP}/Info.plist" CFBundleVersion)"
printf '%-28s %s\n' "CFBundleShortVersionString" "$(plist_value "${APP}/Info.plist" CFBundleShortVersionString)"
printf '%-28s %s\n' "MinimumOSVersion" "$(plist_value "${APP}/Info.plist" MinimumOSVersion)"
printf '%-28s %s\n' "App Group" "$(plist_value "${APP}/Info.plist" KeyraSharedContainerID)"
printf '%-28s %s\n' "Executable" "$(plist_value "${APP}/Info.plist" CFBundleExecutable)"

EXECUTABLE="$(plist_value "${APP}/Info.plist" CFBundleExecutable)"
if [ -f "${APP}/${EXECUTABLE}" ]; then
  printf '%-28s %s\n' "Architectures" "$(xcrun lipo -archs "${APP}/${EXECUTABLE}" 2>/dev/null || echo unknown)"
  printf '%-28s %s\n' "Binary size" "$(wc -c < "${APP}/${EXECUTABLE}" | tr -d ' ') bytes"
  SIZE_KIND="$(xcrun size "${APP}/${EXECUTABLE}" 2>/dev/null | tail -n 1 || true)"
  [ -n "${SIZE_KIND}" ] && printf '%-28s %s\n' "Section sizes" "${SIZE_KIND}"
fi

echo ""
echo "PlugIns"
echo "=========================================================="
if [ -d "${APP}/PlugIns" ]; then
  for appex in "${APP}"/PlugIns/*.appex; do
    [ -d "${appex}" ] || continue
    echo "Extension: $(basename "${appex}")"
    printf '%-28s %s\n' "  CFBundleIdentifier" "$(plist_value "${appex}/Info.plist" CFBundleIdentifier)"
    printf '%-28s %s\n' "  Extension point" "$(plist_value "${appex}/Info.plist" NSExtension.NSExtensionPointIdentifier)"
    printf '%-28s %s\n' "  Principal class" "$(plist_value "${appex}/Info.plist" NSExtension.NSExtensionPrincipalClass)"
    printf '%-28s %s\n' "  RequestsOpenAccess" "$(plist_value "${appex}/Info.plist" NSExtension.NSExtensionAttributes.RequestsOpenAccess)"
    printf '%-28s %s\n' "  PrimaryLanguage" "$(plist_value "${appex}/Info.plist" NSExtension.NSExtensionAttributes.PrimaryLanguage)"
    printf '%-28s %s\n' "  App Group" "$(plist_value "${appex}/Info.plist" KeyraSharedContainerID)"
    EXT_EXECUTABLE="$(plist_value "${appex}/Info.plist" CFBundleExecutable)"
    if [ -f "${appex}/${EXT_EXECUTABLE}" ]; then
      printf '%-28s %s\n' "  Architectures" "$(xcrun lipo -archs "${appex}/${EXT_EXECUTABLE}" 2>/dev/null || echo unknown)"
      printf '%-28s %s\n' "  Binary size" "$(wc -c < "${appex}/${EXT_EXECUTABLE}" | tr -d ' ') bytes"
    else
      echo "  MISSING EXECUTABLE: ${EXT_EXECUTABLE}"
    fi
  done
else
  echo "NO PlugIns DIRECTORY — the keyboard extension is not embedded"
fi

echo ""
echo "Resources the extension carries"
echo "=========================================================="
if [ -d "${APP}/PlugIns" ]; then
  find "${APP}/PlugIns" -maxdepth 3 -name '*.json' -o -maxdepth 3 -name '*.plist' | sed "s|${APP}/||" | sort | head -n 20
fi

echo ""
echo "Signing"
echo "=========================================================="
if command -v codesign >/dev/null 2>&1 && codesign -d -v "${APP}" >/dev/null 2>&1; then
  codesign -d -v "${APP}" 2>&1 | head -n 5
  echo "--- entitlements ---"
  codesign -d --entitlements :- "${APP}" 2>/dev/null | head -n 30 || true
else
  echo "unsigned (expected for the CI artefact: SideStore signs on device)"
fi

echo ""
echo "Largest files"
echo "=========================================================="
find "${APP}" -type f -exec ls -l {} \; 2>/dev/null | sort -k5 -n -r | head -n 12 | awk '{printf "%10d  %s\n", $5, $9}'
