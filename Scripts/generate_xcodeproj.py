#!/usr/bin/env python3
"""Generate CustomKeyboard.xcodeproj deterministically.

Why a generator instead of a hand-written project file:

* object identifiers are derived from a counter, so the file is byte-for-byte
  reproducible and reviews are meaningful,
* every Swift file under the three source directories is picked up
  automatically, so a new file can never be forgotten in the project,
* the host app / keyboard extension target membership rules are declared once,
  explicitly, in this script.

Run it after adding, renaming or deleting a source file:

    python Scripts/generate_xcodeproj.py

Then verify with:

    python Scripts/validate_project.py
"""

from __future__ import annotations

import os
import sys

PROJECT_NAME = "CustomKeyboard"
PROJECT_DIR = f"{PROJECT_NAME}.xcodeproj"

APP_TARGET = "CustomKeyboard"
APP_PRODUCT = "CustomKeyboard.app"
APP_MODULE = "CustomKeyboardApp"

EXT_TARGET = "CustomKeyboardExtension"
EXT_PRODUCT = "CustomKeyboardKeyboard.appex"
EXT_MODULE = "CustomKeyboardExtension"

# Paths are normalised so the generator behaves identically on Windows and macOS.
CONFIG_FILE = os.path.normpath("Config/Keyra.xcconfig")

APP_SOURCE_DIR = "CustomKeyboardApp"
EXT_SOURCE_DIR = "CustomKeyboardExtension"
SHARED_SOURCE_DIR = "Shared"

APP_ASSETS = os.path.normpath("CustomKeyboardApp/Assets.xcassets")
EXT_RESOURCES = [os.path.normpath("CustomKeyboardExtension/ExtensionResources/default-layouts.json")]

DEPLOYMENT_TARGET = "16.0"
SWIFT_VERSION = "5.0"
OBJECT_VERSION = 56
COMPATIBILITY_VERSION = "Xcode 14.0"
UPGRADE_CHECK = "1600"

PROJECT_SETTINGS_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": SWIFT_VERSION,
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "TARGETED_DEVICE_FAMILY": "1",
}

PROJECT_SETTINGS_DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}

PROJECT_SETTINGS_RELEASE = {
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "ONLY_ACTIVE_ARCH": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
}

APP_COMMON = {
    "ARCHS": "arm64",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "CustomKeyboardApp/CustomKeyboardApp.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "$(KEYRA_BUILD_NUMBER)",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "CustomKeyboardApp/Info.plist",
    "MARKETING_VERSION": "$(KEYRA_MARKETING_VERSION)",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(KEYRA_APP_BUNDLE_ID)",
    "PRODUCT_MODULE_NAME": APP_MODULE,
    "PRODUCT_NAME": APP_TARGET,
    "SWIFT_EMIT_LOC_STRINGS": "NO",
}

EXT_COMMON = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "ARCHS": "arm64",
    "CODE_SIGN_ENTITLEMENTS": "CustomKeyboardExtension/CustomKeyboardExtension.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "$(KEYRA_BUILD_NUMBER)",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "CustomKeyboardExtension/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "MARKETING_VERSION": "$(KEYRA_MARKETING_VERSION)",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(KEYRA_EXTENSION_BUNDLE_ID)",
    "PRODUCT_MODULE_NAME": EXT_MODULE,
    "PRODUCT_NAME": "CustomKeyboardKeyboard",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
}


class IdentifierFactory:
    """Deterministic 24-character hex object identifiers."""

    def __init__(self, prefix="CA11AB1E"):
        self.prefix = prefix
        self.counter = 0

    def next(self):
        self.counter += 1
        return f"{self.prefix}{self.counter:016X}"


