# Build the IPA from Windows 11 and install it with SideStore

This is the complete path from this folder on a Windows 11 PC to a working
keyboard on a physical iPhone. **No Mac and no Xcode are involved on your side** —
the compile happens on a GitHub-hosted macOS runner.

```
Windows 11              GitHub                       macOS runner            iPhone
──────────              ──────                       ────────────            ──────
git push       ───►     repo + Actions      ───►     xcodebuild       ───►   SideStore signs
                        Build Keyra IPA              → CustomKeyboard.ipa    and installs
```

---

## 0. What you need

| | |
|---|---|
| Windows 11 PC | this repository, plus [Git for Windows](https://git-scm.com/download/win) |
| GitHub account | free — the macOS runners are free for public repos (and free-minutes for private ones) |
| iPhone | iOS 16 or newer, with [SideStore](https://sidestore.io) already set up and refreshing |
| Apple ID | any, including a free one — SideStore signs the IPA on the device |
| Time | first build ≈ 3–6 minutes |

Nothing to install on Windows beyond Git and Python 3 (both are only used for the
project generator and the validators).

**Not required:** Xcode, a Mac, a Mac in the cloud you pay for, an Apple Developer
Program membership, a certificate, a provisioning profile, or any signing secret.

---

## 1. Get the code onto GitHub

### Option A — GitHub website + `git` (recommended)

1. On GitHub: **New repository** → name it `keyra` → **Private** is fine
   (public gives unlimited free macOS minutes) → **Create repository**, and do
   **not** add a README or .gitignore.
2. In Git Bash, from this folder:

   ```bash
   cd "/c/Users/ver0016/OneDrive - Hoppers Crossing Secondary College/Documents/Keyra"

   git init -b main
   git add -A
   git commit -m "Keyra: native iPhone custom keyboard with embedded extension"

   git remote add origin https://github.com/<your-username>/keyra.git
   git push -u origin main
   ```

   Git for Windows will open a browser window to sign in to GitHub the first time
   (`git config credential.helper` is already `manager`). No password or token
   needs to be typed.

3. If `git init` has already been run for you in this folder, skip straight to the
   `git remote add` and `git push` lines.

### Option B — GitHub Desktop

**File → Add local repository** → this folder → **Publish repository**. Make sure
"Keep this code private" matches what you want.

### Option C — you would rather I pushed it

Give me the repository URL (or create an empty repo and tell me its name) and I
will add the remote and push from this machine — the Git Credential Manager
already has your `plutoxqq@gmail.com` identity configured. Only the repository is
created on GitHub's side; nothing else leaves your machine.

---

## 2. Let the macOS runner build it

The workflow starts automatically on the first push to `main`/`master`.

1. Open your repository → **Actions** tab.
2. Click **Build Keyra IPA** → the run named after your commit.
3. Watch the steps. What each one proves:

   | Step | What it proves |
   |---|---|
   | Report the runner and toolchain | which macOS + Xcode + `iphoneos` SDK are actually installed (detected, never assumed) |
   | Select the Xcode toolchain | the newest installed Xcode is selected via `DEVELOPER_DIR` |
   | Regenerate the Xcode project | the committed `.xcodeproj` matches `Scripts/generate_xcodeproj.py` |
   | Validate project metadata | plists, entitlements, targets and bundle IDs agree (303 checks) |
   | Static source checks | the Swift sources are balanced and free of `try!`/`as!`/`fatalError`/TODO (148 checks) |
   | Run the shared tests | `swift test` on models, engine, geometry and store |
   | Build … and package the IPA | `xcodebuild` for `-sdk iphoneos` on `arm64`, then `Payload/` → `CustomKeyboard.ipa` |
   | Validate the IPA structure | the `.appex` exists, the extension point is `com.apple.keyboard-service`, bundle IDs match |
   | Inspect the built app bundle | `Info.plist`, architectures, entitlements of the built products |

4. When it finishes, open the run's **Summary**. You get the chosen runner,
   Xcode version, `iphoneos` SDK version, the commit, the artifact details and the
   install steps.

### Getting the file

At the bottom of the run page there is an artifact called **`keyra-ipa-<sha>`**.
Download it and unzip — it contains:

```
CustomKeyboard.ipa              ← install this
CustomKeyboard.ipa.sha256       ← checksum
build-info.txt                  ← Xcode/SDK/version/commit stamp
xcodebuild.log, build.log, swift-test.log
```

### Prefer a normal download link?

Run the workflow manually (**Actions → Build Keyra IPA → Run workflow**) and tick
**publish_release**, or push a tag:

```bash
git tag v1.0 && git push origin v1.0
```

The IPA is then attached to a GitHub **Release**, which downloads like any other
file (artifacts, by contrast, require being signed in to GitHub). This is the
nicest way to fetch it on the iPhone itself.

### Rebuilding later

Every push to `main`/`master` rebuilds. A manual run lets you pick the runner
(`macos-26`, `macos-15`, `macos-14`), pin an Xcode version (e.g. `26.0`), and
choose whether to publish a Release. The build number is taken from the run
number, so successive builds stay distinguishable.

---

## 3. Install with SideStore

1. Get `CustomKeyboard.ipa` onto the iPhone: download the Release asset in Safari,
   AirDrop it, put it in iCloud Drive/Files, or use the SideStore app's own
   pairing-free import.
2. Open **SideStore → My Apps → +** (top right) and pick the IPA. If you opened
   the file from Files, choose **Share → SideStore** instead.
3. **Leave the app extension selected.** SideStore lists the embedded extensions
   it will register; `CustomKeyboardKeyboard` must stay ticked, or the keyboard
   simply will not exist on the device. (This is why the project deliberately
   ships only *one* host app — SideStore must spend a second App ID on the
   keyboard extension. On a free Apple ID that is 2 of the 3 installed apps, and
   it counts against the 10-apps-per-week limit. An app *with an extension* is
   still, by Apple's rules, one installable app for the 3-app limit; the extra App
   ID registration is the real cost.)
4. Wait for **Install** to finish. A second "CustomKeyboard" icon may appear
   briefly while the extension is registered — that is normal.
5. **Trust it if iOS asks:** Settings → General → VPN & Device Management →
   *Developer App* → your Apple ID → **Trust**.
6. Open the **Keyra** host app once. It prints the keyboard status and the exact
   enable steps.

### About App Groups and Full Access (honest version)

Keyra's keyboard extension reads your layouts from the App Group
`group.com.keyra.CustomKeyboard`. For that to work, **all three** of these must be
true:

1. the IPA was signed *with* the App Group entitlement (SideStore applies the
   entitlements from the app it installs — the files are in the project for
   exactly this reason);
2. the extension was registered (step 3 above);
3. **Full Access is enabled** for Keyra in Settings → General → Keyboard →
   Keyboards → Keyra → **Allow Full Access**.

There is a known SideStore limitation around App Group entitlements for
extensions on some versions. If the shared container is not granted, Keyra does
**not** pretend: the host app shows *"App Group unreachable"*, and the keyboard
loads its validated built-in configuration and keeps working. Everything you type
still works; only your custom layouts would not transfer until the container is
available.

Note also what `RequestAccess`/Full Access means: the extension is declared with
`RequestsOpenAccess = true` because shared-container access requires it. That is
the *only* reason. The extension contains no networking and never sends your text
anywhere — you can verify that in `Shared/` and `CustomKeyboardExtension/`.

---

## 4. Enable the keyboard on the iPhone

iOS decides this, not the app — no app can enable its own keyboard.

1. **Settings → General → Keyboard → Keyboards → Add New Keyboard…**
2. Choose **Keyra** (it appears under *Third-Party Keyboards*).
3. Tap **Keyra** in the same list → turn on **Allow Full Access** (needed for
   shared layouts; confirm the warning).
4. Open **Notes**, tap a note to get the cursor, and touch-and-hold the 🌐 globe
   key → **Keyra**. (If the globe is not on your current keyboard, add another
   keyboard first, or use the globe key inside Keyra to switch away.)

The host app's **Setup** tab shows the same steps, plus a live status line and a
heartbeat written by the extension, so you can see *from inside the app* whether
the extension has loaded your configuration, which layout it is on, and whether
Full Access is on.

---

## 5. Test that the dynamic engine really is dynamic

1. In Keyra: **Keyboards → +** to create a layout.
2. In the **Layout Editor**, delete every row and add one with **20 keys**, then a
   second row with **1 key**, then a third with **4 keys**.
3. Give one key width `5.0` and another `0.4`.
4. In the **Key Editor** set a key's action to `Insert Text` with
   `Hello, world!` and another to `Insert Macro` with a multi-line macro.
5. Switch to the extension in Notes. The keyboard renders exactly that shape —
   nothing is fixed at 3/4 rows and nothing is fixed at 10 keys.

---

## 6. LiveContainer — what actually works

You asked for this specifically, so here is the honest position:

**LiveContainer cannot register a keyboard extension.** LiveContainer's own FAQ
says guest apps generally cannot use widgets/plugins/extensions *"They require
extra app ids"*, and extensions cannot be registered at all because LiveContainer
is sandboxed and SpringBoard does not know what apps live inside it. A keyboard
extension therefore needs the system to know about the app.

So:

- **To use the keyboard itself → install Keyra with SideStore** (or AltStore), not
  inside LiveContainer. SideStore installs the app properly, registers
  `CustomKeyboardKeyboard.appex`, and it appears under Settings → Keyboards.
- **LiveContainer is still useful for the host app**: it can run the Keyra editor
  as a guest app so you can build and export layouts, and it will work normally
  inside the container. What it cannot do is make the keyboard appear system-wide.
- Exporting a layout as JSON in LiveContainer and importing it later in the
  SideStore-installed copy is a practical way to move layouts between the two.

The Keyra host app detects the situation instead of looking broken: with no shared
container it reports "App Group unreachable" and marks the layouts accordingly.

---

## 7. Rebuilding with your own identity

To use your own reverse-DNS prefix, edit **one** file:
[`Config/Keyra.xcconfig`](../Config/Keyra.xcconfig).

```ini
KEYRA_BUNDLE_PREFIX = com.yourname
```

then

```bash
python Scripts/generate_xcodeproj.py
python Scripts/validate_project.py
git commit -am "Use my bundle prefix" && git push
```

The extension becomes `com.yourname.CustomKeyboard.Keyboard` and the App Group
`group.com.yourname.CustomKeyboard` consistently across the project, both plists,
both entitlements and both targets — `validate_project.py` fails the build if they
ever disagree.

Since SideStore signs with your Apple ID, use a prefix you personally own; there is
no reason for two people's sideloads to share App IDs.

---

## 8. Where everything ends up

| Thing | Where |
|---|---|
| IPA | `build/Artifacts/CustomKeyboard.ipa` on the runner → artifact `keyra-ipa-<sha>` / Release asset |
| Build logs | artifact: `build.log`, `xcodebuild.log`, `swift-test.log`; the run page log |
| Validation result | the **Validate the IPA structure** step, and the job Summary |
| Repository | your GitHub repo (this folder is the source of truth) |

See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) when a step fails.
