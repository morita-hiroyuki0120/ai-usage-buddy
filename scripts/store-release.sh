#!/bin/bash
# Mac App Store signing workflow helper (install-profile / preflight / archive / export / verify / upload).
#
# Safety model:
#   - Subcommands that change state (install-profile, archive, export) print the command and stop
#     unless --execute is given (dry-run by default).
#   - upload additionally needs --i-have-approval; it never reads or stores credentials.
#   - Output goes to a NEW directory under build/. Existing files and directories are never overwritten.
#   - Private keys, provisioning profile bodies and credentials are never read or printed.
#     The profile is decoded in memory and only UUID / Team / application-identifier are compared.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TEAM="9HYDLV4RY2"
BID="com.aiusagebuddy.app.store"
PROFILE_NAME="AI Usage Buddy Mac App Store"
PROFILE_UUID_DEFAULT="12df9150-9fe1-4e9b-a2a1-ba399280778b"
PROFILE_SRC_DEFAULT="$HOME/Downloads/AI_Usage_Buddy_Mac_App_Store.provisionprofile"
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROJECT="$REPO_ROOT/Store/AIUsageBuddy.xcodeproj"
SCHEME="AIUsageBuddyStore"
CONFIG_JSON="$REPO_ROOT/config/EmbeddedAppServer.json"
PBXPROJ="$PROJECT/project.pbxproj"
APP_NAME="AI Usage Buddy.app"
HELPER_REL="Contents/Helpers/codex-app-server"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

usage() {
  cat <<'EOF'
usage: scripts/store-release.sh <subcommand> [options]

  install-profile [--profile PATH] [--uuid UUID] [--execute]
  preflight       [--inputs DIR] [--approval-sha SHA256] [--profile PATH] [--uuid UUID]
                  [--expect-version V] [--expect-build N]
  archive         [--inputs DIR] [--approval-sha SHA256] [--uuid UUID] [--identity NAME] [--execute]
  export          --archive PATH.xcarchive [--uuid UUID] [--installer-cert NAME] [--execute]
  verify          [--archive PATH.xcarchive] [--export DIR] [--inputs DIR] [--approval-sha SHA256]
  upload          --pkg PATH.pkg [--i-have-approval]    (prints commands only; never reads credentials)

Env: AI_USAGE_BUDDY_STORE_INPUTS, AI_USAGE_BUDDY_STORE_APPROVAL_SHA256 are used when the options are omitted.
EOF
}

die() { echo "store-release: error: $*" >&2; exit 2; }
ts() { date +%Y%m%d-%H%M%S; }
need_arg() { [ "$#" -ge 2 ] && [ -n "$2" ] || die "option $1 needs a value"; }

new_dir() { # create a brand-new directory; refuse if present
  local d="$1"
  [ ! -e "$d" ] && [ ! -L "$d" ] || die "output exists, refusing to overwrite: $d"
  mkdir -p "$(dirname "$d")"
  mkdir "$d"
}

# ---- profile (decoded in memory, only 3 fields are extracted) -------------------------------
profile_field() { # $1=decoded plist text, $2=plutil keypath
  printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null || true
}
profile_check() { # $1=file $2=expected uuid ; prints findings, returns 0 if all match
  local file="$1" want="$2" decoded uuid team appid ok=0
  decoded="$(security cms -D -i "$file" 2>/dev/null)" || { echo "cannot decode profile CMS"; return 1; }
  uuid="$(profile_field "$decoded" UUID)"
  team="$(profile_field "$decoded" TeamIdentifier.0)"
  appid="$(profile_field "$decoded" 'Entitlements.com\.apple\.application-identifier')"
  [ "$uuid" = "$want" ] || { echo "UUID mismatch (profile=$uuid expected=$want)"; ok=1; }
  [ "$team" = "$TEAM" ] || { echo "Team mismatch (profile=$team expected=$TEAM)"; ok=1; }
  [ "$appid" = "$TEAM.$BID" ] || { echo "application-identifier mismatch (profile=$appid)"; ok=1; }
  [ "$ok" -eq 0 ] && echo "profile matches UUID=$uuid Team=$team application-identifier=$appid"
  return "$ok"
}

# ---- project settings -----------------------------------------------------------------------
pbx_values() { grep -E "^[[:space:]]*$1 = " "$PBXPROJ" | sed -E 's/.*= "?([^";]*)"?;.*/\1/' | sort -u; }

