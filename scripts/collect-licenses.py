"""Collects the license of every package the app is built from into Licenses/.

Only packages pinned in Package.resolved are included (plus the vendored audio engine),
so a stale checkout can never add or hide a notice. The folder is rebuilt each time.
"""
import json
import shutil
from pathlib import Path
root = Path(__file__).resolve().parent.parent
out = root/'Licenses'
shutil.rmtree(out, ignore_errors=True); out.mkdir()
def collect(folder, name):
    found = False
    for f in sorted(folder.iterdir()):
        if f.is_file() and ('LICENSE' in f.name.upper() or 'COPYING' in f.name.upper()):
            (out/(name+'-'+f.name)).write_bytes(f.read_bytes()); found = True
    if not found: raise SystemExit(f'No license file found for {name} in {folder}')
collect(root/'Vendor/SFBAudioEngine', 'SFBAudioEngine')
checkouts = {p.name.lower(): p for p in (root/'.build/checkouts').iterdir() if p.is_dir()}
for pin in json.loads((root/'Package.resolved').read_text())['pins']:
    folder = checkouts.get(pin['identity'].lower())
    if folder is None: raise SystemExit(f"Package {pin['identity']} is pinned but not checked out; build first")
    collect(folder, folder.name)
print('Collected', len(list(out.iterdir())), 'license files')