class Project:
    def __init__(self, root):
        self.root = root
        self.ids = IdentifierFactory()
        self.objects = []          # list of (identifier, body-string)
        self.file_refs = {}        # relative path -> identifier
        self.groups = {}           # relative directory -> identifier

        self.project_id = self.ids.next()
        self.main_group_id = self.ids.next()
        self.products_group_id = self.ids.next()
        self.config_group_id = self.ids.next()
        self.config_file_ref = None
        self.product_refs = {}

    # -- helpers ---------------------------------------------------------

    def add(self, identifier, body):
        self.objects.append((identifier, body))
        return identifier

    def quote(self, value):
        if isinstance(value, bool):
            return "YES" if value else "NO"
        if isinstance(value, list):
            inner = ", ".join(self.quote(item) for item in value)
            return f"({inner})"
        text = str(value)
        safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./$@"
        if text == "" or any(char not in safe for char in text):
            escaped = text.replace("\\", "\\\\").replace('"', '\\"')
            return f'"{escaped}"'
        return text

    def settings_block(self, settings, indent):
        lines = []
        pad = "\t" * indent
        for key in sorted(settings):
            lines.append(f"{pad}{self.quote(key)} = {self.quote(settings[key])};")
        return "\n".join(lines)

    def file_ref(self, path, file_type, source_tree="<group>"):
        if path in self.file_refs:
            return self.file_refs[path]
        identifier = self.ids.next()
        name = os.path.basename(path)
        self.add(identifier, (
            "{\n"
            f"\t\t\tisa = PBXFileReference;\n"
            f"\t\t\tlastKnownFileType = {file_type};\n"
            f"\t\t\tpath = {self.quote(name)};\n"
            f"\t\t\tsourceTree = \"{source_tree}\";\n"
            "\t\t}"
        ))
        self.file_refs[path] = identifier
        return identifier

    def ensure_group(self, directory):
        """Creates (recursively) the PBXGroup chain for a directory path."""
        if directory in ("", "."):
            return self.main_group_id
        if directory in self.groups:
            return self.groups[directory]

        parent = self.ensure_group(os.path.dirname(directory))
        identifier = self.ids.next()
        name = os.path.basename(directory)
        self.groups[directory] = identifier

        # The placeholder group object is filled in later, once children are known.
        self.add(identifier, ("GROUP:" + directory))
        self.pending_children = getattr(self, "pending_children", {})
        self.pending_children.setdefault(parent, []).append((None, identifier, name))
        return identifier

    # -- build -----------------------------------------------------------

    def build(self):
        app_sources = collect_swift([APP_SOURCE_DIR])
        ext_sources = collect_swift([EXT_SOURCE_DIR])
        shared_sources = collect_swift([SHARED_SOURCE_DIR])
        shared_rendering = sorted(p for p in shared_sources if os.sep.join(["Shared", "Rendering"]) in p)
        shared_core = [p for p in shared_sources if p not in shared_rendering]

        self.pending_children = {}
        self.children = {}

        # Groups + file references ---------------------------------------
        self.config_file_ref = self.file_ref(CONFIG_FILE, "text.xcconfig")
        for path in app_sources + ext_sources + shared_sources:
            self.file_ref(path, "sourcecode.swift")
        self.file_ref(APP_ASSETS, "folder.assetcatalog")
        for path in EXT_RESOURCES:
            self.file_ref(path, "text.json")

        # Products
        app_product_id = self.project_product_ref(APP_PRODUCT, "wrapper.application")
        ext_product_id = self.project_product_ref(EXT_PRODUCT, "wrapper.app-extension")

        # Register directories
        for path in app_sources + ext_sources + shared_sources + [APP_ASSETS] + EXT_RESOURCES:
            self.ensure_group(os.path.dirname(path))
        self.ensure_group(os.path.dirname(CONFIG_FILE))

        # Sources build phases -------------------------------------------
        app_source_build_files = []
        for path in sorted(app_sources + shared_core + shared_rendering):
            app_source_build_files.append(self.build_file(self.file_refs[path], os.path.basename(path)))

        ext_source_build_files = []
        for path in sorted(ext_sources + shared_core + shared_rendering):
            ext_source_build_files.append(self.build_file(self.file_refs[path], os.path.basename(path)))

        app_resources_phase = self.resources_phase([self.build_file(self.file_refs[APP_ASSETS], "Assets.xcassets")])
        ext_resources_phase = self.resources_phase(
            [self.build_file(self.file_refs[path], os.path.basename(path)) for path in EXT_RESOURCES]
        )

        app_sources_phase = self.sources_phase(app_source_build_files)
        ext_sources_phase = self.sources_phase(ext_source_build_files)

        app_frameworks_phase = self.frameworks_phase()
        ext_frameworks_phase = self.frameworks_phase()

        # Extension target must exist before it can be embedded -------------
        ext_target_id = self.ids.next()
        self.product_refs[EXT_TARGET] = (ext_product_id, EXT_PRODUCT)

        embed_phase, embed_file = self.embed_app_extensions_phase(ext_product_id, EXT_PRODUCT)
        proxy_id = self.ids.next()
        dependency_id = self.ids.next()

        app_target_id = self.ids.next()
        self.product_refs[APP_TARGET] = (app_product_id, APP_PRODUCT)

        app_config_list = self.configuration_list(
            f"Build configuration list for PBXNativeTarget \"{APP_TARGET}\"",
            {**APP_COMMON, "PRODUCT_NAME": APP_TARGET},
            EXTRA_APP_DEBUG,
            EXTRA_APP_RELEASE,
        )
        ext_config_list = self.configuration_list(
            f"Build configuration list for PBXNativeTarget \"{EXT_TARGET}\"",
            EXT_COMMON,
            {},
            {},
        )
        project_config_list = self.configuration_list(
            f"Build configuration list for PBXProject \"{PROJECT_NAME}\"",
            PROJECT_SETTINGS_COMMON,
            PROJECT_SETTINGS_DEBUG,
            PROJECT_SETTINGS_RELEASE,
        )

        # Targets ---------------------------------------------------------
        self.add(app_target_id, (
            "{\n"
            "\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {app_config_list};\n"
            "\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{app_sources_phase},\n"
            f"\t\t\t\t{app_frameworks_phase},\n"
            f"\t\t\t\t{app_resources_phase},\n"
            f"\t\t\t\t{embed_phase},\n"
            "\t\t\t);\n"
            "\t\t\tbuildRules = (\n\t\t\t);\n"
            f"\t\t\tdependencies = (\n\t\t\t\t{dependency_id},\n\t\t\t);\n"
            f"\t\t\tname = {APP_TARGET};\n"
            f"\t\t\tproductName = {APP_TARGET};\n"
            f"\t\t\tproductReference = {app_product_id};\n"
            "\t\t\tproductType = \"com.apple.product-type.application\";\n"
            "\t\t}"
        ))

        self.add(ext_target_id, (
            "{\n"
            "\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {ext_config_list};\n"
            "\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{ext_sources_phase},\n"
            f"\t\t\t\t{ext_frameworks_phase},\n"
            f"\t\t\t\t{ext_resources_phase},\n"
            "\t\t\t);\n"
            "\t\t\tbuildRules = (\n\t\t\t);\n"
            "\t\t\tdependencies = (\n\t\t\t);\n"
            f"\t\t\tname = {EXT_TARGET};\n"
            f"\t\t\tproductName = {EXT_TARGET};\n"
            f"\t\t\tproductReference = {ext_product_id};\n"
            "\t\t\tproductType = \"com.apple.product-type.app-extension\";\n"
            "\t\t}"
        ))

        self.add(dependency_id, (
            "{\n"
            "\t\t\tisa = PBXTargetDependency;\n"
            f"\t\t\ttarget = {ext_target_id};\n"
            f"\t\t\ttargetProxy = {proxy_id};\n"
            "\t\t}"
        ))
        self.add(proxy_id, (
            "{\n"
            "\t\t\tisa = PBXContainerItemProxy;\n"
            f"\t\t\tcontainerPortal = {self.project_id};\n"
            "\t\t\tproxyType = 1;\n"
            f"\t\t\tremoteGlobalIDString = {ext_target_id};\n"
            f"\t\t\tremoteInfo = {EXT_TARGET};\n"
            "\t\t}"
        ))
        # Project ---------------------------------------------------------
        self.add(self.project_id, (
            "{\n"
            "\t\t\tisa = PBXProject;\n"
            "\t\t\tattributes = {\n"
            "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
            f"\t\t\t\tLastSwiftUpdateCheck = {UPGRADE_CHECK};\n"
            f"\t\t\t\tLastUpgradeCheck = {UPGRADE_CHECK};\n"
            "\t\t\t\tORGANIZATIONNAME = Keyra;\n"
            "\t\t\t\tTargetAttributes = {\n"
            f"\t\t\t\t\t{app_target_id} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
            f"\t\t\t\t\t{ext_target_id} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
            "\t\t\t\t};\n"
            "\t\t\t};\n"
            f"\t\t\tbuildConfigurationList = {project_config_list};\n"
            f"\t\t\tcompatibilityVersion = \"{COMPATIBILITY_VERSION}\";\n"
            "\t\t\tdevelopmentRegion = en;\n"
            "\t\t\thasScannedForEncodings = 0;\n"
            "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
            f"\t\t\tmainGroup = {self.main_group_id};\n"
            f"\t\t\tproductRefGroup = {self.products_group_id};\n"
            "\t\t\tprojectDirPath = \"\";\n"
            "\t\t\tprojectRoot = \"\";\n"
            "\t\t\ttargets = (\n"
            f"\t\t\t\t{app_target_id},\n"
            f"\t\t\t\t{ext_target_id},\n"
            "\t\t\t);\n"
            "\t\t}"
        ))

        # Groups ----------------------------------------------------------
        # The main group deliberately has no `path`: it is the project directory.
        self.add(self.main_group_id, self.group_body(
            [self.ensure_group(APP_SOURCE_DIR), self.ensure_group(EXT_SOURCE_DIR), self.ensure_group(SHARED_SOURCE_DIR), self.config_group_id, self.products_group_id]
        ))
        self.add(self.config_group_id, self.group_body([self.config_file_ref], path=os.path.dirname(CONFIG_FILE)))
        self.add(self.products_group_id, self.group_body([app_product_id, ext_product_id], name="Products"))

        for directory, identifier in self.groups.items():
            if not directory:
                continue
            child_ids = [child_id for (_, child_id, _) in self.pending_children.get(identifier, [])]
            direct_files = [
                path for path in self.file_refs
                if os.path.dirname(path) == directory and os.path.basename(path) != os.path.basename(directory)
            ]
            child_ids.extend(self.file_refs[path] for path in sorted(direct_files))
            self.add(identifier, self.group_body(child_ids, path=os.path.basename(directory)))

        return self.render()

    # -- object builders -------------------------------------------------

    def project_product_ref(self, product, file_type):
        identifier = self.ids.next()
        self.add(identifier, (
            "{\n"
            "\t\t\tisa = PBXFileReference;\n"
            f"\t\t\texplicitFileType = {self.quote(file_type)};\n"
            "\t\t\tincludeInIndex = 0;\n"
            f"\t\t\tpath = {self.quote(product)};\n"
            "\t\t\tsourceTree = BUILT_PRODUCTS_DIR;\n"
            "\t\t}"
        ))
        return identifier

    def build_file(self, file_ref, name):
        identifier = self.ids.next()
        self.add(identifier, (
            "{\n"
            "\t\t\tisa = PBXBuildFile;\n"
            f"\t\t\tfileRef = {file_ref};\n"
            "\t\t}"
        ))
        return identifier

    def sources_phase(self, file_ids):
        identifier = self.ids.next()
        lines = "\n".join(f"\t\t\t\t{item} /* in Sources */," for item in file_ids)
        self.add(identifier, (
            "{\n"
            "\t\t\tisa = PBXSourcesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n"
            f"{lines}\n"
            "\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t}"
        ))
        return identifier

    def resources_phase(self, file_ids):
        identifier = self.ids.next()
        lines = "\n".join(f"\t\t\t\t{item} /* in Resources */," for item in file_ids)
        self.add(identifier, (
            "{\n"
            "\t\t\tisa = PBXResourcesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n"
            f"{lines}\n"
            "\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t}"
        ))
        return identifier

    def frameworks_phase(self):
        identifier = self.ids.next()
        self.add(identifier, (
            "{\n"
            "\t\t\tisa = PBXFrameworksBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t}"
        ))
        return identifier

    def embed_app_extensions_phase(self, appex_ref, name):
        file_id = self.ids.next()
        phase_id = self.ids.next()
        self.add(file_id, (
            "{\n"
            "\t\t\tisa = PBXBuildFile;\n"
            f"\t\t\tfileRef = {appex_ref};\n"
            "\t\t\tsettings = {\n"
            "\t\t\t\tATTRIBUTES = (\n"
            "\t\t\t\t\tRemoveHeadersOnCopy,\n"
            "\t\t\t\t);\n"
            "\t\t\t};\n"
            "\t\t}"
        ))
        self.add(phase_id, (
            "{\n"
            "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tdstPath = \"\";\n"
            "\t\t\tdstSubfolderSpec = 13;\n"
            "\t\t\tfiles = (\n"
            f"\t\t\t\t{file_id} /* {name} in Embed App Extensions */,\n"
            "\t\t\t);\n"
            "\t\t\tname = \"Embed App Extensions\";\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t}"
        ))
        return phase_id, file_id

    def configuration_list(self, comment, common, debug_extra, release_extra):
        debug_settings = {**common, **debug_extra}
        release_settings = {**common, **release_extra}

        debug_id = self.ids.next()
        release_id = self.ids.next()
        list_id = self.ids.next()

        self.add(debug_id, self.configuration_body("Debug", debug_settings))
        self.add(release_id, self.configuration_body("Release", release_settings))
        self.add(list_id, (
            "{\n"
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{debug_id} /* Debug */,\n"
            f"\t\t\t\t{release_id} /* Release */,\n"
            "\t\t\t);\n"
            "\t\t\tdefaultConfigurationIsVisible = 0;\n"
            "\t\t\tdefaultConfigurationName = Release;\n"
            "\t\t}"
        ))
        return list_id

    def configuration_body(self, name, settings):
        body = (
            "{\n"
            "\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbaseConfigurationReference = " + str(self.config_file_ref) + ";\n"
            "\t\t\tbuildSettings = {\n"
            + self.settings_block(settings, 4) + "\n"
            "\t\t\t};\n"
            f"\t\t\tname = {name};\n"
            "\t\t}"
        )
        return body

    def group_body(self, children, path=None, name=None):
        lines = "\n".join(f"\t\t\t\t{item}," for item in children if item)
        body = (
            "{\n"
            "\t\t\tisa = PBXGroup;\n"
            "\t\t\tchildren = (\n"
            f"{lines}\n"
            "\t\t\t);\n"
        )
        if name:
            body += f"\t\t\tname = {self.quote(name)};\n"
        if path:
            body += f"\t\t\tpath = {self.quote(path)};\n"
        body += "\t\t\tsourceTree = \"<group>\";\n\t\t}"
        return body

    # -- output ----------------------------------------------------------

    def render(self):
        sections = [
            "PBXBuildFile",
            "PBXContainerItemProxy",
            "PBXCopyFilesBuildPhase",
            "PBXFileReference",
            "PBXFrameworksBuildPhase",
            "PBXGroup",
            "PBXNativeTarget",
            "PBXProject",
            "PBXResourcesBuildPhase",
            "PBXSourcesBuildPhase",
            "PBXTargetDependency",
            "XCBuildConfiguration",
            "XCConfigurationList",
        ]
        by_isa = {name: [] for name in sections}
        for identifier, body in self.objects:
            if body.startswith("GROUP:"):
                continue
            isa = body.split("isa = ", 1)[1].split(";", 1)[0]
            by_isa.setdefault(isa, []).append((identifier, body))

        out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
               f"\tobjectVersion = {OBJECT_VERSION};", "\tobjects = {"]

        for section in sections:
            entries = by_isa.get(section, [])
            if not entries:
                continue
            out.append(f"\n/* Begin {section} section */")
            for identifier, body in sorted(entries, key=lambda pair: pair[0]):
                out.append(f"\t\t{identifier} = {body};")
            out.append(f"/* End {section} section */")

        out.append("\t};")
        out.append(f"\trootObject = {self.project_id};")
        out.append("}")
        return "\n".join(out) + "\n"


