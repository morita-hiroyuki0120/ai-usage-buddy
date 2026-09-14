#!/bin/bash
# AI Usage Buddy — リリースパッケージ作成（arm64 Releaseビルド → .app → バージョン付きzip → SHA-256）
# 使い方: ./scripts/package-release.sh
# 出力先: build/release/
#   - AI Usage Buddy.app
#   - AIUsageBuddy-<version>-<build>-arm64.zip
#   - SHA256SUMS.txt
#   - RELEASE_NOTES.txt（バージョン・署名状態・検証方法）
# 注意: このスクリプトは署名・公証を行わない（sign-and-notarize.sh.example 参照）。
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AI Usage Buddy"
RELEASE_DIR="$PROJECT_ROOT/build/release"
APP_ROOT="$RELEASE_DIR/$APP_NAME.app"
SUMS_FILE="$RELEASE_DIR/SHA256SUMS.txt"

# 1) .app 生成（既存の build-app.sh を再利用し、成果物を release ディレクトリへ）
echo "==> Releaseビルド（build-app.sh を再利用）"
"$PROJECT_ROOT/scripts/build-app.sh" "$RELEASE_DIR"

# 2) バージョン情報は生成された Info.plist から読む（config との不一致を防ぐ）
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_ROOT/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_ROOT/Contents/Info.plist")
ZIP_NAME="AIUsageBuddy-${VERSION}-${BUILD}-arm64.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

# 3) 署名状態の確認（ad-hoc署名を配布用Developer ID署名と誤認させないため明示する）
echo "==> 署名状態の確認"
SIGN_INFO=$(codesign -dv "$APP_ROOT" 2>&1 || true)
SIGNATURE=$(echo "$SIGN_INFO" | grep "^Signature=" | head -1 | cut -d= -f2)
TEAM_ID=$(echo "$SIGN_INFO" | grep "^TeamIdentifier=" | head -1 | cut -d= -f2)

if [[ "$SIGNATURE" == "adhoc" || -z "$SIGNATURE" || "$TEAM_ID" == "not set" ]]; then
  SIGNING_STATUS="ad-hoc署名（配布用のDeveloper ID署名ではありません・公証も未実施）"
  SIGNING_ICON="!!"
elif [[ -n "$TEAM_ID" ]]; then
  SIGNING_STATUS="TeamIdentifier=$TEAM_ID の署名あり（Developer IDの場合は公証ステープルを確認すること）"
  SIGNING_ICON="OK"
else
  SIGNING_STATUS="未署名"
  SIGNING_ICON="!!"
fi
echo "    $SIGNING_ICON $SIGNING_STATUS"

# 4) バージョン付きzip（公証用途と同じ ditto 形式）
echo "==> zip作成: $ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_ROOT" "$ZIP_PATH"

# 5) SHA-256チェックサム（zip・.app内バイナリ）
SHA_ZIP=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
{
  echo "$SHA_ZIP  $ZIP_NAME"
} > "$SUMS_FILE"

# 6) リリースノート（配布物の状態を誤解させないための明示）
cat > "$RELEASE_DIR/RELEASE_NOTES.txt" <<NOTES
AI Usage Buddy ${VERSION} (build ${BUILD}) — Apple Silicon (arm64) / macOS 13以降

署名状態: ${SIGNING_STATUS}

このパッケージは配布用の署名・公証が済んでいるとは限りません。
初回起動時にGatekeeperへブロックされる場合は、Finderで
「AI Usage Buddy.app」を右クリック →「開く」を選択してください。

ファイル:
  ${ZIP_NAME}
  AI Usage Buddy.app（zip展開後の中身）

SHA-256:
  ${SHA_ZIP}  ${ZIP_NAME}

検証方法:
  shasum -a 256 ${ZIP_NAME}   # SHA256SUMS.txt と一致すること
NOTES

echo "==> SHA-256"
echo "    $SHA_ZIP  $ZIP_NAME"

echo ""
echo "==> 完了: $RELEASE_DIR"
echo "    zip: $ZIP_PATH"
echo "    署名: $SIGNING_STATUS"
echo "    DMGも作成する場合: ./scripts/create-dmg.sh"