# ---- identities (names / SHA-1 only) --------------------------------------------------------
dist_identities() { security find-identity -v -p codesigning 2>/dev/null | grep "Apple Distribution:.*($TEAM)" || true; }
installer_identities() { security find-identity -v 2>/dev/null | grep -E "(3rd Party Mac Developer Installer|Mac Installer Distribution):.*\($TEAM\)" || true; }

cmd_install_profile() {
  local src="$PROFILE_SRC_DEFAULT" uuid="$PROFILE_UUID_DEFAULT" execute=0
  while [ $# -gt 0 ]; do case "$1" in
    --profile) need_arg "$@"; src="$2"; shift 2;;
    --uuid) need_arg "$@"; uuid="$2"; shift 2;;
    --execute) execute=1; shift;;
    *) die "unknown option: $1";; esac; done
  [ -f "$src" ] && [ ! -L "$src" ] || die "profile not found (or symlink): $src"
  profile_check "$src" "$uuid" || die "profile does not match; not installing"
  local dest="$PROFILE_DIR/$uuid.provisionprofile"
  [ ! -e "$dest" ] || die "already installed, not overwriting: $dest"
  if [ "$execute" -ne 1 ]; then
    echo "[dry-run] would run: mkdir -p \"$PROFILE_DIR\" && cp -n \"$src\" \"$dest\""
    echo "[dry-run] add --execute to install"
    return 0
  fi
  mkdir -p "$PROFILE_DIR"
  cp -n "$src" "$dest"
  echo "installed: $dest"
}

cmd_preflight() {
  local inputs="${AI_USAGE_BUDDY_STORE_INPUTS:-}" sha="${AI_USAGE_BUDDY_STORE_APPROVAL_SHA256:-}"
  local src="$PROFILE_SRC_DEFAULT" uuid="$PROFILE_UUID_DEFAULT" ev="" eb=""
  while [ $# -gt 0 ]; do case "$1" in
    --inputs) need_arg "$@"; inputs="$2"; shift 2;;
    --approval-sha) need_arg "$@"; sha="$2"; shift 2;;
    --profile) need_arg "$@"; src="$2"; shift 2;;
    --uuid) need_arg "$@"; uuid="$2"; shift 2;;
    --expect-version) need_arg "$@"; ev="$2"; shift 2;;
    --expect-build) need_arg "$@"; eb="$2"; shift 2;;
    *) die "unknown option: $1";; esac; done
  local fails=0
  ok() { echo "  OK   $*"; }
  ng() { echo "  NG   $*"; fails=$((fails+1)); }

  echo "== Xcode"
  local xv; xv="$(xcodebuild -version 2>/dev/null | tr '\n' ' ')" && ok "$xv" || ng "xcodebuild unavailable (DEVELOPER_DIR=$DEVELOPER_DIR)"

  echo "== distribution status / approval receipt"
  local status
  status="$(/usr/bin/python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("distributionStatus",""))' "$CONFIG_JSON" 2>/dev/null || true)"
  [ "$status" = "ready" ] && ok "distributionStatus=ready" || ng "config/EmbeddedAppServer.json distributionStatus=${status:-unknown} (need ready after approved review)"
  if [ -z "$inputs" ]; then ng "approved inputs dir not given (--inputs / AI_USAGE_BUDDY_STORE_INPUTS)"
  elif [ ! -f "$inputs/approval.json" ]; then ng "approval.json not found in inputs dir"
  else
    local actual; actual="$(shasum -a 256 "$inputs/approval.json" | cut -d' ' -f1)"
    if [ -z "$sha" ]; then ng "approval SHA-256 not given (--approval-sha / AI_USAGE_BUDDY_STORE_APPROVAL_SHA256)"
    elif [ "$sha" != "$actual" ]; then ng "approval.json SHA-256 does not match the given value"
    else ok "approval.json hash matches"; fi
    /usr/bin/python3 -I - "$inputs/approval.json" "$uuid" <<'PY' && ok "receipt status/signing fields consistent" || ng "receipt status or signing fields wrong (status=approved-for-store-packaging, team, bundleID, profileSpecifier=UUID, profileUUID empty)"
