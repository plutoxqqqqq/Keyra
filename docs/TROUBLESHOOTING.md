# Troubleshooting

Two groups of problems: the **build** (GitHub Actions, macOS runner) and the
**device** (SideStore install, keyboard behaviour). Find the symptom, apply the
fix, and re-run — everything is reproducible from a clean clone.

---

## A. The build failed

### `The generated Xcode project is out of date`

The committed `.xcodeproj` does not match `Scripts/generate_xcodeproj.py` (usually
after adding, renaming or deleting a Swift file). On Windows:

```bash
python Scripts/generate_xcodeproj.py
git commit -am "Regenerate Xcode project" && git push
```

The project is generated, never hand-edited: fixing `project.pbxproj` by hand will
be overwritten and will fail this check again.

### `error: cannot find 'X' in scope` / `cannot convert` / other Swift errors

Expected on an early run: this code had never been through a compiler before its
first CI run on Windows. The full compiler output is in the artifacts
(`xcodebuild.log`, and `build.log`) and in the run log. Read the **first** error
in the file listed — later errors are usually cascade noise. Fix, push, re-run.

To reproduce the shared core's errors much faster than a full iOS build, the
`Run the shared tests` step compiles `Shared/` through SwiftPM; those errors print
in `swift-test.log`. That step is allowed to fail without stopping the IPA build,
so a red X there does not mean the app did not compile — check the build step.

### `The iphoneos SDK is missing`

The selected Xcode did not include iOS device support. Use a different runner
(**Run workflow** → `runner: macos-26`) or pin `xcode: 26.0`. The workflow reports
every installed Xcode at the top of the log so you can copy an exact name.

### `Requested Xcode not found` warning

Your `xcode` input did not match anything on that runner; the build continued with
the newest installed Xcode (the workflow prints which one). Re-run with an empty
input to silence it.

### Build succeeds but the artifact is missing

Look for the artifact named `keyra-ipa-<sha>`. If files were missing, the upload
step warns and a second artifact `keyra-failure-logs-<sha>` appears with the logs
only. Confirm the build step actually reached `CustomKeyboard.ipa` in its log.

---

## B. The IPA is wrong

`Scripts/validate_ipa.sh` is the gate, and it exits non-zero on any problem.

### `Payload/…app` or `PlugIns/….appex` missing

The keyboard extension is not embedded — the app would install but never appear as
a keyboard. Causes: the *Embed App Extensions* copy phase lost its product
reference, or the extension target is not a dependency of the app target. Both are
generated, so regenerate and re-run:

```bash
python Scripts/generate_xcodeproj.py && python Scripts/validate_project.py
```

`validate_project.py` prints the embed phase and the embedded product count; it
must report **1 embedded product** and **0 dangling references**.

### `the extension point is not com.apple.keyboard-service`

`CustomKeyboardExtension/Info.plist` lost its `NSExtensionPointIdentifier`. It must
be exactly `com.apple.keyboard-service`, with
`NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).KeyboardViewController` and
`PRODUCT_MODULE_NAME = CustomKeyboardExtension`. A mismatch here makes iOS refuse
to load the keyboard (it dies the moment you select it).

### `bundle identifier mismatch`

The extension's bundle ID must be the app's ID plus a suffix
(`com.keyra.CustomKeyboard.Keyboard`). Change it only in
`Config/Keyra.xcconfig`, then regenerate and re-validate.

### `architecture ... expected arm64`

The final IPA must be built for a real device (`-sdk iphoneos`), never
`iphonesimulator`. Simulator binaries install but the keyboard never loads. The
build script and workflow both force the device SDK; a simulator build in the IPA
means something bypassed them.

### `App Group entitlement not found`

The `.entitlements` files were stripped from a target. They are deliberately kept
in the project so SideStore can sign with the App Group — do not remove them to
make a build succeed. Without the entitlement the keyboard still runs (built-in
configuration), but your layouts will not transfer, and the app will say so.

---

## C. SideStore problems

### SideStore rejects the IPA / "invalid provisioning" / "could not sign"

- Free Apple IDs cannot register an unlimited number of App IDs. **Remove an
  unused app or extension first**, then retry — Keyra needs two IDs (host +
  keyboard extension).
- Signing sometimes fails when the device's clock, network, or Apple session is
  stale: re-authenticate the Apple ID inside SideStore, then retry.
- Refresh SideStore's own installation (or let its 7-day refresh run) before
  installing something new.
- The file must be a complete `.ipa`. Re-download it instead of unzipping and
  re-zipping: a re-zipped IPA loses the `Payload/` root the installer expects.

### "CustomKeyboard" appears twice, or the keyboard extension never registers

SideStore installs the host app and separately registers each embedded extension;
do not deselect `CustomKeyboardKeyboard` during install. If you already installed
without it, delete the app in SideStore and install again with the extension
ticked.

### The app will not launch: "Untrusted Developer"

