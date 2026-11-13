#!/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$ROOT/Store/AIUsageBuddy.xcodeproj"
SCHEME="AIUsageBuddyStore"
BUNDLE_ID="com.aiusagebuddy.app.store.validation"
TEAM_ID="9HYDLV4RY2"
UPSTREAM_TEAM_ID="2DC432GLL2"
EXPECTED_SHA256="6d42b6a34bbe05d083e66b0dec65e23db77b2c87a82435882acfda043aab1e06"
RELEASE_URL="https://github.com/openai/codex/releases/download/rust-v0.167.2/codex-app-server-aarch64-apple-darwin.tar.gz"
CACHED_TARBALL="$ROOT/build/dependency-audit/codex-0.167.2/codex-app-server-aarch64-apple-darwin.tar.gz"
HELPER_ENTITLEMENTS="$ROOT/Tools/StoreRuntimeValidation/codex-app-server.entitlements"
APP_ENTITLEMENTS="$ROOT/Store/AIUsageBuddyStore.entitlements"
DEVELOPER_DIR_PATH="/Applications/Xcode.app/Contents/Developer"

fail() {
    printf 'Store runtime validation: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf '%s\n' \
        'Usage:' \
        '  bash scripts/validate-store-runtime.sh --prepare' \
        '  bash scripts/validate-store-runtime.sh --prepare-interactive' \
        '  bash scripts/validate-store-runtime.sh --prepare-keyring-interactive' \
        '  bash scripts/validate-store-runtime.sh --launch-after-go /absolute/path/to/AI\ Usage\ Buddy.app'
}

verify_team() {
    local target="$1"
    local expected_team="$2"
    local details actual_team
    details="$(/usr/bin/codesign -dv --verbose=4 "$target" 2>&1)" || fail "could not inspect signature: $target"
    actual_team="$(printf '%s\n' "$details" | /usr/bin/sed -n 's/^TeamIdentifier=//p' | /usr/bin/tail -n 1)"
    [[ "$actual_team" == "$expected_team" ]] || fail "unexpected signing team: $target"
}

verify_entitlements() {
    local target="$1"
    local destination="$2"
    /usr/bin/codesign -d --entitlements :- "$target" > "$destination" 2>/dev/null \
        || fail "could not read signed entitlements: $target"
}

verify_signed_entitlements() {
    local target="$1"
    local profile="$2"
    if ! /usr/bin/python3 - "$target" "$profile" <<'PY'
import plistlib
import subprocess
import sys

profiles = {
    "app": {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
    },
    "helper": {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.inherit": True,
    },
}
target, profile = sys.argv[1:]
if profile not in profiles:
    raise SystemExit(1)
result = subprocess.run(
    ["/usr/bin/codesign", "-d", "--entitlements", ":-", target],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    check=False,
)
try:
    actual = plistlib.loads(result.stdout) if result.returncode == 0 else None
except Exception:
    actual = None
if actual != profiles[profile]:
    raise SystemExit(1)
PY
    then
        fail "signed $profile entitlements do not match the expected profile"
    fi
}

