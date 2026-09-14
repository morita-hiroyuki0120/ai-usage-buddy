#!/bin/bash
# AI Usage Buddy — Apple Silicon向けReleaseビルドと .app バンドル生成
# 使い方: ./scripts/build-app.sh [出力先ディレクトリ（デフォルト: ./build）]
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build}"
APP_NAME="AI Usage Buddy"
BUNDLE_ID="com.aiusagebuddy.app"
APP_ROOT="$OUTPUT_DIR/$APP_NAME.app"

# --- リリース設定（config/ReleaseConfig.xcconfig → 無ければテンプレート） ---
# 秘密情報はここに置かない。署名情報は scripts/sign-and-notarize.sh.example 参照。
CONFIG_FILE="$PROJECT_ROOT/config/ReleaseConfig.xcconfig"
CONFIG_TEMPLATE="$PROJECT_ROOT/config/ReleaseConfig.example.xcconfig"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$CONFIG_TEMPLATE"
fi

read_config() {
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$CONFIG_FILE" | tail -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

APP_VERSION="$(read_config APP_MARKETING_VERSION)"
BUILD_NUMBER="$(read_config APP_BUILD_NUMBER)"
GITHUB_OWNER="$(read_config GITHUB_OWNER)"
GITHUB_REPOSITORY="$(read_config GITHUB_REPOSITORY)"
SPARKLE_APPCAST_URL="$(read_config SPARKLE_APPCAST_URL)"

if [[ -z "$APP_VERSION" || ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "APP_MARKETING_VERSION が不正です: '$APP_VERSION'（config: $CONFIG_FILE）" >&2
  exit 1
fi
if [[ -z "$BUILD_NUMBER" || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "APP_BUILD_NUMBER が不正です: '$BUILD_NUMBER'（config: $CONFIG_FILE）" >&2
  exit 1
fi
if [[ -z "$GITHUB_REPOSITORY" ]]; then
  GITHUB_REPOSITORY="AIUsageBuddy"
fi
if [[ "$GITHUB_OWNER" == "YOUR_GITHUB_OWNER" ]]; then
  GITHUB_OWNER=""
fi
if [[ -z "$GITHUB_OWNER" ]]; then
  echo "==> 注意: GitHub所有者が未設定（更新確認は行われず手動更新モード）"
  echo "    リポジトリ公開後は config/ReleaseConfig.xcconfig の GITHUB_OWNER に設定する"
fi
echo "==> リリース設定: バージョン $APP_VERSION (build $BUILD_NUMBER) / repo: ${GITHUB_OWNER:-<未設定>}/$GITHUB_REPOSITORY"

echo "==> Release ビルド（arm64）"
cd "$PROJECT_ROOT"
swift build -c release --arch arm64

BINARY="$PROJECT_ROOT/.build/arm64-apple-macosx/release/aiusagebuddy"
if [[ ! -f "$BINARY" ]]; then
  # SPMのバリアントパス差異に対応
  BINARY="$PROJECT_ROOT/.build/release/aiusagebuddy"
fi
if [[ ! -f "$BINARY" ]]; then
  echo "ビルド成果物が見つかりません" >&2
  exit 1
fi

echo "==> .app バンドル組み立て"
rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS"
mkdir -p "$APP_ROOT/Contents/Resources"

cp "$BINARY" "$APP_ROOT/Contents/MacOS/AIUsageBuddy"

# SPMリソースバンドル（ローカライズ文字列）をコピー
RESOURCE_BUNDLE_SRC=$(find "$PROJECT_ROOT/.build" -name "AIUsageBuddy_AIUsageBuddy.bundle" -type d | head -1)
if [[ -n "$RESOURCE_BUNDLE_SRC" ]]; then
  cp -R "$RESOURCE_BUNDLE_SRC" "$APP_ROOT/Contents/Resources/"
fi

# Info.plist（LSUIElement=1 で Dock 非表示 / App Sandbox 無効）
cat > "$APP_ROOT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI Usage Buddy</string>
    <key>CFBundleDisplayName</key>
    <string>AI Usage Buddy</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>GitHubOwner</key>
    <string>${GITHUB_OWNER}</string>
    <key>GitHubRepository</key>
    <string>${GITHUB_REPOSITORY}</string>
    <key>SparkleAppcastURL</key>
    <string>${SPARKLE_APPCAST_URL}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AIUsageBuddy</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>ja</string>
        <string>en</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSUserNotificationsUsageDescription</key>
    <string>利用枠の残量が少なくなったときに通知します。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ログイン項目の登録状態を確認するために使用します。</string>
</dict>
</plist>
PLIST

# ad-hoc署名（未署名でのGatekeeper回避と、安定した実行Identity付与）
codesign --force --deep --sign - "$APP_ROOT"

echo "==> 検証: Info.plist の LSUIElement"
LSUIELEMENT_VALUE=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_ROOT/Contents/Info.plist")
echo "    LSUIElement = $LSUIELEMENT_VALUE"
if [[ "$LSUIELEMENT_VALUE" != "true" ]]; then
  echo "LSUIElement が true ではありません" >&2
  exit 1
fi

echo "==> 完了: $APP_ROOT"
echo "    起動: open \"$APP_ROOT\""