Settings → General → VPN & Device Management → *Developer App* → your Apple ID →
**Trust**. This is required after every re-sign, and again every 7 days on a free
Apple ID.

### Free-account limits to expect

Free Apple IDs allow **3 installed apps at once** and **10 different apps per
week**, with passes that must refresh every **7 days**; running out of either
produces signing/installation failures that look like bugs in the app. Keyra is
one app, but its keyboard extension consumes a second App ID slot. That is exactly
why this project ships a single host app and no helper app, widget or second
extension.

---

## D. The keyboard on the device

### The keyboard is not in Settings → General → Keyboard → Keyboards

- The host app has never been opened. Launch **Keyra** once.
- The app is installed but the extension was not registered (see C above).
- Reinstall: delete from SideStore, reinstall with the extension ticked, open the
  app, then check **Add New Keyboard…** again.
- If Keyra is still missing, check the host app's **Setup** tab — if it can't
  enumerate the keyboard, the install is incomplete rather than misconfigured.

### It is in Keyboards but does not appear while typing

Touch-and-hold the 🌐 globe key on the *current* keyboard and pick **Keyra**. If
there is only one keyboard on the device there is no globe key at all, so first add
a second keyboard (Settings → General → Keyboard → Keyboards → Add New Keyboard →
e.g. Emoji), or tap the 🌐 key *inside Keyra* to switch back. Keyra's own globe key
appears only when iOS reports `needsInputModeSwitchKey` — that is Apple's rule, not
a missing feature.

### The keyboard appears and immediately closes / crashes

Usually a load failure rather than a logic bug:

- A `NSExtensionPrincipalClass`/`PRODUCT_MODULE_NAME` mismatch — see B.
- An invalid layout. Keyra's configuration loader is written never to crash (it
  quarantines unreadable data to `keyboard-config.corrupt.json`, repairs what it
  can, and falls back to the built-in layout), so if it still dies, read the crash
  report: Settings → Privacy & Security → Analytics & Data → Analytics Data.
- Memory pressure: a keyboard extension runs in a small memory budget. Absurd
  layouts (hundreds of keys) are clamped and warned about in the editor for this
  reason.

### The host app works but the extension never uses my layouts

That is the App Group path failing, and Keyra reports it rather than hiding it:

1. Open the host app → **Setup**: if it says *App Group unreachable*, the
   entitlement was not signed into the build (SideStore install without the App
   Group, or the entitlements were stripped — see B).
2. Settings → General → Keyboard → Keyboards → **Keyra** → **Allow Full Access**
   must be ON. Without it the extension cannot read the shared container at all.
3. Re-open the host app after editing a layout: the save is debounced (0.5 s), so
   give it a moment before switching to the keyboard.
4. In the keyboard, switch layouts (or reopen the keyboard) to pick up a change —
   configuration reloads on appearance by design, not on every keystroke.

### Configuration not syncing / my edits are missing on the other side

- The heartbeat in the Setup tab tells you what the *extension* actually loaded:
  source (`sharedContainer` / `localFallback` / `builtInDefaults`), generation and
  key count. If the source says `localFallback`, the keyboard is using its own
  copy — the App Group is not shared on that install.
- A newly edited layout must be made active in the host app before the keyboard
  will show it.
- Export the layout to JSON (Import/Export tab) as a reliable manual bridge, and
  import it on the other side.

---

## E. Diagnosing anything else

Run these on the device-connected Mac if you have one, or rely on the CI logs:

```bash
bash Scripts/inspect_bundle.sh build/Artifacts/Payload   # plists, arch, entitlements
bash Scripts/validate_ipa.sh  build/Artifacts/CustomKeyboard.ipa
python Scripts/validate_project.py
python Scripts/check_swift_safety.py
```

Useful out-of-band checks:

```bash
xcrun simctl list keyboards          # not a device test, but shows registration data
ideviceinstaller -l                  # list installed apps/extensions
```

When reporting a build problem, include the **run URL**, the failing step name and
the first ~30 lines of the relevant log — that is normally enough to pinpoint it.

---

## F. Things that are *not* bugs

- **The IPA is unsigned.** SideStore signs it; "not signed" is the design.
- **The keyboard does not appear in a LiveContainer guest app.** LiveContainer
  cannot register app extensions — see
  [BUILD-AND-INSTALL.md §6](BUILD-AND-INSTALL.md).
- **The globe key is missing on some text fields.** iOS omits
  `needsInputModeSwitchKey` there.
- **A keyboard without Full Access cannot read shared layouts.** Apple's sandbox,
  not a Keyra bug.
- **Inserting `"\n"` does not always behave like Return.** Host apps differ in how
  they treat a newline; Keyra inserts the character and does not pretend
  otherwise.
- **Cursor movement is limited to what `adjustTextPosition` supports.** Arbitrary
  selection and text replacement inside another app's text field is not available
  to keyboard extensions.
