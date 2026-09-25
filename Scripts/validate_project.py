#!/usr/bin/env python3
"""Validate the Keyra project without a Mac.

This script is the portable safety net for a repository that is built on a
GitHub macOS runner: everything that can be checked from any operating system is
checked here, with a non-zero exit status when something is wrong.

It verifies, among other things:

* every object identifier referenced in project.pbxproj really exists,
* every Swift file on disk has exactly the right target membership
  (host app, keyboard extension, or both for Shared/),
* the keyboard extension is embedded in the host application (PlugIns copy
  phase) and the host depends on the extension target,
* the shared scheme points at the host app target,
* Info.plist / entitlements contents: extension point, principal class,
  RequestsOpenAccess, bundle identifiers, App Group consistency, launch screen,
* build settings: iPhone-only, device SDK, deployment target, entitlements
  files, extension API only, extension product naming,
* the asset catalog and the app icon PNG,
* the shipped fallback keyboard JSON against the model's schema.

Usage:
    python Scripts/validate_project.py
"""

from __future__ import annotations

import json
import os
import plistlib
import re
import struct
import sys

PROJECT_DIR = "CustomKeyboard.xcodeproj"
PBXPROJ = os.path.join(PROJECT_DIR, "project.pbxproj")
SCHEME = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", "CustomKeyboard.xcscheme")
XCCONFIG = os.path.normpath("Config/Keyra.xcconfig")

APP_DIR = "CustomKeyboardApp"
EXT_DIR = "CustomKeyboardExtension"
SHARED_DIR = "Shared"

APP_PRODUCT = "CustomKeyboard.app"
EXT_PRODUCT = "CustomKeyboardKeyboard.appex"

KEYBOARD_EXTENSION_POINT = "com.apple.keyboard-service"

failures: list[str] = []
checks = 0


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        failures.append(message)
    return bool(condition)


def note(message):
    print(f"      {message}")


# ---------------------------------------------------------------------------
# project.pbxproj parsing
# ---------------------------------------------------------------------------

ID_PATTERN = re.compile(r"\b([0-9A-F]{24})\b")
OBJECT_PATTERN = re.compile(r"\n\t\t([0-9A-F]{24}) = \{")


def strip_comments(text: str) -> str:
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


def parse_objects(text: str):
    """Returns {identifier: body} for the top level objects of the pbxproj."""
    objects = {}
    for match in OBJECT_PATTERN.finditer(text):
        identifier = match.group(1)
        start = match.end() - 1  # position of '{'
        depth = 0
        index = start
        while index < len(text):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        objects[identifier] = text[start:index + 1]
    return objects


def object_value(body: str, key: str):
    """Top-level `key = value;` lookup inside one object body."""
    depth = 0
    lines = body.split("\n")
    for line in lines:
        stripped = line.strip()
        if depth <= 1 and stripped.startswith(f"{key} = "):
            value = stripped[len(key) + 3:].rstrip(";").strip()
            return value
        depth += line.count("{") - line.count("}")
    return None


def object_list(body: str, key: str):
    """Extracts the identifiers inside a `key = ( ... );` list."""
    pattern = re.compile(rf"{re.escape(key)} = \((.*?)\);", re.S)
    match = pattern.search(body)
    if not match:
        return []
    return ID_PATTERN.findall(match.group(1))


def build_settings(body: str):
    settings = {}
    match = re.search(r"buildSettings = \{(.*?)\n\t\t\t\};", body, re.S)
    if not match:
        return settings
    block = match.group(1)
    for line in block.split("\n"):
        stripped = line.strip()
        if not stripped or "=" not in stripped:
            continue
        key, _, value = stripped.partition(" = ")
        settings[key] = value.rstrip(";").strip()
    return settings


def read_pbxproj():
    with open(PBXPROJ, "r", encoding="utf-8") as handle:
        raw = handle.read()
    text = strip_comments(raw)
    return raw, text, parse_objects(text)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def collect_swift(directory):
    found = []
    for root, dirs, files in os.walk(directory):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(files):
            if name.endswith(".swift"):
                found.append(os.path.normpath(os.path.join(root, name)))
    return sorted(found)


def read_plist(path):
    with open(path, "rb") as handle:
        return plistlib.load(handle)


