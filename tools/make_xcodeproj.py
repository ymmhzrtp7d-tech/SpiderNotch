"""Generates SpiderNotch.xcodeproj (classic file references, objectVersion 56 / Xcode 14+).

Usage: python3 tools/make_xcodeproj.py .   (run it from the project folder after adding or removing files)
The Install and Make Release scripts don't need the Xcode project: it's only for people who prefer Xcode.
"""
import hashlib, re, sys
from pathlib import Path

root = Path(sys.argv[1])
src = root / "SpiderNotch"
swift_files = sorted(p.name for p in src.glob("*.swift"))
resources = sorted(p.name for p in (src / "Resources").iterdir() if p.is_file() and not p.name.startswith("."))
folders = sorted(p.name for p in (src / "Resources").iterdir() if p.is_dir())
version = (root / "VERSION").read_text().strip() if (root / "VERSION").exists() else "1.0.0"
helper_files = ["SpiderNotchMedia.m", "now-playing.pl"]

def uid(name):
    return hashlib.md5(("SpiderNotch:" + name).encode()).hexdigest()[:24].upper()

def q(v):
    v = str(v)
    return v if re.fullmatch(r"[A-Za-z0-9_./]+", v) else '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'

def settings_block(d, indent):
    pad = "\t" * indent
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            items = "".join(f"{pad}\t{q(x)},\n" for x in v)
            out.append(f"{pad}{k} = (\n{items}{pad});\n")
        else:
            out.append(f"{pad}{k} = {q(v)};\n")
    return "".join(out)

ids = {
    "project": uid("project"), "main": uid("group.main"), "products": uid("group.products"),
    "src": uid("group.src"), "res": uid("group.res"), "app": uid("ref.app"), "info": uid("ref.info"),
    "target": uid("target"), "sources": uid("phase.sources"), "frameworks": uid("phase.frameworks"),
    "resources": uid("phase.resources"), "pconf": uid("conflist.project"), "tconf": uid("conflist.target"),
    "helper": uid("phase.helper"), "mediagroup": uid("group.mediahelper"), "entitlements": uid("ref.entitlements"),
    "pdebug": uid("conf.project.debug"), "prelease": uid("conf.project.release"),
    "tdebug": uid("conf.target.debug"), "trelease": uid("conf.target.release"),
}
fref = {f: uid("ref." + f) for f in swift_files + resources + folders + helper_files}
bfile = {f: uid("build." + f) for f in swift_files + resources + folders + ["now-playing.pl"]}
bundled = resources + folders + ["now-playing.pl"]

L = []
L.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n")

L.append("\n/* Begin PBXBuildFile section */\n")
for f in swift_files:
    L.append(f"\t\t{bfile[f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref[f]} /* {f} */; }};\n")
for f in bundled:
    L.append(f"\t\t{bfile[f]} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref[f]} /* {f} */; }};\n")
L.append("/* End PBXBuildFile section */\n")

