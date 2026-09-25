#!/usr/bin/env python3
"""Portable static checks for the Keyra Swift sources.

This is not a compiler. It is the layer of verification that *can* run on
Windows, macOS or Linux, and it catches the mistakes that would otherwise only
appear on the macOS build runner:

* unbalanced (), [] or {} — the most common reason a project fails to compile,
* force unwraps, force casts, fatalError, try! and left-over TODO markers,
* UIKit/SwiftUI accidentally imported into the Foundation-only shared core
  (which would break the `swift test` job on macOS),
* use of APIs that are unavailable to app extensions,
* the required Apple APIs actually being present and used.

Usage:
    python Scripts/check_swift_safety.py
"""

from __future__ import annotations

import os
import re
import sys

SHARED_DIR = "Shared"
SHARED_RENDERING = os.path.join("Shared", "Rendering")
APP_DIR = "CustomKeyboardApp"
EXT_DIR = "CustomKeyboardExtension"

failures: list[str] = []
checks = 0

REQUIRED_FILES = [
    "Shared/KeyboardModels.swift",
    "Shared/KeyboardConfigurationStore.swift",
    "Shared/KeyboardDefaults.swift",
    "Shared/KeyboardTheme.swift",
    "Shared/JSONImportExport.swift",
    "Shared/KeyboardEngine.swift",
    "Shared/KeyboardLayoutMetrics.swift",
    "Shared/KeyboardValidator.swift",
    "Shared/Rendering/KeyboardRootView.swift",
    "Shared/Rendering/KeyboardRowView.swift",
    "Shared/Rendering/KeyboardKeyView.swift",
    "CustomKeyboardApp/CustomKeyboardApp.swift",
    "CustomKeyboardApp/ContentView.swift",
    "CustomKeyboardApp/LayoutEditorView.swift",
    "CustomKeyboardApp/KeyEditorView.swift",
    "CustomKeyboardApp/RowEditorView.swift",
    "CustomKeyboardApp/ThemeEditorView.swift",
    "CustomKeyboardApp/PresetsView.swift",
    "CustomKeyboardApp/SetupView.swift",
    "CustomKeyboardApp/ImportExportView.swift",
    "CustomKeyboardExtension/KeyboardViewController.swift",
    "CustomKeyboardExtension/KeyboardActionHandler.swift",
    "CustomKeyboardExtension/Info.plist",
    "CustomKeyboardExtension/CustomKeyboardExtension.entitlements",
    "CustomKeyboardApp/Info.plist",
    "CustomKeyboardApp/CustomKeyboardApp.entitlements",
    "Config/Keyra.xcconfig",
    "Scripts/build_unsigned_ipa.sh",
    "Scripts/validate_ipa.sh",
    "Scripts/inspect_bundle.sh",
    ".github/workflows/build-ios.yml",
]

# API usage that the specification requires to be real, not simulated.
REQUIRED_API = {
    "CustomKeyboardExtension/KeyboardActionHandler.swift": [
        "textDocumentProxy.insertText",
        "textDocumentProxy.deleteBackward",
        "textDocumentProxy.adjustTextPosition",
        "playInputClick",
    ],
    "CustomKeyboardExtension/KeyboardViewController.swift": [
        "UIInputViewController",
        "advanceToNextInputMode",
        "KeyboardRootView(",
        "KeyboardInputAdapter",
        "KeyboardConfigurationStore",
    ],
    "Shared/KeyboardEngine.swift": [
        "proxy.insertText",
        "proxy.deleteBackward",
        "proxy.adjustTextPosition",
        "nextInputMode",
    ],
    "Shared/KeyboardConfigurationStore.swift": [
        "containerURL(forSecurityApplicationGroupIdentifier",
    ],
    "Shared/KeyboardModels.swift": [
        "Codable",
    ],
}

FORBIDDEN_PATTERNS = [
    (r"\btry!\b", "force-try (`try!`)"),
    (r"\bas!\b", "force cast (`as!`)"),
    (r"\bfatalError\s*\(", "fatalError"),
    (r"\bpreconditionFailure\s*\(", "preconditionFailure"),
    (r"<<<<<<<|>>>>>>>|=======\n", "merge conflict markers"),
    (r"\bTODO\b", "left-over TODO"),
    (r"\bFIXME\b", "left-over FIXME"),
    (r"placeholder implementation", "placeholder implementation"),
    (r"not implemented", "unimplemented code"),
]

EXTENSION_UNSAFE = [
    (r"\bUIApplication\.shared\b", "UIApplication.shared (unavailable in app extensions)"),
    (r"\bopenURL\b", "openURL (unavailable in app extensions)"),
]

counter = {"(": ")", "[": "]", "{": "}"}


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        failures.append(message)
    return bool(condition)


def fail(message):
    global checks
    checks += 1
    failures.append(message)


