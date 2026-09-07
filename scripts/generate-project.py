#!/usr/bin/env python3
"""Generate a dependency-free Xcode project from the Swift source list."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
files = sorted((root / 'Sources').rglob('*.swift'))
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
objects = []
def obj(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)
refs, builds = [], []
for path in files:
    rel = str(path.relative_to(root))
    refs.append(obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = SOURCE_ROOT;'))
    builds.append(obj('build:' + rel, f'isa = PBXBuildFile; fileRef = {uid(rel)};'))
icon = obj('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = SOURCE_ROOT;')
iconBuild = obj('iconBuild', f'isa = PBXBuildFile; fileRef = {icon};')
resources = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconBuild},); runOnlyForDeploymentPostprocessing = 0;')
refs.append(icon)
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = TotalMixSnapshotTouch.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main = obj('main', f'isa = PBXGroup; children = ({",".join(refs + [products])},); sourceTree = "<group>";')
sources = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
configs = []
for config in ['Debug', 'Release']:
    settings = '''ALWAYS_SEARCH_USER_PATHS = NO; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0; SWIFT_VERSION = 5.0;
    PRODUCT_NAME = TotalMixSnapshotTouch; PRODUCT_BUNDLE_IDENTIFIER = local.seijiro.TotalMixSnapshotTouch;
    GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Resources/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = "TotalMix Snapshot Touch";
    INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.music";
    MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1;
    CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = NO;
    SWIFT_EMIT_LOC_STRINGS = NO; COMBINE_HIDPI_IMAGES = YES;'''
    settings += 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if config == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    configs.append(obj('config:' + config, f'isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {config};'))
configlist = obj('configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = TotalMixSnapshotTouch; productName = TotalMixSnapshotTouch; productReference = {product}; productType = "com.apple.product-type.application";')
project = obj('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2600;}}; buildConfigurationList = {configlist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja,en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
folder = root / 'TotalMixSnapshotTouch.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project};}}\n')
scheme = folder / 'xcshareddata/xcschemes'
scheme.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="TotalMixSnapshotTouch.app" BlueprintName="TotalMixSnapshotTouch" ReferencedContainer="container:TotalMixSnapshotTouch.xcodeproj"/>'
(scheme / 'TotalMixSnapshotTouch.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