def read_xcconfig(path):
    values = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if not stripped or stripped.startswith("//") or "=" not in stripped:
                continue
            key, _, value = stripped.partition("=")
            values[key.strip()] = value.strip()
    return values


def expand_xcconfig(values):
    """Resolves $(VAR) references exactly like Xcode does, so the validator can
    check the identifiers the build will really use — not just the source text."""
    resolved = {}

    def resolve(name, depth=0):
        if name in resolved:
            return resolved[name]
        if depth > 12 or name not in values:
            return None
        value = values[name]
        resolved[name] = value  # break cycles
        expanded = re.sub(
            r"\$\(([A-Za-z0-9_]+)\)",
            lambda match: resolve(match.group(1), depth + 1) or match.group(0),
            value,
        )
        resolved[name] = expanded
        return expanded

    for key in list(values):
        resolve(key)
    return resolved


def png_size(path):
    with open(path, "rb") as handle:
        header = handle.read(33)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height, depth, colour = struct.unpack(">IIBB", header[16:26])
    return width, height, depth, colour


# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

def validate_project_file():
    print("  project.pbxproj")
    if not check(os.path.exists(PBXPROJ), f"missing {PBXPROJ}"):
        return None

    raw, text, objects = read_pbxproj()
    check(len(objects) > 40, f"only {len(objects)} objects parsed from the project file")

    # Referential integrity: every identifier used anywhere must be an object.
    referenced = set()
    for identifier, body in objects.items():
        for candidate in ID_PATTERN.findall(body):
            if candidate != identifier:
                referenced.add(candidate)
    root_match = re.search(r"rootObject = ([0-9A-F]{24});", text)
    check(root_match is not None, "project file has no rootObject")
    if root_match:
        referenced.add(root_match.group(1))

    missing = sorted(candidate for candidate in referenced if candidate not in objects)
    check(not missing, f"project file references undefined objects: {missing}")
    note(f"{len(objects)} objects, {len(referenced)} references, 0 dangling"
         if not missing else f"{len(missing)} dangling references")

    isas = {}
    for identifier, body in objects.items():
        isa = object_value(body, "isa")
        isas.setdefault(isa, []).append(identifier)

    required_isas = [
        "PBXProject", "PBXNativeTarget", "PBXFileReference", "PBXBuildFile",
        "PBXGroup", "PBXSourcesBuildPhase", "PBXResourcesBuildPhase",
        "PBXFrameworksBuildPhase", "PBXCopyFilesBuildPhase",
        "PBXTargetDependency", "PBXContainerItemProxy",
        "XCBuildConfiguration", "XCConfigurationList",
    ]
    for isa in required_isas:
        check(isa in isas, f"project file has no {isa} object")

    # --- targets ---------------------------------------------------------
    targets = {}
    for identifier in isas.get("PBXNativeTarget", []):
        body = objects[identifier]
        name = object_value(body, "name")
        targets[name] = (identifier, body)

    check("CustomKeyboard" in targets, "no host application target named CustomKeyboard")
    check("CustomKeyboardExtension" in targets, "no keyboard extension target named CustomKeyboardExtension")
    if "CustomKeyboard" not in targets or "CustomKeyboardExtension" not in targets:
        return objects

    app_id, app_body = targets["CustomKeyboard"]
    ext_id, ext_body = targets["CustomKeyboardExtension"]

    check(object_value(app_body, "productType") == '"com.apple.product-type.application"',
          "host target is not an application")
    check(object_value(ext_body, "productType") == '"com.apple.product-type.app-extension"',
          "extension target is not an app extension")

    # --- products --------------------------------------------------------
    app_product_ref = object_value(app_body, "productReference")
    ext_product_ref = object_value(ext_body, "productReference")
    check(app_product_ref in objects, "host product reference is missing")
    check(ext_product_ref in objects, "extension product reference is missing")
    if app_product_ref in objects:
        check(object_value(objects[app_product_ref], "path") == APP_PRODUCT,
              f"host product is not {APP_PRODUCT}")
    if ext_product_ref in objects:
        check(object_value(objects[ext_product_ref], "path") == EXT_PRODUCT,
              f"extension product is not {EXT_PRODUCT}")
        check(object_value(objects[ext_product_ref], "explicitFileType") == '"wrapper.app-extension"',
              "extension product is not an app extension bundle")

    # --- embed phase -----------------------------------------------------
    embed_phases = [
        (identifier, objects[identifier])
        for identifier in isas.get("PBXCopyFilesBuildPhase", [])
    ]
    app_phases = object_list(app_body, "buildPhases")
    embed_in_app = [phase for phase in embed_phases if phase[0] in app_phases]
    check(len(embed_in_app) == 1, "host target does not have exactly one copy-files phase")
    if embed_in_app:
        identifier, body = embed_in_app[0]
        check(object_value(body, "dstSubfolderSpec") == "13",
              "host copy-files phase is not an Embed App Extensions phase (dstSubfolderSpec 13)")
        check(object_value(body, "name") == '"Embed App Extensions"',
              "host copy-files phase is not named Embed App Extensions")
        files = object_list(body, "files")
        embedded_refs = [
            object_value(objects[build_file], "fileRef")
            for build_file in files if build_file in objects
        ]
        check(ext_product_ref in embedded_refs,
              "the keyboard extension product is NOT embedded in the host app")
        note(f"embed phase {identifier}: {len(files)} embedded product(s)")

    # --- dependency ------------------------------------------------------
    dependencies = object_list(app_body, "dependencies")
    check(bool(dependencies), "host target has no dependency on the extension target")
    dependency_targets = []
    for dependency in dependencies:
        if dependency in objects:
            dependency_targets.append(object_value(objects[dependency], "target"))
    check(ext_id in dependency_targets, "host target does not depend on the keyboard extension target")

    # --- sources membership ---------------------------------------------
    def sources_in(target_body):
        paths = set()
        for phase in object_list(target_body, "buildPhases"):
            body = objects.get(phase, "")
            if object_value(body, "isa") != "PBXSourcesBuildPhase":
                continue
            for build_file in object_list(body, "files"):
                file_ref = object_value(objects.get(build_file, ""), "fileRef")
                reference = objects.get(file_ref, "")
                name = object_value(reference, "path")
                if name:
                    paths.add(name.strip('"'))
        return paths

    app_source_names = sources_in(app_body)
    ext_source_names = sources_in(ext_body)

    app_on_disk = collect_swift(APP_DIR)
    ext_on_disk = collect_swift(EXT_DIR)
    shared_on_disk = collect_swift(SHARED_DIR)

    for path in app_on_disk:
        name = os.path.basename(path)
        check(name in app_source_names, f"{path} is not compiled into the host app")
    for path in ext_on_disk:
        name = os.path.basename(path)
        check(name in ext_source_names, f"{path} is not compiled into the keyboard extension")
    for path in shared_on_disk:
        name = os.path.basename(path)
        check(name in app_source_names, f"{path} is missing from the host app target")
        check(name in ext_source_names, f"{path} is missing from the keyboard extension target")

    unexpected_ext = app_source_names & ext_source_names - {os.path.basename(p) for p in shared_on_disk}
    check(not unexpected_ext, f"unexpected shared sources between the targets: {sorted(unexpected_ext)}")

    note(f"host app compiles {len(app_source_names)} sources, extension {len(ext_source_names)} "
         f"({len(shared_on_disk)} shared)")

    # --- resources -------------------------------------------------------
    def resources_in(target_body):
        paths = set()
        for phase in object_list(target_body, "buildPhases"):
            body = objects.get(phase, "")
            if object_value(body, "isa") != "PBXResourcesBuildPhase":
                continue
            for build_file in object_list(body, "files"):
                file_ref = object_value(objects.get(build_file, ""), "fileRef")
                reference = objects.get(file_ref, "")
                name = object_value(reference, "path")
                if name:
                    paths.add(name.strip('"'))
        return paths

    app_resources = resources_in(app_body)
    ext_resources = resources_in(ext_body)
    check("Assets.xcassets" in app_resources, "the app icon asset catalog is not in the host app resources")
    check("default-layouts.json" in ext_resources, "the fallback keyboard JSON is not in the extension resources")

    # --- files belong to groups -----------------------------------------
    all_group_children = set()
    for identifier in isas.get("PBXGroup", []):
        all_group_children.update(object_list(objects[identifier], "children"))
    orphan_refs = [ref for ref in isas.get("PBXFileReference", []) if ref not in all_group_children]
    check(not orphan_refs, f"{len(orphan_refs)} file references are not in any group: {orphan_refs[:5]}")

    # The project root group must not carry a `path` or every relative path breaks.
    project_id = root_match.group(1) if root_match else None
    if project_id and project_id in objects:
        main_group = object_value(objects[project_id], "mainGroup")
        check(object_value(objects.get(main_group, ""), "path") is None,
              "the project's main group has a `path`, which breaks every relative file path")
        check(object_value(objects.get(main_group, ""), "name") is None,
              "the project's main group has a `name`, which Xcode does not write")

    # --- build settings --------------------------------------------------
    config_lists = {
        object_value(objects[targets[name][0]], "buildConfigurationList"): name
        for name in targets
    }
    project_config_list = object_value(objects[project_id], "buildConfigurationList") if project_id else None
    config_lists[project_config_list] = "project"

    for list_id, owner in config_lists.items():
        list_body = objects.get(list_id, "")
        configs = object_list(list_body, "buildConfigurations")
        check(len(configs) == 2, f"{owner} does not have exactly Debug and Release configurations")
        names = {object_value(objects[c], "name") for c in configs if c in objects}
        check(names == {"Debug", "Release"}, f"{owner} configurations are {sorted(names)}, expected Debug and Release")

    def settings_for(target_id):
        merged = {}
        list_id = object_value(objects[target_id], "buildConfigurationList")
        for config in object_list(objects.get(list_id, ""), "buildConfigurations"):
            merged.update(build_settings(objects.get(config, "")))
        return merged

    def settings_all_configs(target_id):
        """Returns {name: settings} for the target."""
        result = {}
        list_id = object_value(objects[target_id], "buildConfigurationList")
        for config in object_list(objects.get(list_id, ""), "buildConfigurations"):
            body = objects.get(config, "")
            result[object_value(body, "name")] = build_settings(body)
        return result

    project_settings = {}
    for config in object_list(objects.get(project_config_list, ""), "buildConfigurations"):
        project_settings.update(build_settings(objects.get(config, "")))

    app_settings = settings_for(app_id)
    ext_settings = settings_for(ext_id)

    check(project_settings.get("SDKROOT") == "iphoneos", "the project does not build against the device SDK")
    check(project_settings.get("TARGETED_DEVICE_FAMILY") == "1", "the project is not iPhone-only (TARGETED_DEVICE_FAMILY=1)")
    check(project_settings.get("SWIFT_VERSION") == "5.0", "the project does not use Swift 5 language mode")
    deployment = project_settings.get("IPHONEOS_DEPLOYMENT_TARGET", "")
    check(deployment.startswith("1"), f"unexpected deployment target {deployment!r}")

    check(app_settings.get("PRODUCT_BUNDLE_IDENTIFIER") == '"$(KEYRA_APP_BUNDLE_ID)"',
          "the host app does not use the shared bundle identifier variable")
    check(ext_settings.get("PRODUCT_BUNDLE_IDENTIFIER") == '"$(KEYRA_EXTENSION_BUNDLE_ID)"',
          "the extension does not use the shared bundle identifier variable")
    check(app_settings.get("CODE_SIGN_ENTITLEMENTS") == "CustomKeyboardApp/CustomKeyboardApp.entitlements",
          "the host app has no entitlements file")
    check(ext_settings.get("CODE_SIGN_ENTITLEMENTS") == "CustomKeyboardExtension/CustomKeyboardExtension.entitlements",
          "the extension has no entitlements file")
    check(ext_settings.get("APPLICATION_EXTENSION_API_ONLY") == "YES",
          "the extension is not built with APPLICATION_EXTENSION_API_ONLY")
    check(ext_settings.get("SKIP_INSTALL") == "YES", "the extension is not marked SKIP_INSTALL")
    def unquoted(value):
        return (value or "").strip('"')

    check(unquoted(app_settings.get("PRODUCT_NAME")) == "CustomKeyboard",
          f"the host product name is {app_settings.get('PRODUCT_NAME')!r}, expected CustomKeyboard")
    check(unquoted(ext_settings.get("PRODUCT_NAME")) == "CustomKeyboardKeyboard",
          f"the extension product name is {ext_settings.get('PRODUCT_NAME')!r}, expected CustomKeyboardKeyboard")
    check(app_settings.get("INFOPLIST_FILE") == "CustomKeyboardApp/Info.plist",
          "the host app does not use its committed Info.plist")
    check(ext_settings.get("INFOPLIST_FILE") == "CustomKeyboardExtension/Info.plist",
          "the extension does not use its committed Info.plist")
    check(app_settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon", "the app icon is not configured")
    check(app_settings.get("ARCHS") == "arm64", "the host app does not target arm64 devices")

    # The Release configuration must produce a device build, never a simulator one.
    # Project-level settings are inherited by the targets, so merge them in.
    for name, target_settings in settings_all_configs(app_id).items():
        settings = {**project_settings, **target_settings}
        check(settings.get("ARCHS") == "arm64", f"host app {name} is not arm64 only")
        check(settings.get("ONLY_ACTIVE_ARCH") in ("NO", "YES"),
              f"host app {name} has an unexpected ONLY_ACTIVE_ARCH value")
        check(settings.get("SDKROOT") == "iphoneos", f"host app {name} does not build for the device SDK")

    # Every $(VAR) used by the project must be defined by the xcconfig.
    xcconfig = read_xcconfig(XCCONFIG)
    check(os.path.exists(XCCONFIG), f"missing {XCCONFIG}")
    for variable in ["KEYRA_APP_BUNDLE_ID", "KEYRA_EXTENSION_BUNDLE_ID", "KEYRA_SHARED_CONTAINER_ID",
                     "KEYRA_MARKETING_VERSION", "KEYRA_BUILD_NUMBER", "KEYRA_BUNDLE_PREFIX",
                     "KEYRA_DISPLAY_NAME", "KEYRA_KEYBOARD_DISPLAY_NAME"]:
        check(variable in xcconfig, f"{XCCONFIG} does not define {variable}")

    # The configuration file must actually be wired into the project.
    base_refs = set()
    for identifier, body in objects.items():
        value = object_value(body, "baseConfigurationReference")
        if value:
            base_refs.add(value)
    check(len(base_refs) == 1, "the project does not use exactly one base configuration file")

    print("  scheme")
    check(os.path.exists(SCHEME), f"missing shared scheme {SCHEME}")
    if os.path.exists(SCHEME):
        with open(SCHEME, "r", encoding="utf-8") as handle:
            scheme = handle.read()
        check(app_id in scheme, "the shared scheme does not reference the host app target")
        check(f'BuildableName="{APP_PRODUCT}"' in scheme,
              "the shared scheme does not build the host app product")
        check('BlueprintName="CustomKeyboard"' in scheme, "the shared scheme's blueprint name is wrong")

    return objects


def validate_plists():
    print("  Info.plist and entitlements")
    app_plist_path = os.path.join(APP_DIR, "Info.plist")
    ext_plist_path = os.path.join(EXT_DIR, "Info.plist")
    app_ent_path = os.path.join(APP_DIR, "CustomKeyboardApp.entitlements")
    ext_ent_path = os.path.join(EXT_DIR, "CustomKeyboardExtension.entitlements")

    for path in [app_plist_path, ext_plist_path, app_ent_path, ext_ent_path]:
        if not check(os.path.exists(path), f"missing {path}"):
            return

    app_plist = read_plist(app_plist_path)
    ext_plist = read_plist(ext_plist_path)
    app_ent = read_plist(app_ent_path)
    ext_ent = read_plist(ext_ent_path)

    check(app_plist.get("CFBundlePackageType") == "APPL", "host app CFBundlePackageType must be APPL")
    check(ext_plist.get("CFBundlePackageType") == "XPC!", "extension CFBundlePackageType must be XPC!")

    for label, plist in [("host app", app_plist), ("extension", ext_plist)]:
        check(plist.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)",
              f"{label} CFBundleIdentifier must use $(PRODUCT_BUNDLE_IDENTIFIER)")
        check(plist.get("CFBundleShortVersionString") == "$(KEYRA_MARKETING_VERSION)",
              f"{label} CFBundleShortVersionString must use the shared version variable")
        check(plist.get("CFBundleVersion") == "$(KEYRA_BUILD_NUMBER)",
              f"{label} CFBundleVersion must use the shared build variable")
        check(plist.get("CFBundleExecutable") == "$(EXECUTABLE_NAME)",
              f"{label} CFBundleExecutable must use $(EXECUTABLE_NAME)")
        check(plist.get("KeyraSharedContainerID") == "$(KEYRA_SHARED_CONTAINER_ID)",
              f"{label} does not expose the App Group identifier")

    extension = ext_plist.get("NSExtension")
    check(isinstance(extension, dict), "the keyboard extension Info.plist has no NSExtension dictionary")
    if isinstance(extension, dict):
        check(extension.get("NSExtensionPointIdentifier") == KEYBOARD_EXTENSION_POINT,
              f"extension point must be {KEYBOARD_EXTENSION_POINT}")
        principal = extension.get("NSExtensionPrincipalClass", "")
        check(principal.endswith(".KeyboardViewController"),
              f"principal class must point at the UIInputViewController subclass, found {principal!r}")
        check(principal.startswith("$(PRODUCT_MODULE_NAME)"),
              "principal class should be module-qualified with $(PRODUCT_MODULE_NAME)")
        attributes = extension.get("NSExtensionAttributes", {})
        check(isinstance(attributes, dict), "NSExtensionAttributes must be a dictionary")
        if isinstance(attributes, dict):
            check(attributes.get("RequestsOpenAccess") is True,
                  "RequestsOpenAccess must be true for shared-container access")
            check("IsASCIICapable" in attributes, "NSExtensionAttributes should declare IsASCIICapable")
            check("PrimaryLanguage" in attributes, "NSExtensionAttributes should declare PrimaryLanguage")

    check(app_plist.get("UILaunchScreen") is not None, "the host app has no UILaunchScreen entry")
    check(app_plist.get("LSRequiresIPhoneOS") is True, "the host app should require iOS")
    orientations = app_plist.get("UISupportedInterfaceOrientations", [])
    check("UIInterfaceOrientationPortrait" in orientations, "the host app should support portrait")
    check("UISupportedInterfaceOrientations~ipad" not in app_plist,
          "the host app should not declare iPad orientations (iPhone-only)")

    app_group_key = "com.apple.security.application-groups"
    app_groups = app_ent.get(app_group_key, [])
    ext_groups = ext_ent.get(app_group_key, [])
    check(app_groups, "the host app declares no App Group")
    check(ext_groups, "the extension declares no App Group")
    check(app_groups == ext_groups,
          "the host app and extension must declare exactly the same App Group identifier")
    for group in app_groups:
        check(group == "$(KEYRA_SHARED_CONTAINER_ID)",
              f"the App Group should use the shared variable, found {group!r}")
    check(len(app_ent) == 1, "the host entitlements should contain only the App Group")

    xcconfig = read_xcconfig(XCCONFIG)
    resolved = expand_xcconfig(xcconfig)
    app_bundle = resolved.get("KEYRA_APP_BUNDLE_ID", "")
    ext_bundle = resolved.get("KEYRA_EXTENSION_BUNDLE_ID", "")
    container = resolved.get("KEYRA_SHARED_CONTAINER_ID", "")
    note(f"app bundle id        : {app_bundle}")
    note(f"extension bundle id  : {ext_bundle}")
    note(f"app group            : {container}")

    for label, value in [("app bundle id", app_bundle), ("extension bundle id", ext_bundle),
                         ("app group", container)]:
        check("$(" not in value, f"the {label} still contains an unexpanded variable: {value!r}")
        check(value.count(".") >= 2, f"the {label} does not look like an identifier: {value!r}")

    check(ext_bundle.startswith(app_bundle + "."),
          "the extension bundle identifier must be prefixed by the host app's identifier")
    check(container.startswith("group."),
          "an App Group identifier must start with group.")
    check(app_bundle.endswith("CustomKeyboard"),
          "the host app bundle identifier should end in CustomKeyboard")
    check(container == f"group.{app_bundle}",
          "the App Group should be group.<host app bundle id>")