import json, sys
r = json.load(open(sys.argv[1]))
s = r.get("signing", {})
assert r.get("status") == "approved-for-store-packaging"
assert r.get("review", {}).get("status") == "approved"
assert s.get("team") == "9HYDLV4RY2" and s.get("bundleID") == "com.aiusagebuddy.app.store"
# archive passes PROVISIONING_PROFILE_SPECIFIER=<UUID> only, so prepare.py needs these exact values
assert s.get("profileSpecifier") == sys.argv[2] and s.get("profileUUID") == ""
PY
  fi

  echo "== signing identities (names only)"
  local d i
  d="$(dist_identities)"; [ -n "$d" ] && ok "Apple Distribution: $(echo "$d" | sed -E 's/^ *[0-9]+\) //')" || ng "Apple Distribution identity for $TEAM not found in codesigning identities"
  [ "$(echo "$d" | grep -c . || true)" -le 1 ] || ng "multiple Apple Distribution identities; pass --identity <SHA-1> to archive"
  i="$(installer_identities)"; [ -n "$i" ] && ok "Installer: $(echo "$i" | sed -E 's/^ *[0-9]+\) //')" || ng "Mac Installer Distribution / 3rd Party Mac Developer Installer identity for $TEAM not found"

  echo "== provisioning profile"
  local installed="$PROFILE_DIR/$uuid.provisionprofile"
  [ -f "$src" ] && ok "downloaded profile exists: $src" || ng "downloaded profile not found: $src"
  if [ -f "$installed" ]; then ok "installed: $installed"; else ng "profile not installed (run install-profile --execute after approval)"; fi
  if [ -f "$src" ]; then profile_check "$src" "$uuid" >/dev/null && ok "profile UUID/Team/application-identifier match" || ng "profile UUID/Team/application-identifier mismatch"; fi

  echo "== project settings (Store/AIUsageBuddy.xcodeproj)"
  local v b t p
  v="$(pbx_values MARKETING_VERSION)"; b="$(pbx_values CURRENT_PROJECT_VERSION)"
  t="$(pbx_values DEVELOPMENT_TEAM)"; p="$(pbx_values PRODUCT_BUNDLE_IDENTIFIER)"
  [ "$(echo "$v" | grep -c .)" -eq 1 ] && ok "MARKETING_VERSION=$v" || ng "MARKETING_VERSION inconsistent: $(echo $v)"
  [ "$(echo "$b" | grep -c .)" -eq 1 ] && ok "CURRENT_PROJECT_VERSION=$b" || ng "CURRENT_PROJECT_VERSION inconsistent: $(echo $b)"
  [ "$t" = "$TEAM" ] && ok "DEVELOPMENT_TEAM=$t" || ng "DEVELOPMENT_TEAM=$(echo $t) (expected $TEAM)"
  [ "$p" = "$BID" ] && ok "PRODUCT_BUNDLE_IDENTIFIER=$p" || ng "PRODUCT_BUNDLE_IDENTIFIER=$(echo $p) (expected $BID)"
  [ -z "$ev" ] || { [ "$v" = "$ev" ] && ok "version matches --expect-version" || ng "version $v != expected $ev"; }
  [ -z "$eb" ] || { [ "$b" = "$eb" ] && ok "build matches --expect-build" || ng "build $b != expected $eb (must be higher than any build already uploaded)"; }

  echo
  if [ "$fails" -gt 0 ]; then echo "preflight: $fails blocker(s). NOT ready for archive."; return 1; fi
  echo "preflight: all checks passed."
}

cmd_archive() {
  local inputs="${AI_USAGE_BUDDY_STORE_INPUTS:-}" sha="${AI_USAGE_BUDDY_STORE_APPROVAL_SHA256:-}"
  local uuid="$PROFILE_UUID_DEFAULT" identity="Apple Distribution" execute=0
  while [ $# -gt 0 ]; do case "$1" in
    --inputs) need_arg "$@"; inputs="$2"; shift 2;;
    --approval-sha) need_arg "$@"; sha="$2"; shift 2;;
    --uuid) need_arg "$@"; uuid="$2"; shift 2;;
    --identity) need_arg "$@"; identity="$2"; shift 2;;
    --execute) execute=1; shift;;
    *) die "unknown option: $1";; esac; done
  if [ -n "$inputs" ] && [ -d "$inputs" ]; then inputs="$(cd "$inputs" && pwd -P)"; fi  # prepare.py requires an absolute canonical path
  local pf=0
  cmd_preflight --inputs "$inputs" --approval-sha "$sha" --uuid "$uuid" || pf=1
  local out="$REPO_ROOT/build/store-archive-$(ts)"
  # No -arch here: combining -arch with a generic/platform=macOS destination fails.
  local cmd=(xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release
    -destination 'generic/platform=macOS'
    -archivePath "$out/AIUsageBuddy.xcarchive" -derivedDataPath "$out/DerivedData"
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$TEAM"
    PROVISIONING_PROFILE_SPECIFIER="$uuid"
    AI_USAGE_BUDDY_STORE_INPUTS="$inputs")
  echo
  echo "archive command (env AI_USAGE_BUDDY_STORE_APPROVAL_SHA256 is exported; log goes to $out/archive.log):"
  printf '  '; printf '%q ' "${cmd[@]}"; echo
  if [ "$execute" -ne 1 ]; then echo "[dry-run] add --execute to run"; return 0; fi
  [ "$pf" -eq 0 ] || die "preflight failed; refusing to archive"
  new_dir "$out"
  AI_USAGE_BUDDY_STORE_APPROVAL_SHA256="$sha" "${cmd[@]}" 2>&1 | tee "$out/archive.log"
  echo "archive: $out/AIUsageBuddy.xcarchive"
}