prepare() {
    local mode="${1:-validation}"
    local bundle_id="$BUNDLE_ID"
    local artifact_prefix='store-validation'
    local display_name='AI Usage Buddy'
    local compilation_conditions='$(inherited) AI_USAGE_BUDDY_APP_STORE AI_USAGE_BUDDY_RUNTIME_VALIDATION'
    if [[ "$mode" == 'interactive' ]]; then
        bundle_id='com.aiusagebuddy.app.store.localtest'
        artifact_prefix='store-interactive'
        compilation_conditions='$(inherited) AI_USAGE_BUDDY_APP_STORE'
    elif [[ "$mode" == 'keyring-interactive' ]]; then
        bundle_id='com.aiusagebuddy.app.store.keyringtest'
        artifact_prefix='store-keyring-interactive'
        display_name='AI Usage Buddy Keychain検証'
        compilation_conditions='$(inherited) AI_USAGE_BUDDY_APP_STORE'
    elif [[ "$mode" != 'validation' ]]; then
        fail 'unknown prepare profile'
    fi

    [[ -d "$PROJECT" ]] || fail 'Store Xcode project is missing'
    [[ -f "$HELPER_ENTITLEMENTS" && -f "$APP_ENTITLEMENTS" ]] || fail 'entitlements file is missing'
    [[ -f "$CACHED_TARBALL" ]] || fail 'the pinned helper archive is not present in the local audit folder'

    local archive_sha
    archive_sha="$(/usr/bin/shasum -a 256 "$CACHED_TARBALL" | /usr/bin/awk '{print $1}')"
    [[ "$archive_sha" == "$EXPECTED_SHA256" ]] || fail 'the pinned helper archive hash does not match'

    local output_root derived_data helper_source helper_destination app_path info_plist
    /bin/mkdir -p "$ROOT/build"
    output_root="$(/usr/bin/mktemp -d "$ROOT/build/$artifact_prefix.XXXXXX")"
    derived_data="$(/usr/bin/mktemp -d "$ROOT/build/$artifact_prefix-derived.XXXXXX")"
    helper_source="$output_root/source/codex-app-server"
    helper_destination="$output_root/AI Usage Buddy.app/Contents/Helpers/codex-app-server"
    app_path="$output_root/AI Usage Buddy.app"
    info_plist="$app_path/Contents/Info.plist"
    /bin/mkdir -p "$output_root/source"

    /usr/bin/python3 - "$CACHED_TARBALL" "$helper_source" <<'PY'
import os
import pathlib
import shutil
import sys
import tarfile

archive_path, destination = sys.argv[1:]
expected_name = "codex-app-server-aarch64-apple-darwin"
with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    candidates = []
    for member in members:
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit("unsafe archive path")
        if member.issym() or member.islnk() or member.isdev():
            raise SystemExit("unsupported archive entry")
        if member.isfile() and path.name == expected_name:
            candidates.append(member)
    if len(candidates) != 1:
        raise SystemExit("expected exactly one standalone app-server binary")
    source = archive.extractfile(candidates[0])
    if source is None:
        raise SystemExit("app-server archive member is unreadable")
    with source, open(destination, "xb") as output:
        shutil.copyfileobj(source, output)
os.chmod(destination, 0o755)
PY

    /usr/bin/codesign --verify --strict --verbose=4 "$helper_source"
    verify_team "$helper_source" "$UPSTREAM_TEAM_ID"

    local identity_output signing_identity identity_count
    identity_output="$(/usr/bin/security find-identity -v -p codesigning)" \
        || fail 'could not enumerate available code-signing identities'
    signing_identity="$(printf '%s\n' "$identity_output" | /usr/bin/sed -nE \
        's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) "Developer ID Application:.* \(9HYDLV4RY2\)"$/\1/p')"
    unset identity_output
    identity_count="$(printf '%s\n' "$signing_identity" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
    [[ "$identity_count" == '1' ]] || fail 'exactly one valid Developer ID Application identity for the configured team is required'

    if ! DEVELOPER_DIR="$DEVELOPER_DIR_PATH" /usr/bin/xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        ARCHS=arm64 \
        MARKETING_VERSION=1.0 \
        CURRENT_PROJECT_VERSION=2 \
        PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
        INFOPLIST_KEY_CFBundleDisplayName="$display_name" \
        SWIFT_ACTIVE_COMPILATION_CONDITIONS="$compilation_conditions" \
        build > "$output_root/xcodebuild.log" 2>&1; then
        /usr/bin/tail -n 100 "$output_root/xcodebuild.log" >&2
        fail 'validation app build failed; build log is in the temporary output folder'
    fi

    local built_app
    built_app="$derived_data/Build/Products/Release/AI Usage Buddy.app"
    [[ -d "$built_app" ]] || fail 'the validation app product was not produced'
    /usr/bin/ditto "$built_app" "$app_path"

    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" == "$bundle_id" ]] \
        || fail 'validation bundle identifier was not generated'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist")" == "$display_name" ]] \
        || fail 'local test display name was not generated'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" == '1.0' ]] \
        || fail 'candidate marketing version was not generated'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" == '2' ]] \
        || fail 'candidate build version was not generated'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info_plist")" == 'true' ]] \
        || fail 'LSUIElement is not enabled'

    /bin/mkdir -p "$(/usr/bin/dirname "$helper_destination")"
    /bin/cp "$helper_source" "$helper_destination"
    /bin/chmod 755 "$helper_destination"
    /usr/bin/codesign --force --options runtime --timestamp=none \
        --entitlements "$HELPER_ENTITLEMENTS" --sign "$signing_identity" "$helper_destination"
    /usr/bin/codesign --verify --strict --verbose=4 "$helper_destination"
    verify_team "$helper_destination" "$TEAM_ID"
    verify_entitlements "$helper_destination" "$output_root/helper-signed-entitlements.plist"
    /usr/bin/python3 - "$output_root/helper-signed-entitlements.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.inherit": True,
}
if entitlements != expected:
    raise SystemExit("helper entitlements do not match the sandbox inheritance profile")
