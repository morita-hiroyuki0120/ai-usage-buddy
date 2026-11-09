#!/bin/bash
# リリース用シェルスクリプトの回帰テスト。署名や公証は実行せず、コマンドを一時モックへ差し替える。
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT=$(mktemp -d /tmp/aiusagebuddy-release-test.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT

for tool in bash ditto shasum awk sed grep; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "必要なコマンドが見つからない: $tool" >&2
    exit 1
  fi
done
if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "このテストはmacOSのPlistBuddyを必要とする。" >&2
  exit 1
fi

TEST_SCRIPTS="$TEST_ROOT/scripts"
MOCK_BIN="$TEST_ROOT/mock-bin"
RELEASE_DIR="$TEST_ROOT/candidate-release"
APP_ROOT="$RELEASE_DIR/AI Usage Buddy.app"
export AI_USAGE_BUDDY_RELEASE_DIR="$RELEASE_DIR"
mkdir -p "$TEST_SCRIPTS" "$MOCK_BIN" "$APP_ROOT/Contents/MacOS"
cp "$PROJECT_ROOT/scripts/package-release.sh" "$TEST_SCRIPTS/"
cp "$PROJECT_ROOT/scripts/create-dmg.sh" "$TEST_SCRIPTS/"
cp "$PROJECT_ROOT/scripts/sign-and-notarize.sh.example" "$TEST_SCRIPTS/"
chmod +x "$TEST_SCRIPTS/package-release.sh" "$TEST_SCRIPTS/create-dmg.sh"

cat > "$APP_ROOT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.aiusagebuddy.app</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
</dict></plist>
PLIST
printf 'fixture executable\n' > "$APP_ROOT/Contents/MacOS/AIUsageBuddy"
chmod +x "$APP_ROOT/Contents/MacOS/AIUsageBuddy"

cat > "$TEST_SCRIPTS/build-app.sh" <<'BUILD'
#!/bin/bash
: > "$1/build-app-was-called"
BUILD
chmod +x "$TEST_SCRIPTS/build-app.sh"

cat > "$MOCK_BIN/codesign" <<'CODESIGN'
#!/bin/bash
if [[ "$1" == "-dv" ]]; then
  case "$AUB_TEST_CODESIGN_STATE" in
    developer)
      printf '%s\n' \
        "Executable=$2" \
        "Identifier=com.aiusagebuddy.app" \
        "Format=app bundle with Mach-O thin" \
        "Signature size=1234" \
        "Authority=Developer ID Application: Test Team (ABCDEFGHIJ)" \
        "TeamIdentifier=ABCDEFGHIJ"
      echo "CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=20+5 location=embedded"
      echo "Timestamp=2026-10-15T00:00:00Z"
      exit 0
      ;;
    developer-no-runtime|developer-no-timestamp)
      printf '%s\n' "Executable=$2" "Identifier=com.aiusagebuddy.app" "Signature size=1234" "Authority=Developer ID Application: Test Team (ABCDEFGHIJ)" "TeamIdentifier=ABCDEFGHIJ"
      if [[ "$AUB_TEST_CODESIGN_STATE" == "developer-no-runtime" ]]; then
        echo "CodeDirectory v=20500 size=1234 flags=0x0 hashes=20+5 location=embedded"
        echo "Timestamp=2026-10-15T00:00:00Z"
      else
        echo "CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=20+5 location=embedded"
      fi
      exit 0
      ;;
    adhoc)
      printf '%s\n' \
        "Executable=$2" \
        "Identifier=com.aiusagebuddy.app" \
        "Signature=adhoc" \
        "TeamIdentifier=not set"
      exit 0
      ;;
    unsigned)
      echo "code object is not signed at all" >&2
      exit 1
      ;;
    failure)
      echo "codesign: unable to inspect bundle" >&2
      exit 2
      ;;
  esac
fi
if [[ "$1" == "--verify" ]]; then
  [[ "$AUB_TEST_VERIFY_FAIL" == "0" ]]
  exit $?
fi
exit 0
CODESIGN

cat > "$MOCK_BIN/xcrun" <<'XCRUN'
#!/bin/bash
if [[ "$1" == "notarytool" && "$2" == "submit" ]]; then
  : > "$AUB_TEST_NOTARY_WAS_CALLED"
  printf '{"id":"mock-id","status":"%s","nested":{"status":"Accepted"}}\n' "$AUB_TEST_NOTARY_STATUS"
  exit 0
