# Keyra — a fully configurable native iPhone keyboard

Keyra is a native iOS **custom keyboard app**: an iPhone host app plus an embedded
keyboard extension (`com.apple.keyboard-service`), sharing one JSON configuration
through an App Group. Every key, row, width, colour and action is **data** — the
keyboard renderer has no hardcoded QWERTY layout, no fixed row count and no fixed
number of keys.

The `.ipa` is built **remotely on a GitHub-hosted macOS runner**, so the whole
project can be developed from Windows with no Xcode and no Mac. Nothing about the
build needs an Apple Developer account: the IPA is deliberately **unsigned** and
gets signed on the device by SideStore with your own Apple ID.

```
┌──────────────────────────┐   App Group (group.com.keyra.CustomKeyboard)
│  Keyra.app   (editor)    │──────────────┐
│  SwiftUI layout editor   │              ▼
└──────────────────────────┘      keyboard-config.json
           │                              │
           │ embeds                       ▼
           │                   ┌──────────────────────────────┐
           └──────────────────►│ CustomKeyboardKeyboard.appex │
                               │ UIInputViewController        │
                               │ + SwiftUI keyboard renderer  │
                               └──────────────────────────────┘
```

---

## Status — read this first

| | |
|---|---|
| Source, project generator, scripts, build workflow | **written** |
| Local Python validators (`validate_project.py`, `check_swift_safety.py`) | **pass** (303 + 148 checks) |
| Compiled by a Swift compiler | **not yet** — see below |
| `CustomKeyboard.ipa` | **not yet produced** |
| Verified on a physical iPhone | **not yet** |

Everything in this repository is real code, but it has never been through a Swift
compiler: there is no Xcode or Swift toolchain on Windows. The first
`Build Keyra IPA` workflow run is the moment the code is actually compiled, and
the first run of a project this size normally reports a handful of compile
errors. Those are fixed in the workflow log, not hidden. **The repository does
not claim a build, an IPA or a device test until the workflow has produced one.**

See [`.github/workflows/build-ios.yml`](.github/workflows/build-ios.yml) and
[`docs/BUILD-AND-INSTALL.md`](docs/BUILD-AND-INSTALL.md).

---

## What it does

**Host app (keyboard builder)** — tabbed editor:

- **Keyboards** — create / duplicate / rename / delete layouts, each with its own
  rows and keys, plus a live preview that renders through *the same* SwiftUI view
  the extension uses.
- **Layout Editor** — add, delete, duplicate and reorder rows and keys; explicit
  Move Up / Move Down / Move Left / Move Right buttons, so reordering never
  depends on a drag gesture being reliable.
- **Key Editor** — label, action type, normal output, Shift output, width, height,
  special-key styling, accessibility label, and a long-press alternative editor.
  Controls appear only for the selected action (a Backspace key never shows a text
  field).
- **Themes** — background, key, special-key, pressed-key, text, border colours,
  corner radius, key/row spacing, font size, font weight, opacity, shadow.
  Ships with Light, Dark, Purple and Minimal.
- **Presets** — QWERTY, Symbols, Math, Emoji and Coding, all built as ordinary
  layout data, which is what proves the engine is genuinely dynamic.
- **Import / Export** — human-readable JSON for one layout (optionally with its
  theme) or the whole configuration, with validation and readable errors.
- **Setup** — the real keyboard status and the exact steps to enable the keyboard
  in iOS Settings.

**Keyboard extension** — renders from the shared configuration:

- Text insertion (`insertText`), backspace with press-and-hold repeat, space,
  newline, Shift with double-tap Caps Lock, next keyboard
  (`advanceToNextInputMode`), cursor left/right (`adjustTextPosition`), cursor
  move by offset, layout switching, macros, and no-op.
- Data-driven long-press alternates with a popup, tapped or slid onto.
- Optional haptics (off/light/medium/strong) and optional system key clicks
  (off by default). No private APIs.
- Honest fallback: if the App Group is unavailable or the stored JSON is corrupt,
  the keyboard loads a **validated built-in configuration** and says so in the
  editor instead of pretending shared configuration works.

**Privacy** — no network, no analytics, no keylogging, no storage of typed text.
The only data Keyra writes is the layout configuration you edit and a small
runtime heartbeat (counts, layout name, capabilities — never your text).

---

## Repository layout