L.append("\n/* Begin PBXFileReference section */\n")
L.append(f"\t\t{ids['app']} /* SpiderNotch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SpiderNotch.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
L.append(f"\t\t{ids['info']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};\n")
types = {"png": "image.png", "icns": "image.icns", "json": "text.json"}
L.append(f"\t\t{ids['entitlements']} /* SpiderNotch.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = SpiderNotch.entitlements; sourceTree = \"<group>\"; }};\n")
for f in folders:
    L.append(f"\t\t{fref[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = folder; path = {q(f)}; sourceTree = \"<group>\"; }};\n")
L.append(f"\t\t{fref['SpiderNotchMedia.m']} /* SpiderNotchMedia.m */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = SpiderNotchMedia.m; sourceTree = \"<group>\"; }};\n")
L.append(f"\t\t{fref['now-playing.pl']} /* now-playing.pl */ = {{isa = PBXFileReference; lastKnownFileType = text.script.perl; path = \"now-playing.pl\"; sourceTree = \"<group>\"; }};\n")
for f in swift_files:
    L.append(f"\t\t{fref[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(f)}; sourceTree = \"<group>\"; }};\n")
for f in resources:
    t = types[f.rsplit('.', 1)[1]]
    L.append(f"\t\t{fref[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {q(f)}; sourceTree = \"<group>\"; }};\n")
L.append("/* End PBXFileReference section */\n")

L.append("\n/* Begin PBXFrameworksBuildPhase section */\n")
L.append(f"\t\t{ids['frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
L.append("/* End PBXFrameworksBuildPhase section */\n")

L.append("\n/* Begin PBXGroup section */\n")
L.append(f"\t\t{ids['main']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{ids['src']} /* SpiderNotch */,\n\t\t\t\t{ids['products']} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
L.append(f"\t\t{ids['products']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{ids['app']} /* SpiderNotch.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
children = "".join(f"\t\t\t\t{fref[f]} /* {f} */,\n" for f in swift_files)
children += f"\t\t\t\t{ids['res']} /* Resources */,\n\t\t\t\t{ids['mediagroup']} /* MediaHelper */,\n\t\t\t\t{ids['info']} /* Info.plist */,\n\t\t\t\t{ids['entitlements']} /* SpiderNotch.entitlements */,\n"
L.append(f"\t\t{ids['src']} /* SpiderNotch */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t);\n\t\t\tpath = SpiderNotch;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
rchildren = "".join(f"\t\t\t\t{fref[f]} /* {f} */,\n" for f in resources + folders)
mchildren = "".join(f"\t\t\t\t{fref[f]} /* {f} */,\n" for f in helper_files)
L.append(f"\t\t{ids['mediagroup']} /* MediaHelper */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{mchildren}\t\t\t);\n\t\t\tpath = MediaHelper;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
L.append(f"\t\t{ids['res']} /* Resources */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{rchildren}\t\t\t);\n\t\t\tpath = Resources;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
L.append("/* End PBXGroup section */\n")

L.append("\n/* Begin PBXNativeTarget section */\n")
L.append(f"""\t\t{ids['target']} /* SpiderNotch */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids['tconf']} /* Build configuration list for PBXNativeTarget "SpiderNotch" */;
\t\t\tbuildPhases = (
\t\t\t\t{ids['sources']} /* Sources */,
\t\t\t\t{ids['frameworks']} /* Frameworks */,
\t\t\t\t{ids['resources']} /* Resources */,
\t\t\t\t{ids['helper']} /* Build Now Playing helper */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = SpiderNotch;
\t\t\tproductName = SpiderNotch;
\t\t\tproductReference = {ids['app']} /* SpiderNotch.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
""")
L.append("/* End PBXNativeTarget section */\n")

L.append("\n/* Begin PBXProject section */\n")
L.append(f"""\t\t{ids['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ids['target']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {ids['pconf']} /* Build configuration list for PBXProject "SpiderNotch" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {ids['main']};
\t\t\tproductRefGroup = {ids['products']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ids['target']} /* SpiderNotch */,
\t\t\t);
\t\t}};
""")
L.append("/* End PBXProject section */\n")

L.append("\n/* Begin PBXResourcesBuildPhase section */\n")
rfiles = "".join(f"\t\t\t\t{bfile[f]} /* {f} in Resources */,\n" for f in bundled)
L.append(f"\t\t{ids['resources']} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{rfiles}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
L.append("/* End PBXResourcesBuildPhase section */\n")

L.append("\n/* Begin PBXShellScriptBuildPhase section */\n")
script = 'bash \\"$SRCROOT/scripts/build-media-helper.sh\\" \\"$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH\\" $ARCHS\\n'
L.append(f"""\t\t{ids['helper']} /* Build Now Playing helper */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputFileListPaths = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t\t\"$(SRCROOT)/SpiderNotch/MediaHelper/SpiderNotchMedia.m\",
\t\t\t);
\t\t\tname = \"Build Now Playing helper\";
\t\t\toutputFileListPaths = (
\t\t\t);
\t\t\toutputPaths = (
\t\t\t\t\"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/SpiderNotchMedia.dylib\",
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = \"{script}\";
\t\t}};
""")
L.append("/* End PBXShellScriptBuildPhase section */\n")
L.append("\n/* Begin PBXSourcesBuildPhase section */\n")
sfiles = "".join(f"\t\t\t\t{bfile[f]} /* {f} in Sources */,\n" for f in swift_files)
L.append(f"\t\t{ids['sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{sfiles}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
L.append("/* End PBXSourcesBuildPhase section */\n")

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
}
pdebug = dict(common, **{
    "COPY_PHASE_STRIP": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
prelease = dict(common, **{
    "COPY_PHASE_STRIP": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O",
})
target = {
    "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Automatic", "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1", "DEVELOPMENT_TEAM": "", "ENABLE_HARDENED_RUNTIME": "NO",
    "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "SpiderNotch/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "MACOSX_DEPLOYMENT_TARGET": "14.0", "MARKETING_VERSION": version, "CODE_SIGN_ENTITLEMENTS": "SpiderNotch/SpiderNotch.entitlements",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.huang.SpiderNotch", "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO", "SWIFT_VERSION": "5.0",
}
L.append("\n/* Begin XCBuildConfiguration section */\n")
for key, name, d in (("pdebug", "Debug", pdebug), ("prelease", "Release", prelease),
                     ("tdebug", "Debug", target), ("trelease", "Release", target)):
    L.append(f"\t\t{ids[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_block(d, 4)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")
L.append("/* End XCBuildConfiguration section */\n")

L.append("\n/* Begin XCConfigurationList section */\n")
for key, owner, dbg, rel in (("pconf", 'PBXProject "SpiderNotch"', "pdebug", "prelease"),
                             ("tconf", 'PBXNativeTarget "SpiderNotch"', "tdebug", "trelease")):
    L.append(f"\t\t{ids[key]} /* Build configuration list for {owner} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{ids[dbg]} /* Debug */,\n\t\t\t\t{ids[rel]} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
L.append("/* End XCConfigurationList section */\n")
L.append(f"\t}};\n\trootObject = {ids['project']} /* Project object */;\n}}\n")

proj = root / "SpiderNotch.xcodeproj"
(proj / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
(proj / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
(proj / "project.pbxproj").write_text("".join(L))
(proj / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
ref = (f'BuildableIdentifier = "primary"\n               BlueprintIdentifier = "{ids["target"]}"\n'
       f'               BuildableName = "SpiderNotch.app"\n               BlueprintName = "SpiderNotch"\n'
       f'               ReferencedContainer = "container:SpiderNotch.xcodeproj"')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               {ref}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            {ref.replace("               ", "            ")}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            {ref.replace("               ", "            ")}>
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
(proj / "xcshareddata" / "xcschemes" / "SpiderNotch.xcscheme").write_text(scheme)
print("swift files:", swift_files)
print("written", proj)