def validate_resources():
    print("  resources")
    icon_dir = os.path.join(APP_DIR, "Assets.xcassets", "AppIcon.appiconset")
    contents_path = os.path.join(icon_dir, "Contents.json")
    icon_path = os.path.join(icon_dir, "AppIcon-1024.png")

    check(os.path.exists(os.path.join(APP_DIR, "Assets.xcassets", "Contents.json")),
          "the asset catalog has no root Contents.json")
    check(os.path.exists(contents_path), "the app icon set has no Contents.json")
    check(os.path.exists(icon_path), "the 1024pt app icon PNG is missing")

    if os.path.exists(contents_path):
        with open(contents_path, "r", encoding="utf-8") as handle:
            contents = json.load(handle)
        images = contents.get("images", [])
        check(len(images) == 1, "the app icon set should contain exactly one single-size image")
        if images:
            check(images[0].get("filename") == "AppIcon-1024.png", "the app icon filename changed")
            check(images[0].get("size") == "1024x1024", "the app icon must be 1024x1024")

    if os.path.exists(icon_path):
        size = png_size(icon_path)
        check(size is not None, "the app icon is not a valid PNG")
        if size:
            width, height, depth, colour = size
            check((width, height) == (1024, 1024), f"the app icon is {width}x{height}, expected 1024x1024")
            check(depth == 8, "the app icon should be 8 bits per channel")
            check(colour == 2, "the app icon must not have an alpha channel (PNG colour type 2)")
            note(f"app icon             : {width}x{height}, {depth}-bit, colour type {colour}")

    # The shipped fallback keyboard must match the model's schema.
    fallback_path = os.path.join(EXT_DIR, "ExtensionResources", "default-layouts.json")
    if check(os.path.exists(fallback_path), "the extension's fallback keyboard JSON is missing"):
        with open(fallback_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        check(payload.get("kind") == "layout", "the fallback JSON should be a layout envelope")
        layout = payload.get("layout", {})
        rows = layout.get("rows", [])
        check(isinstance(rows, list) and rows, "the fallback keyboard has no rows")
        key_count = 0
        actions = set()
        for row_index, row in enumerate(rows):
            check(isinstance(row, dict), f"fallback row {row_index} is not an object")
            keys = row.get("keys") if isinstance(row, dict) else None
            check(isinstance(keys, list) and keys, f"fallback row {row_index} has no keys")
            for key in keys or []:
                key_count += 1
                action = key.get("action")
                check(isinstance(action, dict), f"fallback key {key.get('label')!r} has no action object")
                if isinstance(action, dict):
                    actions.add(action.get("type"))
                    check(isinstance(action.get("type"), str),
                          f"fallback key {key.get('label')!r} has no action type")
        check(key_count > 30, "the fallback keyboard looks too small to be useful")
        for required in ["insertText", "shift", "space", "backspace", "newline", "nextKeyboard"]:
            check(required in actions, f"the fallback keyboard has no {required} action")
        for key in [k for row in rows for k in row.get("keys", [])]:
            width = key.get("width", 1)
            check(isinstance(width, (int, float)) and width > 0,
                  f"fallback key {key.get('label')!r} has an invalid width")
        note(f"fallback keyboard    : {len(rows)} rows, {key_count} keys, actions {sorted(a for a in actions if a)}")


def validate_xcodeproj_files():
    print("  project bundle contents")
    for relative in [
        os.path.join(PROJECT_DIR, "project.xcworkspace", "contents.xcworkspacedata"),
    ]:
        check(os.path.exists(relative), f"missing {relative}")

    for path in [
        os.path.join(APP_DIR, "Info.plist"),
        os.path.join(EXT_DIR, "Info.plist"),
        os.path.join(EXT_DIR, "ExtensionResources", "default-layouts.json"),
    ]:
        check(os.path.exists(path), f"missing {path}")


def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(project_root)

    print("Keyra project validation")
    print(f"  working directory: {project_root}")

    validate_xcodeproj_files()
    validate_project_file()
    validate_plists()
    validate_resources()

    print("")
    if failures:
        print(f"FAILED: {len(failures)} problem(s) out of {checks} checks")
        for problem in failures:
            print(f"  - {problem}")
        return 1
    print(f"OK: {checks} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
