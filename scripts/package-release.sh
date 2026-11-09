#!/bin/bash
# AI Usage Buddy — Release .app → バージョン付きzip → SHA-256
# 使い方: ./scripts/package-release.sh [--reuse-app]
# 出力先: build/release/
#   - AI Usage Buddy.app
#   - AIUsageBuddy-<version>-<build>-arm64.zip
#   - SHA256SUMS.txt
#   - RELEASE_NOTES.txt（バージョン・署名状態・検証方法）
# 注意: このスクリプトは署名・公証を行わない（sign-and-notarize.sh.example 参照）。
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AI Usage Buddy"
RELEASE_DIR="${AI_USAGE_BUDDY_RELEASE_DIR:-$PROJECT_ROOT/build/release}"
APP_ROOT="$RELEASE_DIR/$APP_NAME.app"
SUMS_FILE="$RELEASE_DIR/SHA256SUMS.txt"

MODE="build"
if [[ $# -gt 1 ]]; then
  echo "使い方: $0 [--reuse-app]" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" != "--reuse-app" ]]; then
    echo "使い方: $0 [--reuse-app]" >&2
    exit 2
  fi
  MODE="reuse"
fi

mkdir -p "$RELEASE_DIR"

# 正式署名済みアプリを通常ビルドで上書きしない。
if [[ "$MODE" == "build" && -d "$APP_ROOT" ]]; then
  if ! EXISTING_SIGN_INFO=$(codesign -dv --verbose=4 "$APP_ROOT" 2>&1); then
    if ! printf '%s\n' "$EXISTING_SIGN_INFO" | grep -Fq "code object is not signed at all"; then
      echo "既存 .app の署名状態を判定できないため、上書きせず停止した。" >&2
      printf '%s\n' "$EXISTING_SIGN_INFO" >&2
      exit 1
    fi
  fi
  EXISTING_SIGNATURE=$(printf '%s\n' "$EXISTING_SIGN_INFO" | sed -n 's/^Signature=//p' | head -1)
  EXISTING_TEAM_ID=$(printf '%s\n' "$EXISTING_SIGN_INFO" | sed -n 's/^TeamIdentifier=//p' | head -1)
  if [[ ( -n "$EXISTING_SIGNATURE" && "$EXISTING_SIGNATURE" != "adhoc" ) ||
        ( -n "$EXISTING_TEAM_ID" && "$EXISTING_TEAM_ID" != "not set" ) ]] ||
      printf '%s\n' "$EXISTING_SIGN_INFO" | grep -q '^Authority='; then
    echo "Developer ID等で署名済みの .app を上書きしないため停止した。" >&2
    echo "署名・ステープル後は ./scripts/package-release.sh --reuse-app を使うこと。" >&2
    exit 1
  fi
fi

if [[ "$MODE" == "reuse" ]]; then
  if [[ ! -d "$APP_ROOT" ]]; then
    echo "--reuse-app 指定時は既存の .app が必要: $APP_ROOT" >&2
    exit 1
  fi
  echo "==> 既存 .app を再利用（ビルド・署名の変更なし）"
else
  echo "==> Releaseビルド（build-app.sh）"
  "$PROJECT_ROOT/scripts/build-app.sh" "$RELEASE_DIR"
fi

# バージョン情報は .app の Info.plist を正とする。
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_ROOT/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_ROOT/Contents/Info.plist")
ZIP_NAME="AIUsageBuddy-${VERSION}-${BUILD}-arm64.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
DMG_NAME="AIUsageBuddy-${VERSION}-${BUILD}-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"

# 署名・公証がすべて確認できた場合だけ正式状態と記載する。
echo "==> 署名状態の確認"
SIGN_INFO_STATE="signed"
if ! SIGN_INFO=$(codesign -dv --verbose=4 "$APP_ROOT" 2>&1); then
  if printf '%s\n' "$SIGN_INFO" | grep -Fq "code object is not signed at all"; then
    SIGN_INFO_STATE="unsigned"
  else
    echo ".app の署名状態を判定できないためパッケージを作成しない。" >&2
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
      echo "Developer ID署名を検証できないためパッケージを作成しない。" >&2
      exit 1
    fi
    SIGNING_STATUS="Developer ID署名済み（公証・ステープル未実施）"
    SIGNING_ICON="!!"
  elif codesign --verify --strict "$APP_ROOT" >/dev/null 2>&1 &&
      xcrun stapler validate "$APP_ROOT" >/dev/null 2>&1 &&
      spctl --assess --type execute "$APP_ROOT" >/dev/null 2>&1; then
    SIGNING_STATUS="Developer ID署名・公証ステープル・Gatekeeper検証済み"
    SIGNING_ICON="OK"
  else
    SIGNING_STATUS="Developer ID署名あり（公証・ステープル未検証）"
    SIGNING_ICON="!!"
  fi
elif [[ "$SIGNATURE" == "adhoc" ]]; then
  SIGNING_STATUS="ad-hoc署名（Developer ID署名・公証は未実施）"
  SIGNING_ICON="!!"
elif [[ "$SIGN_INFO_STATE" == "unsigned" ]]; then
  SIGNING_STATUS="未署名（Developer ID署名・公証は未実施）"
  SIGNING_ICON="!!"
elif [[ -n "$TEAM_ID" && "$TEAM_ID" != "not set" ]] ||
     printf '%s\n' "$SIGN_INFO" | grep -q '^Authority='; then
  SIGNING_STATUS="署名あり（Developer ID署名・公証は未確認）"
  SIGNING_ICON="!!"
else
  echo ".app の署名情報が想定外の形式のため停止した。" >&2
  printf '%s\n' "$SIGN_INFO" >&2
  exit 1
fi
echo "    $SIGNING_ICON $SIGNING_STATUS"

# zipは一時ファイルから置き換える。
echo "==> zip作成: $ZIP_NAME"
ZIP_TMP="$RELEASE_DIR/.$ZIP_NAME.$$"
SUMS_TMP="$RELEASE_DIR/.SHA256SUMS.txt.$$"
trap 'rm -f "$ZIP_TMP" "$SUMS_TMP"' EXIT
ditto -c -k --keepParent "$APP_ROOT" "$ZIP_TMP"
mv -f "$ZIP_TMP" "$ZIP_PATH"

# 現在の版で実在する配布対象（zip / 既存DMG）のチェックサムを集約する。
SHA_ZIP=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
{
  echo "$SHA_ZIP  $ZIP_NAME"
  if [[ -f "$DMG_PATH" ]]; then
    shasum -a 256 "$DMG_PATH" | awk -v name="$DMG_NAME" '{print $1 "  " name}'
  fi
} > "$SUMS_TMP"
mv -f "$SUMS_TMP" "$SUMS_FILE"

# 6) リリースノート（配布物の状態を誤解させないための明示）
cat > "$RELEASE_DIR/RELEASE_NOTES.txt" <<NOTES
AI Usage Buddy ${VERSION} (build ${BUILD}) — Apple Silicon (arm64) / macOS 13以降

署名状態: ${SIGNING_STATUS}

このパッケージをDeveloper ID署名・公証済みと表示するのは、
署名検証・ステープル検証・Gatekeeper検証がすべて成功した場合だけです。
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
echo "    DMGも作成する場合: ./scripts/create-dmg.sh --reuse-app"
