#!/bin/bash
# AI Usage Buddy — DMG作成（.app + Applicationsへのエイリアス + インストール案内）
# 使い方: ./scripts/create-dmg.sh [--reuse-app]
# 前提: build/release/AI Usage Buddy.app（無ければ build-app.sh で生成）
# 出力先: build/release/AIUsageBuddy-<version>-<build>-arm64.dmg
# 注意: このスクリプトは署名・公証を行わない（sign-and-notarize.sh.example 参照）。
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AI Usage Buddy"
RELEASE_DIR="${AI_USAGE_BUDDY_RELEASE_DIR:-$PROJECT_ROOT/build/release}"
APP_ROOT="$RELEASE_DIR/$APP_NAME.app"
SUMS_FILE="$RELEASE_DIR/SHA256SUMS.txt"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--reuse-app" ) ]]; then
  echo "使い方: $0 [--reuse-app]" >&2
  exit 2
fi
REUSE_APP=0
[[ $# -eq 1 ]] && REUSE_APP=1

# 1) .app が無ければ生成（既存スクリプトを再利用）
if [[ ! -d "$APP_ROOT" ]]; then
  if [[ "$REUSE_APP" -eq 1 ]]; then
    echo "--reuse-app 指定時は既存の .app が必要: $APP_ROOT" >&2
    exit 1
  fi
  echo "==> .app が無いため build-app.sh を実行"
  "$PROJECT_ROOT/scripts/build-app.sh" "$RELEASE_DIR"
fi

# 2) バージョンは Info.plist から読む（package-release.sh と同じ規則）
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_ROOT/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_ROOT/Contents/Info.plist")
DMG_NAME="AIUsageBuddy-${VERSION}-${BUILD}-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
SUMS_TMP="$RELEASE_DIR/.SHA256SUMS.txt.$$"

# 3) 署名状態の確認（DMG掲載物の状態を明示）
SIGN_INFO_STATE="signed"
if ! SIGN_INFO=$(codesign -dv --verbose=4 "$APP_ROOT" 2>&1); then
  if printf '%s\n' "$SIGN_INFO" | grep -Fq "code object is not signed at all"; then
    SIGN_INFO_STATE="unsigned"
  else
    echo ".app の署名状態を判定できないためDMGを作成しない。" >&2
    printf '%s\n' "$SIGN_INFO" >&2
    exit 1
  fi
fi
SIGNATURE=$(printf '%s\n' "$SIGN_INFO" | sed -n 's/^Signature=//p' | head -1)
TEAM_ID=$(printf '%s\n' "$SIGN_INFO" | sed -n 's/^TeamIdentifier=//p' | head -1)
if printf '%s\n' "$SIGN_INFO" | grep -q '^Authority=Developer ID Application: '; then
  if [[ -z "$TEAM_ID" || "$TEAM_ID" == "not set" ]]; then
    echo "Developer ID署名にTeamIdentifierが無いため停止した。" >&2
    exit 1
  fi
  if [[ "${AI_USAGE_BUDDY_NOTARIZATION_STATE:-}" == "pending" ]]; then
    if ! codesign --verify --strict "$APP_ROOT"; then
      echo "Developer ID署名を検証できないためDMGを作成しない。" >&2
      exit 1
    fi
    SIGNING_STATUS="Developer ID署名済み（公証・ステープル未実施）"
  elif codesign --verify --strict "$APP_ROOT" >/dev/null 2>&1 &&
      xcrun stapler validate "$APP_ROOT" >/dev/null 2>&1 &&
      spctl --assess --type execute "$APP_ROOT" >/dev/null 2>&1; then
    SIGNING_STATUS="Developer ID署名・公証ステープル・Gatekeeper検証済み"
  else
    SIGNING_STATUS="Developer ID署名あり（公証・ステープル未検証）"
  fi
elif [[ "$SIGNATURE" == "adhoc" ]]; then
  SIGNING_STATUS="ad-hoc署名（Developer ID署名・公証は未実施）"
elif [[ "$SIGN_INFO_STATE" == "unsigned" ]]; then
  SIGNING_STATUS="未署名（Developer ID署名・公証は未実施）"
elif [[ -n "$TEAM_ID" && "$TEAM_ID" != "not set" ]] ||
     printf '%s\n' "$SIGN_INFO" | grep -q '^Authority='; then
  SIGNING_STATUS="署名あり（Developer ID署名・公証は未確認）"
else
  echo ".app の署名情報が想定外の形式のため停止した。" >&2
  printf '%s\n' "$SIGN_INFO" >&2
  exit 1
fi

# 4) ステージング組み立て（.app + Applicationsエイリアス + 案内）
echo "==> ステージング組み立て"
STAGING=$(mktemp -d)
DMG_TMP="$RELEASE_DIR/.AIUsageBuddy-${VERSION}-${BUILD}-arm64-$$.dmg"
trap 'rm -rf "$STAGING"; rm -f "$DMG_TMP" "$SUMS_TMP"' EXIT
ditto "$APP_ROOT" "$STAGING/$APP_NAME.app"
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
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_TMP" >/dev/null
mv -f "$DMG_TMP" "$DMG_PATH"

# zipがあれば現在の内容も含め、最終状態のチェックサムに更新する。
SHA_DMG=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
{
  ZIP_NAME="AIUsageBuddy-${VERSION}-${BUILD}-arm64.zip"
  ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
  if [[ -f "$ZIP_PATH" ]]; then
    shasum -a 256 "$ZIP_PATH" | awk -v name="$ZIP_NAME" '{print $1 "  " name}'
  fi
  echo "$SHA_DMG  $DMG_NAME"
} > "$SUMS_TMP"
mv -f "$SUMS_TMP" "$SUMS_FILE"

echo "==> SHA-256"
echo "    $SHA_DMG  $DMG_NAME"

echo ""
echo "==> 完了: $DMG_PATH"
echo "    署名: $SIGNING_STATUS"
echo "    検証: shasum -a 256 ${DMG_NAME}（SHA256SUMS.txt と一致すること）"