EXTRA_APP_DEBUG = {}
EXTRA_APP_RELEASE = {}


def collect_swift(directories):
    found = []
    for directory in directories:
        for root, dirs, files in os.walk(directory):
            dirs[:] = sorted(d for d in dirs if not d.startswith("."))
            for name in sorted(files):
                if name.endswith(".swift"):
                    found.append(os.path.normpath(os.path.join(root, name)))
    return sorted(found)


def scheme_xml(app_target_id):
    reference = (
        f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target_id}" '
        f'BuildableName="{APP_PRODUCT}" BlueprintName="{APP_TARGET}" '
        f'ReferencedContainer="container:{PROJECT_DIR}"/>'
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "{UPGRADE_CHECK}" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {reference}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


WORKSPACE_XML = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "self:">
   </FileRef>
</Workspace>
"""


def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(project_root)

    if not os.path.isdir(APP_SOURCE_DIR) or not os.path.isdir(EXT_SOURCE_DIR):
        print("error: run this from the repository root (CustomKeyboardApp/ and CustomKeyboardExtension/ must exist)")
        return 1

    project = Project(project_root)
    pbxproj = project.build()

    os.makedirs(os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes"), exist_ok=True)
    os.makedirs(os.path.join(PROJECT_DIR, "project.xcworkspace"), exist_ok=True)

    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(pbxproj)

    with open(os.path.join(PROJECT_DIR, "project.xcworkspace", "contents.xcworkspacedata"), "w",
              encoding="utf-8", newline="\n") as handle:
        handle.write(WORKSPACE_XML)

    app_target_id = next(
        (identifier for identifier, body in project.objects
         if "isa = PBXNativeTarget" in body and f"name = {APP_TARGET};" in body),
        None,
    )

    with open(os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", f"{PROJECT_NAME}.xcscheme"),
              "w", encoding="utf-8", newline="\n") as handle:
        handle.write(scheme_xml(app_target_id))

    app_sources = collect_swift([APP_SOURCE_DIR])
    ext_sources = collect_swift([EXT_SOURCE_DIR])
    shared_sources = collect_swift([SHARED_SOURCE_DIR])

    print(f"Wrote {PROJECT_DIR}/project.pbxproj")
    print(f"  targets            : {APP_TARGET} (app) -> embeds {EXT_TARGET} ({EXT_PRODUCT})")
    print(f"  app sources        : {len(app_sources)} + {len(shared_sources)} shared")
    print(f"  extension sources  : {len(ext_sources)} + {len(shared_sources)} shared")
    print(f"  scheme             : {PROJECT_NAME}.xcscheme (shared)")
    print(f"  configuration      : {CONFIG_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
