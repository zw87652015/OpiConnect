#!/usr/bin/env bash
# Archive the watch-only app (OpiConnect container) and upload it to App Store Connect / TestFlight.
# Usage: scripts/testflight.sh              archive + upload
#        DESTINATION=export scripts/testflight.sh   archive + export an .ipa locally, no upload
#        BUILD_NUMBER=42 scripts/testflight.sh      override the build number (default: timestamp)
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=watch/OpiConnect.xcodeproj
SCHEME=OpiConnect
BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
DEST="${DESTINATION:-upload}"
WORK=watch/build/testflight
ARCHIVE="$WORK/OpiConnect.xcarchive"
EXPORT="$WORK/export"

if [[ "$DEST" != "upload" && "$DEST" != "export" ]]; then
  echo "DESTINATION must be 'upload' or 'export'"
  exit 1
fi

settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)
setting() { sed -n "s/^ *$1 = //p" <<<"$settings" | head -n 1; }
team=$(setting DEVELOPMENT_TEAM)
bundle=$(setting PRODUCT_BUNDLE_IDENTIFIER)
version=$(setting MARKETING_VERSION)
if [[ -z "$team" || "$bundle" == com.example.* ]]; then
  echo "Set DEVELOPMENT_TEAM and BUNDLE_PREFIX in watch/Local.xcconfig (see watch/Local.xcconfig.example)"
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"

echo "Archiving ${bundle} ${version} (build ${BUILD})"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD"

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>${DEST}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>${team}</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
EOF

echo "Exporting (destination=${DEST})"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates

if [[ "$DEST" == "upload" ]]; then
  echo "Uploaded ${version} (build ${BUILD}). App Store Connect needs a few minutes to process it, then it appears in TestFlight."
else
  echo "Exported to ${EXPORT} (not uploaded)."
fi
