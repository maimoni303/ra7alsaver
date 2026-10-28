#!/usr/bin/env bash
# Generates the native platform folders with `flutter create`, then applies
# RA7AL SAVER settings (cleartext servers, photos access, biometrics, network entitlement,
# deployment targets, display name, icons). Usage: tool/setup_platforms.sh ios|macos|windows
set -euo pipefail
PLATFORM="$1"

flutter create --platforms="$PLATFORM" --org com.ra7al --project-name ra7alsaver . >/dev/null
rm -rf test   # flutter create adds a sample test that does not apply here

pb() { /usr/libexec/PlistBuddy "$@" 2>/dev/null || true; }

allow_http() {   # $1 = Info.plist
  pb -c "Delete :NSAppTransportSecurity" "$1"
  pb -c "Add :NSAppTransportSecurity dict" "$1"
  pb -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$1"
  pb -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoadsForMedia bool true" "$1"
}

case "$PLATFORM" in
  ios)
    PLIST=ios/Runner/Info.plist
    allow_http "$PLIST"
    pb -c "Delete :CFBundleDisplayName" "$PLIST"
    pb -c "Add :CFBundleDisplayName string RA7AL SAVER" "$PLIST"
    pb -c "Add :UIBackgroundModes array" "$PLIST"
    pb -c "Add :UIBackgroundModes:0 string audio" "$PLIST"
    pb -c "Add :LSApplicationCategoryType string public.app-category.photography" "$PLIST"
    pb -c "Add :NSFaceIDUsageDescription string Lock My files with Face ID" "$PLIST"
    pb -c "Add :NSPhotoLibraryAddUsageDescription string Save videos and photos to your library" "$PLIST"
    pb -c "Add :NSPhotoLibraryUsageDescription string Save videos and photos to your library" "$PLIST"
    pb -c "Add :UISupportsDocumentBrowser bool true" "$PLIST"
    pb -c "Add :UIFileSharingEnabled bool true" "$PLIST"
    pb -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$PLIST"
    if [ -f ios/Podfile ]; then
      sed -i '' -E "s/^#? *platform :ios, '[0-9.]+'/platform :ios, '13.0'/" ios/Podfile
    fi
    ;;
  macos)
    allow_http macos/Runner/Info.plist
    pb -c "Add :NSPhotoLibraryAddUsageDescription string Save videos and photos to your library" macos/Runner/Info.plist
    pb -c "Add :NSPhotoLibraryUsageDescription string Save videos and photos to your library" macos/Runner/Info.plist
    for ENT in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
      pb -c "Add :com.apple.security.network.client bool true" "$ENT"
      pb -c "Set :com.apple.security.network.client true" "$ENT"
      pb -c "Add :com.apple.security.personal-information.photos-library bool true" "$ENT"
    done
    sed -i '' -E 's/^PRODUCT_NAME = .*/PRODUCT_NAME = RA7ALSAVER/' macos/Runner/Configs/AppInfo.xcconfig
    pb -c "Set :CFBundleName RA7AL SAVER" macos/Runner/Info.plist
    pb -c "Delete :CFBundleDisplayName" macos/Runner/Info.plist
    pb -c "Add :CFBundleDisplayName string RA7AL SAVER" macos/Runner/Info.plist
    sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = 10\.[0-9]+;/MACOSX_DEPLOYMENT_TARGET = 10.15;/g' macos/Runner.xcodeproj/project.pbxproj
    if [ -f macos/Podfile ]; then
      sed -i '' -E "s/^#? *platform :osx, '[0-9.]+'/platform :osx, '10.15'/" macos/Podfile
    fi
    ;;
  android)
    python3 - <<'PY'
import re
p = "android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()
if "android.permission.INTERNET" not in s:
    s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="RA7AL SAVER"', s, count=1)
if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
# Gallery saving on Android 9 and older.
if "WRITE_EXTERNAL_STORAGE" not in s:
    s = s.replace("<application",
        '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n'
        '    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n'
        '    <application\n        android:requestLegacyExternalStorage="true"', 1)
open(p, "w", encoding="utf-8").write(s)
# local_auth needs a FragmentActivity.
import glob
for f in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
    k = open(f, encoding="utf-8").read()
    k = k.replace("import io.flutter.embedding.android.FlutterActivity", "import io.flutter.embedding.android.FlutterFragmentActivity")
    k = k.replace(": FlutterActivity()", ": FlutterFragmentActivity()")
    open(f, "w", encoding="utf-8").write(k)
    assert "FlutterFragmentActivity" in k
PY
    ;;
  windows)
    # Window title and executable description.
    sed -i 's/L"ra7alsaver"/L"RA7AL SAVER"/' windows/runner/main.cpp || true
    sed -i 's/"FileDescription", "ra7alsaver"/"FileDescription", "RA7AL SAVER"/; s/"ProductName", "ra7alsaver"/"ProductName", "RA7AL SAVER"/' windows/runner/Runner.rc || true
    ;;
esac

flutter pub get >/dev/null

if [ "$PLATFORM" = "windows" ]; then
  # New MSVC (VS 2026) removed experimental coroutines (/await). Build
  # local_auth_windows with standard C++20 coroutines instead.
  LA=windows/flutter/ephemeral/.plugin_symlinks/local_auth_windows/windows/CMakeLists.txt
  if [ -f "$LA" ]; then
    sed -i 's#/await:strict##g; s#/await##g; s#cxx_std_17#cxx_std_20#g' "$LA"
    grep -q "cxx_std_20" "$LA" || echo 'target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)' >> "$LA"
  fi
fi

# App icon for this platform only.
{
  echo "flutter_launcher_icons:"
  echo "  image_path: assets/icon.png"
  case "$PLATFORM" in
    ios) printf '  ios: true\n  android: false\n  remove_alpha_ios: true\n' ;;
    android) printf '  android: true\n  ios: false\n  min_sdk_android: 21\n' ;;
    macos) printf '  ios: false\n  android: false\n  macos:\n    generate: true\n    image_path: assets/icon.png\n' ;;
    windows) printf '  ios: false\n  android: false\n  windows:\n    generate: true\n    image_path: assets/icon.png\n    icon_size: 256\n' ;;
  esac
} > icons.yaml
dart run flutter_launcher_icons -f icons.yaml || echo "icon generation skipped"
rm -f icons.yaml
echo "Platform $PLATFORM ready"
