#!/bin/zsh
set -eu
mkdir -p "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
for framework in "$BUILT_PRODUCTS_DIR"/*.framework; do
  destination="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/${framework:t}"
  ditto "$framework" "$destination"
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$destination"
done
cp "$SRCROOT/THIRD_PARTY_NOTICES.md" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/"
# Replace the folder, so notices of libraries that were dropped never linger.
rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses"
cp -R "$SRCROOT/Licenses" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/"
cp "$SRCROOT/Config/AppIcon.icns" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/"
cp "$SRCROOT/Config/PrivacyInfo.xcprivacy" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/"
rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/SkinExamples"
cp -R "$SRCROOT/skills/playamp-skins/examples" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/SkinExamples"