```
CustomKeyboard.xcodeproj/     generated — never hand-edit (see Scripts/)
Config/Keyra.xcconfig         the ONE place to change bundle IDs, App Group, names
Shared/                       core: models, engine, store, geometry, defaults
Shared/Rendering/             SwiftUI keyboard views (used by BOTH targets)
CustomKeyboardApp/            host app: editor UI, preview, setup screen
CustomKeyboardExtension/      keyboard extension + Info.plist + entitlements
Scripts/                      project generator, validators, macOS build scripts
Tests/KeyraSharedTests/       swift-test coverage of models, engine, geometry
.github/workflows/            macOS CI that produces CustomKeyboard.ipa
Package.swift                 SwiftPM wrapper so `swift test` runs the shared core
```

### Targets

| Target | Product | Bundle ID |
|---|---|---|
| `CustomKeyboard` (app) | `CustomKeyboard.app` | `com.keyra.CustomKeyboard` |
| `CustomKeyboardExtension` | `CustomKeyboardKeyboard.appex` | `com.keyra.CustomKeyboard.Keyboard` |

App Group: `group.com.keyra.CustomKeyboard` · iOS 16.0+ · `arm64` · iPhone only.

The extension is embedded by the app's *Embed App Extensions* copy phase, so the
`.ipa` contains `Payload/CustomKeyboard.app/PlugIns/CustomKeyboardKeyboard.appex`.
There is exactly one installable app, which keeps free-account sideloading cheap
(SideStore must register the extension as a second App ID — see the sideload doc).

---

## The dynamic layout engine

The renderer walks the decoded configuration. It never assumes a shape:

```swift
ForEach(geometry.rows) { row in          // as many rows as the data has
    ForEach(row.keys) { key in           // as many keys as the row has
        // key width = row's remaining width × normalised weight
    }
}
```

Key widths are **weights**, not pixels: a row's usable width (after spacing) is
divided in proportion to `key.width`. So `A B C` and
`D E F G H I J K L` in adjacent rows both render correctly without any special
case, and Shift 1.5 / Space 5.0 / Return 1.4 coexist with 1.0 keys.

Sanity limits exist only to keep the UI usable and are enforced by
`KeyboardValidator`, at sane magnitudes (40 rows, 60 keys per row, 600 keys
total, 40 layouts). A layout at the top of those limits is still rendered — the
editor warns when a layout is physically impractical, and geometry clamps to
non-negative sizes rather than producing an impossible frame.

---

## Configuration in one place

[`Config/Keyra.xcconfig`](Config/Keyra.xcconfig) is included by both targets and
referenced from both `Info.plist` files, both `.entitlements` files and the
project settings. Change the bundle prefix there, then:

```bash
python Scripts/generate_xcodeproj.py     # regenerate the project
python Scripts/validate_project.py       # prove everything still agrees
```

`validate_project.py` fails if the plists, entitlements, targets and the shared
container identifier disagree, so a stale bundle ID cannot survive unnoticed.

---

## Local commands (Windows is fine)

```bash
python Scripts/generate_xcodeproj.py     # deterministic .xcodeproj generator
python Scripts/validate_project.py       # 303 structural checks
python Scripts/check_swift_safety.py     # 148 source checks
python Scripts/generate_app_icon.py      # writes the 1024×1024 app icon PNG
```

These need only Python 3 — no Xcode, no Swift. The macOS-only scripts
(`build_unsigned_ipa.sh`, `validate_ipa.sh`, `inspect_bundle.sh`) refuse to run
on Windows on purpose and point you at the workflow.

```bash
bash Scripts/build_unsigned_ipa.sh       # macOS/Xcode: build + package + validate
bash Scripts/validate_ipa.sh build/Artifacts/CustomKeyboard.ipa
bash Scripts/inspect_bundle.sh build/Artifacts/Payload
```

---

## Getting the IPA

Full walkthrough: [`docs/BUILD-AND-INSTALL.md`](docs/BUILD-AND-INSTALL.md).
Something went wrong: [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

Short version: push this repository to GitHub, open **Actions → Build Keyra IPA**,
let the macOS runner compile both targets, then download the
`keyra-ipa-<sha>` artifact. Inside it is `CustomKeyboard.ipa` — install that with
SideStore.

---

## Deliberate design decisions

- **Native only.** UIKit owns `UIInputViewController`, the text document proxy,
  lifecycle and keyboard switching; SwiftUI owns the key views and the editor.
  No third-party keyboard framework.
- **Unsigned IPA by design.** No certificate, profile or team ID is stored here,
  and none is needed. The entitlements stay in the project so SideStore can sign
  *with* the App Group — but the build never claims the binary is signed, and the
  runtime reports honestly when the shared container is missing.
- **A shared core.** Everything in `Shared/` (except `Shared/Rendering/`) is
  Foundation-only, which is why `swift test` can cover the models, engine,
  geometry and store on a plain macOS runner with no simulator.
- **Honest UI.** The Setup screen reports "App Group unreachable" and "Full
  Access is off" rather than showing a green tick that is not true.
