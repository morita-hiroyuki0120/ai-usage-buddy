#!/bin/bash
# AI Usage Buddy — DMG作成（.app + Applicationsへのエイリアス + インストール案内）
# 使い方: ./scripts/create-dmg.sh
# 前提: build/release/AI Usage Buddy.app（無ければ build-app.sh で生成）
# 出力先: build/release/AIUsageBuddy-<version>-<build>-arm64.dmg
# 注意: このスクリプトは署名・公証を行わない（sign-and-notarize.sh.example 参照）。
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AI Usage Buddy"
RELEASE_DIR="$PROJECT_ROOT/build/release"
APP_ROOT="$RELEASE_DIR/$APP_NAME.app"
SUMS_FILE="$RELEASE_DIR/SHA256SUMS.txt"

# 1) .app が無ければ生成（既存スクリプトを再利用）
if [[ ! -d "$APP_ROOT" ]]; then
  echo "==> .app が無いため build-app.sh を実行"
  "$PROJECT_ROOT/scripts/build-app.sh" "$RELEASE_DIR"
fi

# 2) バージョンは Info.plist から読む（package-release.sh と同じ規則）
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_ROOT/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_ROOT/Contents/Info.plist")
DMG_NAME="AIUsageBuddy-${VERSION}-${BUILD}-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"

# 3) 署名状態の確認（DMG掲載物の状態を明示）
SIGN_INFO=$(codesign -dv "$APP_ROOT" 2>&1 || true)
SIGNATURE=$(echo "$SIGN_INFO" | grep "^Signature=" | head -1 | cut -d= -f2)
TEAM_ID=$(echo "$SIGN_INFO" | grep "^TeamIdentifier=" | head -1 | cut -d= -f2)
if [[ "$SIGNATURE" == "adhoc" || -z "$SIGNATURE" || "$TEAM_ID" == "not set" ]]; then
  SIGNING_STATUS="ad-hoc署名（配布用のDeveloper ID署名ではありません・公証も未実施）"
else
  SIGNING_STATUS="TeamIdentifier=$TEAM_ID の署名あり"
fi

# 4) ステージング組み立て（.app + Applicationsエイリアス + 案内）
echo "==> ステージング組み立て"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_ROOT" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/はじめにお読みください.txt" <<TXT
AI Usage Buddy ${VERSION} (build ${BUILD}) — macOS 13以降 / Apple Silicon

インストール手順:
  1. 「AI Usage Buddy.app」を横の「Applications」フォルダへドラッグ＆ドロップ
  2. Applications から AI Usage Buddy を起動
  3. メニューバーにキャラクターが表示されます

はじめて起動するとき:
  - Gatekeeperにブロックされた場合は、Finderで AI Usage Buddy.app を
    右クリック →「開く」→「開く」を選択してください
  - 通知を利用する場合は通知の許可を求められたら「許可」を選択してください

要件:
  - macOS 13 Ventura 以降（Apple Silicon）
  - ChatGPT公式macOSアプリ（同梱の公式Codex CLIを使用）

署名状態: ${SIGNING_STATUS}

利用データの送信先サーバー・広告・分析はありません（ローカル完結）。
更新確認のみ GitHub Releases（設定済みの場合）へHTTPS接続します。
TXT

# 5) DMG作成（UDZO圧縮）
echo "==> DMG作成: $DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

# 6) SHA-256を SUMS ファイルへ追記
SHA_DMG=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
touch "$SUMS_FILE"
grep -v "  $DMG_NAME$" "$SUMS_FILE" > "$SUMS_FILE.tmp" 2>/dev/null || true
mv "$SUMS_FILE.tmp" "$SUMS_FILE"
echo "$SHA_DMG  $DMG_NAME" >> "$SUMS_FILE"

echo "==> SHA-256"
echo "    $SHA_DMG  $DMG_NAME"

echo ""
echo "==> 完了: $DMG_PATH"
echo "    署名: $SIGNING_STATUS"
echo "    検証: shasum -a 256 ${DMG_NAME}（SHA256SUMS.txt と一致すること）"