cmd_export() {
  local archive="" uuid="$PROFILE_UUID_DEFAULT" inst="3rd Party Mac Developer Installer" execute=0
  while [ $# -gt 0 ]; do case "$1" in
    --archive) need_arg "$@"; archive="$2"; shift 2;;
    --uuid) need_arg "$@"; uuid="$2"; shift 2;;
    --installer-cert) need_arg "$@"; inst="$2"; shift 2;;
    --execute) execute=1; shift;;
    *) die "unknown option: $1";; esac; done
  [ -n "$archive" ] || die "--archive is required"
  [ -d "$archive" ] || die "archive not found: $archive"
  local top; top="$(ls "$archive/Products/Applications" 2>/dev/null || true)"
  [ "$top" = "$APP_NAME" ] || die "archive Products/Applications must contain only '$APP_NAME' (found: ${top:-nothing})"
  [ "$(ls "$archive/Products" | wc -l | tr -d ' ')" -eq 1 ] || die "archive Products has entries other than Applications"
  local out="$REPO_ROOT/build/store-export-$(ts)"
  local plist="$out/ExportOptions.plist"
  # method: Xcode 27.1 lists app-store-connect (app-store is deprecated).
  local cmd=(xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" -exportOptionsPlist "$plist")
  echo "ExportOptions.plist would contain: method=app-store-connect destination=export teamID=$TEAM signingStyle=manual"
  echo "  signingCertificate='Apple Distribution' installerSigningCertificate='$inst' provisioningProfiles={$BID: $uuid}"
  echo "  manageAppVersionAndBuildNumber=false uploadSymbols=false"
  printf '  '; printf '%q ' "${cmd[@]}"; echo
  if [ "$execute" -ne 1 ]; then echo "[dry-run] add --execute to run"; return 0; fi
  new_dir "$out"
  plutil -create xml1 "$plist"
  plutil -insert method -string app-store-connect "$plist"
  plutil -insert destination -string export "$plist"
  plutil -insert teamID -string "$TEAM" "$plist"
  plutil -insert signingStyle -string manual "$plist"
  plutil -insert signingCertificate -string "Apple Distribution" "$plist"
  plutil -insert installerSigningCertificate -string "$inst" "$plist"
  plutil -insert provisioningProfiles -dictionary "$plist"
  plutil -insert "provisioningProfiles.${BID//./\\.}" -string "$uuid" "$plist"  # dots in the bundle ID must be escaped
  plutil -insert manageAppVersionAndBuildNumber -bool NO "$plist"
  plutil -insert uploadSymbols -bool NO "$plist"
  plutil -lint "$plist"
  "${cmd[@]}" 2>&1 | tee "$out/export.log"
  echo "export: $out/export"
}

# ---- verify ---------------------------------------------------------------------------------
V_FAILS=0
vok() { echo "  OK   $*"; }
vng() { echo "  NG   $*"; V_FAILS=$((V_FAILS+1)); }
ent_get() { # $1=path $2=key
  local k; k="$(printf '%s' "$2" | sed 's/\./\\./g')"
  codesign -d --entitlements :- "$1" 2>/dev/null | plutil -extract "$k" raw -o - - 2>/dev/null || echo "<absent>"
}
ent_keys() { codesign -d --entitlements :- "$1" 2>/dev/null | plutil -convert json -o - - 2>/dev/null | /usr/bin/python3 -I -c 'import json,sys;print(" ".join(sorted(json.load(sys.stdin))))' 2>/dev/null || true; }