fi
if [[ "$1" == "stapler" && "$2" == "validate" ]]; then
  [[ "$AUB_TEST_STAPLER_FAIL" == "0" ]]
  exit $?
fi
if [[ "$1" == "stapler" && "$2" == "staple" ]]; then
  : > "$AUB_TEST_STAPLE_WAS_CALLED"
  exit 0
fi
exit 0
XCRUN

cat > "$MOCK_BIN/spctl" <<'SPCTL'
#!/bin/bash
[[ "$AUB_TEST_SPCTL_FAIL" == "0" ]]
exit $?
SPCTL

cat > "$MOCK_BIN/hdiutil" <<'HDIUTIL'
#!/bin/bash
if [[ "$AUB_TEST_HDIUTIL_FAIL" == "1" ]]; then
  echo "mock hdiutil failure" >&2
  exit 1
fi
SOURCE=""
PREVIOUS=""
for TARGET in "$@"; do
  if [[ "$PREVIOUS" == "-srcfolder" ]]; then
    SOURCE="$TARGET"
  fi
  if [[ "$TARGET" == "-srcfolder" ]]; then
    PREVIOUS="$TARGET"
  else
    PREVIOUS=""
  fi
done
printf 'mock dmg payload\n' > "$TARGET"
if [[ -n "$SOURCE" && -f "$SOURCE/はじめにお読みください.txt" ]]; then
  cp "$SOURCE/はじめにお読みください.txt" "$AUB_TEST_HDIUTIL_CAPTURE"
fi
HDIUTIL

cat > "$MOCK_BIN/security" <<'SECURITY'
#!/bin/bash
: > "$AUB_TEST_SECURITY_WAS_CALLED"
printf '1) ABCD1234 "%s"\n' "$AI_USAGE_BUDDY_SIGNING_IDENTITY"
exit 0
SECURITY
chmod +x "$MOCK_BIN/codesign" "$MOCK_BIN/xcrun" "$MOCK_BIN/spctl" "$MOCK_BIN/hdiutil" "$MOCK_BIN/security"

export PATH="$MOCK_BIN:$PATH"
export AUB_TEST_CODESIGN_STATE=adhoc
export AUB_TEST_VERIFY_FAIL=0
export AUB_TEST_STAPLER_FAIL=0
export AUB_TEST_SPCTL_FAIL=0
export AUB_TEST_HDIUTIL_FAIL=0
export AUB_TEST_SECURITY_WAS_CALLED="$TEST_ROOT/security-was-called"
export AUB_TEST_NOTARY_WAS_CALLED="$TEST_ROOT/notary-was-called"
export AUB_TEST_STAPLE_WAS_CALLED="$TEST_ROOT/staple-was-called"
export AUB_TEST_HDIUTIL_CAPTURE="$TEST_ROOT/dmg-instructions.txt"
export AUB_TEST_NOTARY_STATUS=Rejected

ZIP_PATH="$RELEASE_DIR/AIUsageBuddy-1.0.1-2-arm64.zip"
DMG_PATH="$RELEASE_DIR/AIUsageBuddy-1.0.1-2-arm64.dmg"
LOG="$TEST_ROOT/test.log"

# 通常の開発経路はbuild-app.shを呼ぶ。
"$TEST_SCRIPTS/package-release.sh" > "$LOG" 2>&1
[[ -f "$RELEASE_DIR/build-app-was-called" ]] || {
  echo "通常経路がbuild-app.shを呼ばなかった。" >&2
  exit 1
}
grep -Fq "ad-hoc署名（Developer ID署名・公証は未実施）" "$LOG"

# 正式署名情報はSignature=ではなくAuthority/TeamIdentifierから分類する。
rm -f "$RELEASE_DIR/build-app-was-called"
export AUB_TEST_CODESIGN_STATE=developer
"$TEST_SCRIPTS/package-release.sh" --reuse-app > "$LOG" 2>&1
grep -Fq "Developer ID署名・公証ステープル・Gatekeeper検証済み" "$LOG"
[[ ! -f "$RELEASE_DIR/build-app-was-called" ]] || {
  echo "--reuse-app がbuild-app.shを呼んだ。" >&2
  exit 1
}

