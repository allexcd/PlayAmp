from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
output = root/'dist'
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='PlayAmp-package-', dir=output) as temporary:
    staged = Path(temporary)/'PlayAmp.app'
    shutil.copytree(root/'DerivedData/Build/Products/Release/PlayAmp.app', staged, symlinks=True)
    resources = staged/'Contents/Resources'
    resources.mkdir(exist_ok=True)
    shutil.copy2(root/'THIRD_PARTY_NOTICES.md', resources)
    shutil.copytree(root/'Licenses', resources/'Licenses', dirs_exist_ok=True)
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(root/'Config/PlayAmp.entitlements'),str(staged)], check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(staged)], check=True)
    destination = output/'PlayAmp.app'
    if destination.exists():
        shutil.rmtree(destination)
    staged.rename(destination)
# The app was assembled in a temp folder; re-register it at its final path so
# Finder and the Dock pick up the current icon instead of a stale cached record.
destination.touch()
subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-f',str(destination)], check=False)
print('Built and verified dist/PlayAmp.app')
