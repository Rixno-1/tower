#!/bin/zsh
# Incremental build + non-destructive device installation. See docs/DEVELOPMENT.md.
set -e
: "${DEVELOPER_DIR:?按 AGENTS.md 设置 DEVELOPER_DIR 后再运行}"
cd "${0:A:h:h}"
xcodebuild -version

tower_install_tmp="$(mktemp -d)"
trap 'find "$tower_install_tmp" -type f -delete; rmdir "$tower_install_tmp"' EXIT

tower_device_json="$tower_install_tmp/devices.json"
xcrun devicectl list devices --json-output "$tower_device_json" >/dev/null
tower_xcode_devices="$tower_install_tmp/xcode-devices.json"
xcrun xcdevice list >"$tower_xcode_devices"
tower_device_id="$(python3 Scripts/select_device.py "$tower_device_json" "$tower_xcode_devices")"

tower_profile_plist="$tower_install_tmp/profile.plist"
tower_team_ids="$(
  setopt null_glob
  for tower_profile in \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision \
    "$HOME/Library/MobileDevice/Provisioning Profiles/"*.mobileprovision; do
    security cms -D -i "$tower_profile" >"$tower_profile_plist" 2>/dev/null || continue
    tower_app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$tower_profile_plist" 2>/dev/null)"
    tower_debug="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$tower_profile_plist" 2>/dev/null)"
    tower_device="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices:0' "$tower_profile_plist" 2>/dev/null)"
    if [[ "$tower_app_id" == *.com.jzb.tower && "$tower_debug" == true && -n "$tower_device" ]]; then
      /usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$tower_profile_plist"
    fi
  done | sort -u
)"
tower_team_count="$(printf '%s\n' "$tower_team_ids" | awk 'NF { count++ } END { print count + 0 }')"
[[ "$tower_team_count" == 1 ]] || { echo '没有找到唯一的塔台开发团队，停止安装'; exit 1; }
tower_team_id="$tower_team_ids"

tower_derived_data="$PWD/.derived-data-device"
xcodebuild -quiet \
  -project Tower.xcodeproj \
  -scheme Tower \
  -configuration Debug \
  -destination "platform=iOS,id=$tower_device_id" \
  -sdk iphoneos \
  -derivedDataPath "$tower_derived_data" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$tower_team_id" \
  build

tower_app="$tower_derived_data/Build/Products/Debug-iphoneos/Tower.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$tower_app/Info.plist")" == iPhoneOS ]] || { echo '构建产物不是真机平台，停止安装'; exit 1; }
xcrun devicectl device install app --device "$tower_device_id" "$tower_app" >/dev/null 2>&1
printf '覆盖安装成功，正在启动…\n'
xcrun devicectl device process launch \
  --device "$tower_device_id" \
  --terminate-existing \
  com.jzb.tower >/dev/null 2>&1

tower_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$tower_app/Info.plist")"
tower_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$tower_app/Info.plist")"
printf '塔台 %s (%s) 已安装并启动。\n' "$tower_version" "$tower_build"