# ad-hocと明示的な未署名診断は別々の状態として表示する。
export AUB_TEST_CODESIGN_STATE=adhoc
"$TEST_SCRIPTS/package-release.sh" --reuse-app > "$LOG" 2>&1
grep -Fq "ad-hoc署名（Developer ID署名・公証は未実施）" "$LOG"
export AUB_TEST_CODESIGN_STATE=unsigned
"$TEST_SCRIPTS/package-release.sh" --reuse-app > "$LOG" 2>&1
grep -Fq "未署名（Developer ID署名・公証は未実施）" "$LOG"

# 判定不能なcodesign失敗は梱包と通常ビルドのどちらも止め、既存zip/DMGを保つ。
printf 'previous dmg\n' > "$DMG_PATH"
export AUB_TEST_CODESIGN_STATE=adhoc
"$TEST_SCRIPTS/package-release.sh" --reuse-app > "$LOG" 2>&1
grep -Fq "AIUsageBuddy-1.0.1-2-arm64.dmg" "$RELEASE_DIR/SHA256SUMS.txt"
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS.txt >/dev/null)
ZIP_HASH_BEFORE=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
export AUB_TEST_CODESIGN_STATE=failure
if "$TEST_SCRIPTS/package-release.sh" --reuse-app > "$LOG" 2>&1; then
  echo "codesign検査失敗なのに再梱包が成功した。" >&2
  exit 1
fi
grep -Fq "署名状態を判定できない" "$LOG"
[[ "$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')" == "$ZIP_HASH_BEFORE" ]]
[[ -f "$DMG_PATH" ]]
rm -f "$RELEASE_DIR/build-app-was-called"
if "$TEST_SCRIPTS/package-release.sh" > "$LOG" 2>&1; then
  echo "codesign検査失敗なのに通常ビルドが成功した。" >&2
  exit 1
fi
[[ ! -f "$RELEASE_DIR/build-app-was-called" ]]

# Developer ID署名済み.appは通常ビルドで上書きしない。
export AUB_TEST_CODESIGN_STATE=developer
if "$TEST_SCRIPTS/package-release.sh" > "$LOG" 2>&1; then
  echo "署名済み.appを通常ビルドで上書きできてしまった。" >&2
  exit 1
fi
grep -Fq "署名済みの .app を上書きしない" "$LOG"
[[ ! -f "$RELEASE_DIR/build-app-was-called" ]]

# DMG生成失敗時は既存DMGを保護し、成功時に置換。チェックサムはzipとDMG両方を含む。
export AUB_TEST_CODESIGN_STATE=adhoc
export AUB_TEST_HDIUTIL_FAIL=1
if "$TEST_SCRIPTS/create-dmg.sh" --reuse-app > "$LOG" 2>&1; then
  echo "hdiutil失敗を成功扱いした。" >&2
  exit 1
fi
grep -Fq "previous dmg" "$DMG_PATH"
export AUB_TEST_HDIUTIL_FAIL=0
"$TEST_SCRIPTS/create-dmg.sh" --reuse-app > "$LOG" 2>&1
grep -Fq "mock dmg payload" "$DMG_PATH"
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS.txt >/dev/null)
grep -Fq "AIUsageBuddy-1.0.1-2-arm64.zip" "$RELEASE_DIR/SHA256SUMS.txt"
grep -Fq "AIUsageBuddy-1.0.1-2-arm64.dmg" "$RELEASE_DIR/SHA256SUMS.txt"

# Apple Development identityはDeveloper ID署名処理へ到達する前に拒否する。
if AI_USAGE_BUDDY_SIGNING_IDENTITY="Apple Development: Test (ABCDEFGHIJ)" \
   AI_USAGE_BUDDY_TEAM_ID="ABCDEFGHIJ" \
   AI_USAGE_BUDDY_NOTARY_PROFILE="test-profile" \
   AI_USAGE_BUDDY_BUNDLE_ID="com.aiusagebuddy.app" \
   bash "$TEST_SCRIPTS/sign-and-notarize.sh.example" > "$LOG" 2>&1; then
  echo "Apple Development identityを受け入れてしまった。" >&2
  exit 1
