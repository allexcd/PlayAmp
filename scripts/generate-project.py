from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(name, value): objects[uid(name)]=value; return uid(name)
files=[]; builds=[]
for p in sorted((root/'Sources/PlayAmp').glob('*.swift')):
    f=add(str(p),'{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Sources/PlayAmp/'+p.name+'"; sourceTree = SOURCE_ROOT; }'); files.append(f)
    builds.append(add('build'+p.name,'{isa = PBXBuildFile; fileRef = '+f+'; }'))
# Compile core alongside the application; conditional import keeps SwiftPM modular.
for p in sorted((root/'Sources/PlayAmpCore').glob('*.swift')):
    f=add(str(p),'{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Sources/PlayAmpCore/'+p.name+'"; sourceTree = SOURCE_ROOT; }'); files.append(f)
    builds.append(add('build'+p.name,'{isa = PBXBuildFile; fileRef = '+f+'; }'))
product=add('product','{isa = PBXFileReference; explicitFileType = wrapper.application; path = PlayAmp.app; sourceTree = BUILT_PRODUCTS_DIR; }')
group=add('group','{isa = PBXGroup; children = ('+','.join(files+[product])+'); sourceTree = "<group>"; }')
# The audio engine is a trimmed copy inside the repo (see Vendor/SFBAudioEngine/VENDORED.md).
remote=add('remote','{isa = XCLocalSwiftPackageReference; relativePath = Vendor/SFBAudioEngine; }')
dep=add('dep','{isa = XCSwiftPackageProductDependency; package = '+remote+'; productName = SFBAudioEngine; }')
link=add('link','{isa = PBXBuildFile; productRef = '+dep+'; }')
sources=add('sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(builds)+'); runOnlyForDeploymentPostprocessing = 0; }')
frameworks=add('frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ('+link+'); runOnlyForDeploymentPostprocessing = 0; }')
configs=[]
for mode in ['Debug','Release']:
    configs.append(add(mode,'{isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {SDKROOT = macosx; ENABLE_USER_SCRIPT_SANDBOXING = NO; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; MACOSX_DEPLOYMENT_TARGET = 15.0; ARCHS = arm64; SWIFT_VERSION = 5.0; PRODUCT_NAME = PlayAmp; PRODUCT_BUNDLE_IDENTIFIER = com.allexcd.playamp; INFOPLIST_FILE = Config/Info.plist; CODE_SIGN_ENTITLEMENTS = Config/PlayAmp.entitlements; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_APP_SANDBOX = YES; SWIFT_OPTIMIZATION_LEVEL = "'+('-Onone' if mode=='Debug' else '-O')+'"; }; }'))
config=add('config','{isa = XCConfigurationList; buildConfigurations = ('+','.join(configs)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
embed=add('embed', '{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/zsh; shellScript = "\\\"$SRCROOT/scripts/embed-frameworks.sh\\\""; }')
target=add('target' ,'{isa = PBXNativeTarget; buildConfigurationList = '+config+'; buildPhases = ('+sources+','+frameworks+','+embed+'); buildRules = (); dependencies = (); name = PlayAmp; productName = PlayAmp; productReference = '+product+'; productType = "com.apple.product-type.application"; packageProductDependencies = ('+dep+'); }')
project=add('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 1600; }; buildConfigurationList = '+config+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = '+group+'; projectDirPath = ""; projectRoot = ""; targets = ('+target+'); packageReferences = ('+remote+'); }')
folder=root/'PlayAmp.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n')