PY

    /usr/bin/codesign --force --options runtime --timestamp=none \
        --entitlements "$APP_ENTITLEMENTS" --sign "$signing_identity" "$app_path"
    /usr/bin/codesign --verify --strict --verbose=4 "$app_path"
    verify_team "$app_path" "$TEAM_ID"
    verify_entitlements "$app_path" "$output_root/app-signed-entitlements.plist"
    /usr/bin/python3 - "$output_root/app-signed-entitlements.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.network.client": True,
}
if entitlements != expected:
    raise SystemExit("app entitlements do not match the Store sandbox profile")
PY

    /usr/bin/python3 - "$app_path" "$output_root/prepared-manifest.json" "$bundle_id" "$TEAM_ID" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import sys

app_path, manifest_path, bundle_id, team_id = sys.argv[1:]
app = pathlib.Path(app_path).resolve(strict=True)
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
executable_name = info.get("CFBundleExecutable")
if info.get("CFBundleIdentifier") != bundle_id or not isinstance(executable_name, str) or "/" in executable_name:
    raise SystemExit("prepared app metadata is invalid")
files = {
    "appExecutable": app / "Contents/MacOS" / executable_name,
    "helper": app / "Contents/Helpers/codex-app-server",
}
hashes = {}
for name, path in files.items():
    if path.is_symlink() or not path.is_file():
        raise SystemExit("prepared code path is invalid")
    hashes[name + "SHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {
    "schemaVersion": 1,
    "bundleIdentifier": bundle_id,
    "teamIdentifier": team_id,
    "appPath": str(app),
    **hashes,
}
with open(manifest_path, "x", encoding="utf-8") as output:
    json.dump(manifest, output, sort_keys=True)
    output.write("\n")
PY
    [[ -f "$output_root/prepared-manifest.json" ]] || fail 'prepared artifact manifest was not written'

    local notice_dir
    notice_dir="$ROOT/build/dependency-audit/codex-0.167.2/source-licenses"
    [[ -f "$notice_dir/LICENSE" && -f "$notice_dir/NOTICE" ]] || fail 'pinned helper license or notice is missing'
    /bin/mkdir -p "$output_root/ThirdPartyNotices/codex-app-server-0.167.2"
    /bin/cp "$notice_dir/LICENSE" "$notice_dir/NOTICE" "$output_root/ThirdPartyNotices/codex-app-server-0.167.2/"
    /bin/cp "$ROOT/Tools/StoreRuntimeValidation/LOCAL-VALIDATION-ONLY.txt" "$output_root/"

    printf 'Prepared local %s app (%s): %s\n' "$mode" "$bundle_id" "$app_path"
    printf 'Separate DerivedData: %s\n' "$derived_data"
    printf 'No app or helper was launched.\n'
}

launch_after_go() {
    [[ "$#" == '1' ]] || fail '--launch-after-go requires one app bundle path'
    local app_path info_plist artifact_root helper_path run_uuid report_path
    app_path="$(/usr/bin/python3 - "$1" "$ROOT/build" 2>/dev/null <<'PY'
import pathlib
import sys

provided = pathlib.Path(sys.argv[1]).absolute()
app = provided.resolve(strict=True)
build_root = pathlib.Path(sys.argv[2]).resolve(strict=True)
if provided != app or app.name != "AI Usage Buddy.app" or not app.is_dir():
    raise SystemExit(1)
artifact_root = app.parent
if artifact_root.parent != build_root or not artifact_root.name.startswith("store-validation."):
    raise SystemExit(1)
print(app)
PY
)" || fail 'app path is not a real prepared bundle under the validation output folder'
    artifact_root="$(dirname -- "$app_path")"
    info_plist="$app_path/Contents/Info.plist"
    [[ -d "$app_path" && -f "$info_plist" ]] || fail 'prepared app bundle was not found'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" == "$BUNDLE_ID" ]] \
        || fail 'app bundle identifier is not the validation-only identifier'

    if ! /usr/bin/python3 - "$app_path" "$artifact_root/prepared-manifest.json" "$BUNDLE_ID" "$TEAM_ID" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import sys

app_path, manifest_path, bundle_id, team_id = sys.argv[1:]
app = pathlib.Path(app_path)
manifest_file = pathlib.Path(manifest_path)
if manifest_file.is_symlink() or not manifest_file.is_file() or manifest_file.parent != app.parent:
    raise SystemExit(1)
with manifest_file.open("r", encoding="utf-8") as source:
    manifest = json.load(source)
expected_keys = {"schemaVersion", "bundleIdentifier", "teamIdentifier", "appPath", "appExecutableSHA256", "helperSHA256"}
if not isinstance(manifest, dict) or set(manifest) != expected_keys:
    raise SystemExit(1)
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
executable_name = info.get("CFBundleExecutable")
if not isinstance(executable_name, str) or not executable_name or "/" in executable_name:
    raise SystemExit(1)