fi
grep -Fq "Developer ID Application証明書だけ" "$LOG"
[[ ! -f "$AUB_TEST_SECURITY_WAS_CALLED" ]]
if grep -Fq -- "--password" "$TEST_SCRIPTS/sign-and-notarize.sh.example"; then
  echo "署名テンプレートにパスワード引数例が残っている。" >&2
  exit 1
fi

# 既存Developer ID署名でもHardened Runtimeとsecure timestampが必須。
export AI_USAGE_BUDDY_SIGNING_IDENTITY="Developer ID Application: Test Team (ABCDEFGHIJ)"
export AI_USAGE_BUDDY_TEAM_ID=ABCDEFGHIJ
export AI_USAGE_BUDDY_BUNDLE_ID=com.aiusagebuddy.app
unset AI_USAGE_BUDDY_NOTARY_PROFILE
export AUB_TEST_CODESIGN_STATE=developer
export AUB_TEST_STAPLER_FAIL=1
export AUB_TEST_SPCTL_FAIL=1
rm -f "$AUB_TEST_NOTARY_WAS_CALLED" "$AUB_TEST_STAPLE_WAS_CALLED"
bash "$TEST_SCRIPTS/sign-and-notarize.sh.example" --sign-only > "$LOG" 2>&1
grep -Fq "Developer ID署名済み（公証・ステープル未実施）" "$LOG"
grep -Fq "公証・ステープル未実施" "$RELEASE_DIR/RELEASE_NOTES.txt"
grep -Fq "公証・ステープル未実施" "$AUB_TEST_HDIUTIL_CAPTURE"
[[ ! -f "$AUB_TEST_NOTARY_WAS_CALLED" ]]
[[ ! -f "$AUB_TEST_STAPLE_WAS_CALLED" ]]
[[ ! -e "$TEST_ROOT/build/release" ]]
export AUB_TEST_STAPLER_FAIL=0
export AUB_TEST_SPCTL_FAIL=0
export AI_USAGE_BUDDY_NOTARY_PROFILE=test-profile

export AUB_TEST_CODESIGN_STATE=developer-no-runtime
rm -f "$AUB_TEST_NOTARY_WAS_CALLED" "$AUB_TEST_STAPLE_WAS_CALLED"
if bash "$TEST_SCRIPTS/sign-and-notarize.sh.example" > "$LOG" 2>&1; then
  echo "Hardened Runtimeの無い署名を公証へ進めてしまった。" >&2
  exit 1
fi
grep -Fq "Hardened Runtimeが確認できない" "$LOG"
[[ ! -f "$AUB_TEST_NOTARY_WAS_CALLED" ]]
export AUB_TEST_CODESIGN_STATE=developer-no-timestamp
if bash "$TEST_SCRIPTS/sign-and-notarize.sh.example" > "$LOG" 2>&1; then
  echo "secure timestampの無い署名を公証へ進めてしまった。" >&2
  exit 1
fi
grep -Fq "secure timestampが確認できない" "$LOG"
[[ ! -f "$AUB_TEST_NOTARY_WAS_CALLED" ]]

# top-level statusがRejectedなら、nested statusがAcceptedでもステープルしない。
export AUB_TEST_CODESIGN_STATE=developer
rm -f "$AUB_TEST_NOTARY_WAS_CALLED" "$AUB_TEST_STAPLE_WAS_CALLED"
if bash "$TEST_SCRIPTS/sign-and-notarize.sh.example" > "$LOG" 2>&1; then
  cat "$LOG" >&2
  echo "top-level statusがRejectedなのに公証済みとして続行した。" >&2
  exit 1
fi
[[ -f "$AUB_TEST_NOTARY_WAS_CALLED" ]]
[[ ! -f "$AUB_TEST_STAPLE_WAS_CALLED" ]]
grep -Fq "公証結果がAcceptedではない" "$LOG"

# top-level Acceptedのみが最終梱包へ進める。
export AUB_TEST_NOTARY_STATUS=Accepted
rm -f "$AUB_TEST_STAPLE_WAS_CALLED"
bash "$TEST_SCRIPTS/sign-and-notarize.sh.example" > "$LOG" 2>&1
grep -Fq "Developer ID署名・公証・ステープル検証済み" "$LOG"
[[ -f "$AUB_TEST_STAPLE_WAS_CALLED" ]]
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS.txt >/dev/null)

echo "Release script regression checks passed."
