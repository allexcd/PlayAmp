#!/bin/zsh
set -eu
cd "${0:A:h}/.."
xcodebuild -project PlayAmp.xcodeproj -scheme PlayAmp -configuration Release -derivedDataPath DerivedData -clonedSourcePackagesDirPath .build build
python3 scripts/collect-licenses.py
python3 scripts/package-app.py