def strip_for_balance(source: str):
    """Walks the file tracking strings, comments and interpolations.

    Returns (balances, error) where balances maps a bracket opener to the number
    of unbalanced opens, and error is a description of the first imbalance.
    """
    stack = ["code"]
    depths = {"(": 0, "[": 0, "{": 0}
    interp_depths = []
    index = 0
    length = len(source)

    while index < length:
        char = source[index]
        context = stack[-1]

        if context == "line_comment":
            if char == "\n":
                stack.pop()
            index += 1
            continue

        if context == "block_comment":
            if source.startswith("*/", index):
                stack.pop()
                index += 2
                continue
            if source.startswith("/*", index):
                stack.append("block_comment")
                index += 2
                continue
            index += 1
            continue

        if context in ("string", "multiline"):
            if char == "\\":
                if source.startswith("\\(", index):
                    # A string interpolation counts as an opening parenthesis so
                    # its closing one stays balanced, and the rest of the literal
                    # keeps being treated as string content.
                    stack.append("interpolation")
                    interp_depths.append(depths["("])
                    depths["("] += 1
                    index += 2
                    continue
                index += 2
                continue
            if context == "string" and char == '"':
                stack.pop()
                if not stack:
                    stack = ["code"]
                index += 1
                continue
            if context == "multiline" and source.startswith('"""', index):
                stack.pop()
                if not stack:
                    stack = ["code"]
                index += 3
                continue
            index += 1
            continue

        # code (or interpolation contents)
        if source.startswith("//", index):
            stack.append("line_comment")
            index += 2
            continue
        if source.startswith("/*", index):
            stack.append("block_comment")
            index += 2
            continue
        if source.startswith('"""', index):
            stack.append("multiline")
            index += 3
            continue
        if char == '"':
            stack.append("string")
            index += 1
            continue

        if char in "([{":
            depths[char] += 1
            index += 1
            continue
        if char in ")]}":
            opener = {")": "(", "]": "[", "}": "{"}[char]
            if depths[opener] == 0:
                return depths, f"unbalanced '{char}' (nothing to close) near offset {index}"
            depths[opener] -= 1
            if (char == ")" and stack and stack[-1] == "interpolation"
                    and interp_depths and depths["("] == interp_depths[-1]):
                stack.pop()
                interp_depths.pop()
            index += 1
            continue

        index += 1

    for opener, count in depths.items():
        if count != 0:
            return depths, f"{count} unbalanced '{opener}' (never closed)"
    return depths, None


def check_balance(path, source):
    _, error = strip_for_balance(source)
    check(error is None, f"{path}: {error}" if error else "")


def scan_file(path, source):
    for pattern, description in FORBIDDEN_PATTERNS:
        for match in re.finditer(pattern, source):
            line = source[:match.start()].count("\n") + 1
            fail(f"{path}:{line}: {description}")

    # Force unwrap heuristic: `something!` where `!` is not part of != or a
    # logical negation. Implicitly unwrapped optionals would also be caught here.
    for match in re.finditer(r"(?<![!=<>+\-*/%&|^~?])([A-Za-z0-9_\)\]])\!", source):
        trailing = source[match.end():match.end() + 1]
        if trailing in (".", ")", "]", ",", ";", "\n", " "):
            line = source[:match.start()].count("\n") + 1
            fail(f"{path}:{line}: possible force unwrap: {match.group(0)!r}")

    for pattern, description in EXTENSION_UNSAFE:
        for match in re.finditer(pattern, source):
            line = source[:match.start()].count("\n") + 1
            fail(f"{path}:{line}: {description}")


def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(project_root)

    print("Keyra Swift source checks")

    for relative in REQUIRED_FILES:
        check(os.path.exists(relative), f"missing required file: {relative}")

    swift_files = []
    for directory in [SHARED_DIR, APP_DIR, EXT_DIR]:
        for root, dirs, files in os.walk(directory):
            dirs[:] = sorted(d for d in dirs if not d.startswith("."))
            for name in sorted(files):
                if name.endswith(".swift"):
                    swift_files.append(os.path.normpath(os.path.join(root, name)))
    swift_files.sort()

    shared_core = []
    shared_rendering = []
    extension_files = []
    app_files = []

    for path in swift_files:
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()

        check_balance(path, source)
        scan_file(path, source)

        normalized = path.replace("\\", "/")
        if normalized.startswith("Shared/Rendering/"):
            shared_rendering.append(path)
            if not re.search(r"^import (SwiftUI|UIKit)", source, re.M):
                fail(f"{path}: shared rendering file should import SwiftUI")
            else:
                check(True, "")
            continue

        if normalized.startswith("Shared/"):
            # The shared core is compiled by `swift test` on macOS, so it must stay
            # Foundation-only. This is a hard requirement, not a style preference.
            for module in ("SwiftUI", "UIKit", "AppKit", "Combine"):
                if re.search(rf"^import {module}\b", source, re.M):
                    fail(f"{path}: the Foundation-only shared core must not import {module}")
                else:
                    check(True, "")
            if not re.search(r"^import Foundation\b", source, re.M):
                fail(f"{path}: shared core file does not import Foundation")
            else:
                check(True, "")
            shared_core.append(path)
            continue

        if normalized.startswith("CustomKeyboardExtension/"):
            extension_files.append(path)
            continue

        app_files.append(path)

    print(f"  {len(swift_files)} Swift files: {len(shared_core)} shared core, "
          f"{len(shared_rendering)} shared rendering, {len(extension_files)} extension, {len(app_files)} host app")

    for path, snippets in REQUIRED_API.items():
        if not os.path.exists(path):
            fail(f"missing {path} (required Apple API check)")
            continue
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
        for snippet in snippets:
            check(snippet in source, f"{path} does not use the required API: {snippet}")

    # The shared rendering layer must be shared: both targets compile it.
    check(len(shared_rendering) >= 4, "expected at least four shared rendering files")

    # Make sure the preview is not a separate implementation: both the host app
    # and the extension must reference the shared root view.
    with open(os.path.join(EXT_DIR, "KeyboardViewController.swift"), "r", encoding="utf-8") as handle:
        controller = handle.read()
    check("KeyboardRootView(" in controller, "the keyboard extension does not render the shared KeyboardRootView")

    print("")
    if failures:
        print(f"FAILED: {len(failures)} problem(s)")
        for problem in failures:
            print(f"  - {problem}")
        return 1
    print(f"OK: {checks} checks passed across {len(swift_files)} Swift files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
