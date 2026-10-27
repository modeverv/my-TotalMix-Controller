#!/usr/bin/env python3
"""Generate the dependency-free macOS/iOS Xcode project and shared schemes."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
objects = []


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def obj(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)


def configuration_list(name, settings):
    configs = []
    for config in ['Debug', 'Release']:
        optimization = ('SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; '
                        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;') if config == 'Debug' else (
                        'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        configs.append(obj(f'{name}:{config}', f'isa = XCBuildConfiguration; buildSettings = {{{settings}{optimization}}}; name = {config};'))
    return obj(name, f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')


file_refs = {}


def file_ref(path, kind='sourcecode.swift'):
    rel = str(path.relative_to(root)) if isinstance(path, Path) else path
    if rel not in file_refs:
        file_refs[rel] = obj(rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{rel}"; sourceTree = SOURCE_ROOT;')
    return file_refs[rel]


def phase(name, kind, paths):
    builds = []
    for path in paths:
        relative = str(path.relative_to(root)) if isinstance(path, Path) else path
        builds.append(obj(f'build:{name}:{relative}', f'isa = PBXBuildFile; fileRef = {file_ref(path)};'))
    return obj(name, f'isa = {kind}; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')


mac_files = sorted((root / 'Sources').rglob('*.swift'))
shared_files = [path for path in mac_files if any(part in path.parts for part in ['Models', 'OSC', 'Persistence'])]
ios_files = shared_files + sorted((root / 'iOS').rglob('*.swift'))
test_files = sorted((root / 'iOSUITests').glob('*.swift'))
# Keep the test target available before a fresh checkout's test source is generated.
if not test_files:
    test_files = [root / 'iOSUITests/TotalMixSnapshotTouchIOSTests.swift']
file_ref('Resources/AppIcon.icns', 'image.icns')
file_ref('iOS/Assets.xcassets', 'folder.assetcatalog')
file_ref('Resources/Info.plist', 'text.plist.xml')
file_ref('iOS/Info.plist', 'text.plist.xml')

common = '''ALWAYS_SEARCH_USER_PATHS = NO; SWIFT_VERSION = 5.0;
    CLANG_ENABLE_MODULES = YES; SWIFT_EMIT_LOC_STRINGS = NO;
    MARKETING_VERSION = 1.1; CURRENT_PROJECT_VERSION = 2;
'''
project_configs = configuration_list('project-configs', common)
mac_settings = '''SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0;
    PRODUCT_NAME = TotalMixSnapshotTouch; PRODUCT_BUNDLE_IDENTIFIER = local.seijiro.TotalMixSnapshotTouch;
    GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Resources/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = "TotalMix Snapshot Touch";
    INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.music";
    CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = NO;
    COMBINE_HIDPI_IMAGES = YES;
'''
ios_settings = '''SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0;
    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = "1,2";
    SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
    PRODUCT_NAME = TotalMixSnapshotTouchIOS; PRODUCT_BUNDLE_IDENTIFIER = local.seijiro.TotalMixSnapshotTouchIOS;
    GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = iOS/Info.plist;
    INFOPLIST_KEY_CFBundleDisplayName = "TotalMix Touch";
    CODE_SIGN_STYLE = Automatic; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
'''
test_settings = '''SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0;
    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = "1,2";
    PRODUCT_NAME = TotalMixSnapshotTouchIOSUITests; PRODUCT_BUNDLE_IDENTIFIER = local.seijiro.TotalMixSnapshotTouchIOSUITests;
    GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic;
    TEST_TARGET_NAME = TotalMixSnapshotTouchIOS; SKIP_INSTALL = YES;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
'''
products = []


def target(name, key, source_files, resources, settings, product_type='application', dependencies=()):
    extension = 'app' if product_type == 'application' else 'xctest'
    file_type = 'wrapper.application' if product_type == 'application' else 'wrapper.cfbundle'
    product = obj(f'product:{key}', f'isa = PBXFileReference; explicitFileType = {file_type}; path = {name}.{extension}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    sources = phase(f'sources:{key}', 'PBXSourcesBuildPhase', source_files)
    framework = phase(f'frameworks:{key}', 'PBXFrameworksBuildPhase', [])
    resource = phase(f'resources:{key}', 'PBXResourcesBuildPhase', resources)
    configs = configuration_list(f'configs:{key}', settings)
    return obj(key, f'isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = ({sources},{framework},{resource},); buildRules = (); dependencies = ({",".join(dependencies)}); name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{product_type}";')


mac = target('TotalMixSnapshotTouch', 'target', mac_files, ['Resources/AppIcon.icns'], mac_settings)
ios = target('TotalMixSnapshotTouchIOS', 'target:ios', ios_files, ['iOS/Assets.xcassets'], ios_settings)
proxy = obj('ios-test-proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {ios}; remoteInfo = TotalMixSnapshotTouchIOS;')
dependency = obj('ios-test-dependency', f'isa = PBXTargetDependency; target = {ios}; targetProxy = {proxy};')
tests = target('TotalMixSnapshotTouchIOSUITests', 'target:ios-tests', test_files, [], test_settings, 'bundle.ui-testing', [dependency])
products_group = obj('products', f'isa = PBXGroup; children = ({",".join(products)},); name = Products; sourceTree = "<group>";')
main = obj('main', f'isa = PBXGroup; children = ({",".join(list(file_refs.values()) + [products_group])},); sourceTree = "<group>";')
project = obj('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2600; TargetAttributes = {{{tests} = {{TestTargetID = {ios};}};}};}}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja,en,Base,); mainGroup = {main}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({mac},{ios},{tests},);')
folder = root / 'TotalMixSnapshotTouch.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project};}}\n')
scheme = folder / 'xcshareddata/xcschemes'
scheme.mkdir(parents=True, exist_ok=True)


def buildable(name, target_id, extension='app'):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:TotalMixSnapshotTouch.xcodeproj"/>'


def write_scheme(name, target_id, test_target=None):
    ref = buildable(name, target_id)
    entry = f'<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry>'
    test_action = ''
    if test_target:
        test_ref = buildable('TotalMixSnapshotTouchIOSUITests', test_target, 'xctest')
        entry += f'<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{test_ref}</BuildActionEntry>'
        test_action = f'<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>'
    (scheme / f'{name}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>{entry}</BuildActionEntries></BuildAction>
{test_action}
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')


write_scheme('TotalMixSnapshotTouch', mac)
write_scheme('TotalMixSnapshotTouchIOS', ios, tests)
print('Generated macOS + iOS targets and iOS UI test scheme.')