verify_app() { # $1=app path $2=label
  local app="$1" label="$2" info
  echo "== $label: $app"
  [ -d "$app" ] || { vng "app missing"; return; }
  codesign --verify --strict --verbose=2 "$app" 2>&1 | sed 's/^/       /' && vok "codesign --verify --strict" || vng "codesign verify failed"
  info="$(codesign -dvvv "$app" 2>&1)"
  echo "$info" | grep -E '^(Identifier|Authority|TeamIdentifier|Runtime|Timestamp|Format)' | sed 's/^/       /'
  echo "$info" | grep -q "^Identifier=$BID$" && vok "Identifier=$BID" || vng "Identifier != $BID"
  echo "$info" | grep -q "^TeamIdentifier=$TEAM$" && vok "TeamIdentifier=$TEAM" || vng "TeamIdentifier != $TEAM"
  echo "$info" | grep -q "^Authority=Apple Distribution:" && vok "signed by Apple Distribution" || vng "not signed by Apple Distribution"
  echo "$info" | grep -q 'flags=.*runtime' && vok "hardened runtime" || vng "hardened runtime missing"
  echo "       parent entitlement keys: $(ent_keys "$app")"
  [ "$(ent_get "$app" com.apple.security.app-sandbox)" = "true" ] && vok "app-sandbox" || vng "app-sandbox not true"
  [ "$(ent_get "$app" com.apple.security.network.client)" = "true" ] && vok "network.client" || vng "network.client not true"
  [ "$(ent_get "$app" com.apple.security.network.server)" = "true" ] && vok "network.server" || vng "network.server not true"
  [ "$(ent_get "$app" com.apple.security.get-task-allow)" != "true" ] && vok "get-task-allow not true" || vng "get-task-allow=true"
  local appid; appid="$(ent_get "$app" com.apple.application-identifier)"
  [ "$appid" = "$TEAM.$BID" ] && vok "com.apple.application-identifier=$appid" || vng "com.apple.application-identifier=$appid"
  [ -f "$app/Contents/embedded.provisionprofile" ] && vok "embedded.provisionprofile present" || vng "embedded.provisionprofile missing"
  echo "       version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist") build=$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")"
  local h="$app/$HELPER_REL"
  if [ -f "$h" ]; then
    codesign --verify --strict "$h" 2>/dev/null && vok "helper codesign strict" || vng "helper codesign failed"
    local hi; hi="$(codesign -dvvv "$h" 2>&1)"
    echo "$hi" | grep -q "^Identifier=$BID.codex-app-server$" && vok "helper Identifier" || vng "helper Identifier mismatch"
    echo "$hi" | grep -q "^TeamIdentifier=$TEAM$" && vok "helper Team" || vng "helper Team mismatch"
    echo "$hi" | grep -q "^Authority=Apple Distribution:" && vok "helper signed by Apple Distribution" || vng "helper not Apple Distribution"
    echo "$hi" | grep -q 'flags=.*runtime' && vok "helper hardened runtime" || vng "helper runtime missing"
    local hk; hk="$(ent_keys "$h")"
    [ "$hk" = "com.apple.security.app-sandbox com.apple.security.inherit" ] && vok "helper entitlements = sandbox + inherit only" || vng "helper entitlements: $hk"
  else
    vng "helper missing: $HELPER_REL"
  fi
  [ -d "$app/Contents/Resources/StoreNotices" ] && vok "StoreNotices present" || vng "StoreNotices missing"
}