if (
    manifest.get("schemaVersion") != 1
    or manifest.get("bundleIdentifier") != bundle_id
    or manifest.get("teamIdentifier") != team_id
    or manifest.get("appPath") != str(app)
    or info.get("CFBundleIdentifier") != bundle_id
):
    raise SystemExit(1)
for relative_path, hash_key in (
    ("Contents/MacOS/" + executable_name, "appExecutableSHA256"),
    ("Contents/Helpers/codex-app-server", "helperSHA256"),
):
    target = app / relative_path
    if target.is_symlink() or not target.is_file():
        raise SystemExit(1)
    if hashlib.sha256(target.read_bytes()).hexdigest() != manifest.get(hash_key):
        raise SystemExit(1)
PY
    then
        fail 'prepared app does not match its local hash manifest'
    fi

    /usr/bin/codesign --verify --strict --verbose=4 "$app_path"
    verify_team "$app_path" "$TEAM_ID"
    verify_signed_entitlements "$app_path" app
    helper_path="$app_path/Contents/Helpers/codex-app-server"
    [[ -f "$helper_path" && ! -L "$helper_path" ]] || fail 'prepared helper is missing or redirected'
    /usr/bin/codesign --verify --strict --verbose=4 "$helper_path"
    verify_team "$helper_path" "$TEAM_ID"
    verify_signed_entitlements "$helper_path" helper

    run_uuid="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
    if ! /usr/bin/open -n -W "$app_path" --args --run-uuid "$run_uuid"; then
        fail 'LaunchServices could not complete the validation run'
    fi
    report_path="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/AI Usage Buddy/StoreRuntimeValidation/$run_uuid/Report.json"
    if ! /usr/bin/python3 - "$report_path" "$run_uuid" "$BUNDLE_ID" <<'PY'
import json
import pathlib
import sys
import uuid

report_path, expected_run_uuid, bundle_id = sys.argv[1:]
path = pathlib.Path(report_path).absolute()
try:
    resolved = path.resolve(strict=True)
except Exception:
    raise SystemExit(1)
if path != resolved or path.name != "Report.json" or path.parent.name.lower() != expected_run_uuid.lower():
    raise SystemExit(1)
try:
    with path.open("r", encoding="utf-8") as source:
        report = json.load(source)
except Exception:
    raise SystemExit(1)
required = {
    "schemaVersion", "runUUID", "bundleIdentifier", "statusCode",
    "sandboxContainerValidated", "initializeSucceeded", "accountReadSucceeded",
    "unexpectedQuotaResponse", "shutdownCompleted", "ownedProcessIDs",
}
optional = {"accountIsNil", "requiresOpenAIAuth", "rateLimitsRequiresAuthentication", "rateLimitRPCErrorCode"}
if not isinstance(report, dict) or not required.issubset(report) or not set(report).issubset(required | optional):
    raise SystemExit(1)
try:
    actual_run_uuid = str(uuid.UUID(report["runUUID"])).lower()
    requested_run_uuid = str(uuid.UUID(expected_run_uuid)).lower()
except Exception:
    raise SystemExit(1)
if (
    actual_run_uuid != requested_run_uuid
    or report.get("schemaVersion") != 1
    or report.get("bundleIdentifier") != bundle_id
    or report.get("statusCode") != 0
    or report.get("sandboxContainerValidated") is not True
    or report.get("initializeSucceeded") is not True
    or report.get("accountReadSucceeded") is not True
    or report.get("accountIsNil") is not True
    or report.get("requiresOpenAIAuth") is not True
    or report.get("rateLimitsRequiresAuthentication") is not True
    or report.get("unexpectedQuotaResponse") is not False
    or report.get("shutdownCompleted") is not True
    or report.get("ownedProcessIDs") != []
):
    raise SystemExit(1)
if "rateLimitRPCErrorCode" in report and report["rateLimitRPCErrorCode"] is not None:
    if type(report["rateLimitRPCErrorCode"]) is not int:
        raise SystemExit(1)
print("Runtime validation report: PASS (fixed fields only; owned processes stopped)")
PY
    then
        fail 'validation report is missing, unsafe, or does not show a clean successful run'
    fi
}

case "${1:-}" in
    --prepare)
        [[ "$#" == '1' ]] || { usage >&2; exit 64; }
        prepare validation
        ;;
    --prepare-interactive)
        [[ "$#" == '1' ]] || { usage >&2; exit 64; }
        prepare interactive
        ;;
    --prepare-keyring-interactive)
        [[ "$#" == '1' ]] || { usage >&2; exit 64; }
        prepare keyring-interactive
        ;;
    --launch-after-go)
        shift
        launch_after_go "$@"
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