cmd_verify() {
  local archive="" exp="" inputs="${AI_USAGE_BUDDY_STORE_INPUTS:-}" sha="${AI_USAGE_BUDDY_STORE_APPROVAL_SHA256:-}"
  while [ $# -gt 0 ]; do case "$1" in
    --archive) need_arg "$@"; archive="$2"; shift 2;;
    --export) need_arg "$@"; exp="$2"; shift 2;;
    --inputs) need_arg "$@"; inputs="$2"; shift 2;;
    --approval-sha) need_arg "$@"; sha="$2"; shift 2;;
    *) die "unknown option: $1";; esac; done
  [ -n "$archive$exp" ] || die "give --archive and/or --export"
  if [ -n "$inputs" ] && [ -d "$inputs" ]; then inputs="$(cd "$inputs" && pwd -P)"; fi  # prepare.py requires an absolute canonical path
  local out="$REPO_ROOT/build/store-verify-$(ts)"
  new_dir "$out"
  echo "verify output dir: $out"
  if [ -n "$archive" ]; then
    echo "== archive layout"
    local apps; apps="$(ls "$archive/Products/Applications" 2>/dev/null || true)"
    [ "$apps" = "$APP_NAME" ] && vok "Products/Applications contains only $APP_NAME" || vng "Products/Applications: ${apps:-empty}"
    [ "$(ls "$archive/Products" | tr '\n' ' ')" = "Applications " ] && vok "Products contains only Applications (no separate helper install)" || vng "unexpected entries in Products"
    verify_app "$archive/Products/Applications/$APP_NAME" "archive app"
  fi
  if [ -n "$exp" ]; then
    local pkg; pkg="$(ls "$exp"/*.pkg 2>/dev/null | head -1 || true)"
    echo "== pkg"
    if [ -z "$pkg" ]; then vng "no .pkg in $exp"; else
      pkgutil --check-signature "$pkg" 2>&1 | sed 's/^/       /'
      pkgutil --check-signature "$pkg" 2>&1 | grep -qE "(3rd Party Mac Developer Installer|Mac Installer Distribution):.*\($TEAM\)" && vok "pkg signed by installer cert of $TEAM" || vng "pkg installer signature not as expected"
      pkgutil --expand-full "$pkg" "$out/pkg-expanded" && vok "pkg expanded (new dir)" || vng "pkg expand failed"
      local papp; papp="$(find "$out/pkg-expanded" -maxdepth 4 -name "$APP_NAME" -type d | head -1)"
      if [ -n "$papp" ]; then
        verify_app "$papp" "exported app"
        if [ -n "$inputs" ] && [ -n "$sha" ]; then
          AI_USAGE_BUDDY_STORE_INPUTS="$inputs" AI_USAGE_BUDDY_STORE_APPROVAL_SHA256="$sha" \
            bash "$REPO_ROOT/scripts/prepare-store-archive.sh" --verify-app --app "$papp" && vok "prepare-store-archive --verify-app" || vng "prepare-store-archive --verify-app rejected"
        else
          echo "  --   prepare-store-archive --verify-app skipped (no --inputs / --approval-sha)"
        fi
      else vng "no $APP_NAME inside pkg"; fi
    fi
  fi
  echo
  [ "$V_FAILS" -eq 0 ] && echo "verify: all checks passed." || { echo "verify: $V_FAILS failure(s)."; return 1; }
}

cmd_upload() {
  local pkg="" approved=0
  while [ $# -gt 0 ]; do case "$1" in
    --pkg) need_arg "$@"; pkg="$2"; shift 2;;
    --i-have-approval) approved=1; shift;;
    *) die "unknown option: $1";; esac; done
  [ -n "$pkg" ] || die "--pkg is required"
  [ -f "$pkg" ] || die "pkg not found: $pkg"
  cat <<EOF
Upload is never run by this script. Run one of these yourself after approval.
Credentials are yours to supply; this script neither reads nor stores them.

1) Validate (recommended first):
   xcrun altool --validate-app -f "$pkg" <AUTH>
2) Upload:
   xcrun altool --upload-app -f "$pkg" <AUTH>
3) Or Transporter (GUI/CLI) / Xcode Organizer: sign in interactively and deliver the .pkg or the archive.
4) Or re-export the archive with destination=upload in ExportOptions.plist (xcodebuild -exportArchive).

<AUTH> is one of:
   --api-key <KEY_ID> --api-issuer <ISSUER_ID>        (AuthKey_<KEY_ID>.p8 placed by you under ~/.appstoreconnect/private_keys)
   -u <apple-id> -p @keychain:<item-you-stored>      (app-specific password stored by you in Keychain)
Note: bundle ID / Apple ID 6826562310 are read from the pkg; the build number must be higher than any previous upload.
EOF
  if [ "$approved" -ne 1 ]; then echo; echo "[dry-run] --i-have-approval not given: nothing else to do."; return 0; fi
  echo; echo "--i-have-approval acknowledged. Copy the command above and run it in your own terminal (this script will not execute it)."
}

main() {
  [ $# -ge 1 ] || { usage; exit 2; }
  local sub="$1"; shift
  case "$sub" in
    install-profile) cmd_install_profile "$@";;
    preflight) cmd_preflight "$@";;
    archive) cmd_archive "$@";;
    export) cmd_export "$@";;
    verify) cmd_verify "$@";;
    upload) cmd_upload "$@";;
    -h|--help|help) usage;;
    *) usage; exit 2;;
  esac
}
main "$@"
