"""Offline, fail-closed packaging. Never runs the embedded executable."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import tarfile

REPO = Path(__file__).resolve().parents[2]
TEAM = "9HYDLV4RY2"
BID = "com.aiusagebuddy.app.store"
COMMIT = "83086188ae0614bd882818ff1aa23f3194962012"
ARCHIVE_SHA = "8165de84cc8e436d46d5e52fe6b68de053ba729c543e6310a1bd41e881cf4c37"
MEMBER = "codex-app-server-aarch64-apple-darwin"
HELPER_ID = BID + ".codex-app-server"
CHILD = {"com.apple.security.app-sandbox": True, "com.apple.security.inherit": True}
PARENT = {"com.apple.security.app-sandbox": True,
          "com.apple.security.network.client": True, "com.apple.security.network.server": True}
ROOT_HASHES = {"LICENSE": "d17f227e4df5da1600391338865ce0f3055211760a36688f816941d58232d8dc",
               "NOTICE": "9d71575ecfd9a843fc1677b0efb08053c6ba9fd686a0de1a6f5382fd3c220915"}
PAYLOADS = {"App-LICENSE", "LICENSE", "NOTICE", "THIRD-PARTY-NOTICES.txt", "SOURCE-AVAILABILITY.txt"}


class Rejected(Exception):
    pass


def require(condition, code):
    if not condition:
        raise Rejected(code)


def safe_path(value):
    """Reject symlinks in every component, including a nonexistent final component."""
    path = Path(value)
    require(path.is_absolute() and ".." not in path.parts, "unsafe-path")
    for item in (path, *path.parents):
        require(not item.is_symlink(), "symlink-path")
    require(path.resolve() == path, "noncanonical-path")
    return path


def regular(path):
    path = safe_path(path)
    require(stat.S_ISREG(path.stat().st_mode), "not-regular-file")
    return path


def digest(path):
    hasher = hashlib.sha256()
    with regular(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def load(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate-json-key")
            result[key] = value
        return result
    return json.loads(regular(path).read_bytes(), object_pairs_hook=unique)


def checked_file(root, record):
    relative = PurePosixPath(record["path"])
    require(not relative.is_absolute() and relative.parts and
            all(part not in (".", "..") for part in relative.parts), "unsafe-input-path")
    path = regular(root / relative)
    require(path.is_relative_to(root), "input-escape")
    require(path.stat().st_size == record["size"] and record["size"] > 0 and
            digest(path) == record["sha256"], "input-hash-mismatch")
    return path


def approved_inputs(config_path, root, approval_sha):
    root = safe_path(root)
    config = load(config_path)
    require(config["version"] == "0.163.0" and config["tag"] == "rust-v0.163.0" and
            config["sourceCommit"] == COMMIT and config["artifact"]["sha256"] == ARCHIVE_SHA,
            "source-pin-mismatch")
    require(config["distributionStatus"] == "ready", "distribution-not-ready")
    approval_path = root / "approval.json"
    require(re.fullmatch(r"[0-9a-f]{64}", approval_sha or "") and
            digest(approval_path) == approval_sha, "approval-pin-mismatch")
    approval = load(approval_path)
    require(approval["schemaVersion"] == 1 and approval["status"] == "approved-for-store-packaging" and
            approval["configSHA256"] == digest(config_path) and
            approval["artifactSHA256"] == ARCHIVE_SHA and approval["sourceCommit"] == COMMIT,
            "approval-binding-mismatch")
    review = approval["review"]
    require(review["status"] == "approved" and bool(review["reference"].strip()) and
            bool(review["approvedAt"].strip()),
            "review-incomplete")
    require(set(approval["payloads"]) == PAYLOADS, "payload-set-mismatch")
    files = {name: checked_file(root, record) for name, record in approval["payloads"].items()}
    for name, expected in ROOT_HASHES.items():
        require(digest(files[name]) == expected, "root-license-pin-mismatch")
    require(digest(files["App-LICENSE"]) == digest(REPO / "LICENSE"), "app-license-mismatch")
    artifact = checked_file(root, approval["artifact"])
    require(digest(artifact) == ARCHIVE_SHA, "artifact-pin-mismatch")
    require(approval["signing"]["team"] == TEAM and approval["signing"]["bundleID"] == BID,
            "signing-approval-mismatch")
    require(all(isinstance(approval["signing"][key], str) for key in
                ("profileSpecifier", "profileUUID")), "profile-setting-type")
    return approval, artifact, files


def signing_environment(env, approval):
    require(env.get("CONFIGURATION") == "Release" and env.get("ACTION") == "install" and
            env.get("DEPLOYMENT_POSTPROCESSING") == "YES", "not-release-archive")
    require(env.get("DEVELOPMENT_TEAM") == TEAM and env.get("PRODUCT_BUNDLE_IDENTIFIER") == BID and
            env.get("SKIP_INSTALL") == "NO" and env.get("ENABLE_HARDENED_RUNTIME") == "YES" and
            env.get("CODE_SIGNING_ALLOWED") == "YES", "signing-settings-mismatch")
    require(re.fullmatch(r"[0-9A-Fa-f]{40}", env.get("EXPANDED_CODE_SIGN_IDENTITY", "")) and
            env.get("EXPANDED_CODE_SIGN_IDENTITY_NAME", "").startswith("Apple Distribution:") and
            env.get("EXPANDED_CODE_SIGN_IDENTITY_NAME", "").endswith("(" + TEAM + ")"),
            "apple-distribution-required")
    flags = env.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
    require("AI_USAGE_BUDDY_APP_STORE" in flags and
            "AI_USAGE_BUDDY_RUNTIME_VALIDATION" not in flags, "not-production-target")
    # Empty is valid when Xcode's signing workflow needs no profile. No local profile is read.
    require(env.get("PROVISIONING_PROFILE_SPECIFIER", "") == approval["signing"]["profileSpecifier"],
            "profile-setting-mismatch")
    require(env.get("PROVISIONING_PROFILE", "") == approval["signing"]["profileUUID"],
            "profile-setting-mismatch")


def run(command):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    require(result.returncode == 0, "codesign-failed")
    return result


def verify_entitlements(actual, expected):
    require(isinstance(actual, dict) and
            all(actual.get(key) is True for key in expected), "entitlements-mismatch")
    if expected == CHILD:
        require(set(actual) == set(CHILD), "child-entitlements-mismatch")
        return
    # Distribution profiles may add identity entitlements. Bind every permitted value;
    # do not accept arbitrary extra grants, debugging, or wildcard access groups.
    identity = TEAM + "." + BID
    optional = {"com.apple.application-identifier": identity,
                "application-identifier": identity,
                "com.apple.developer.team-identifier": TEAM,
                "keychain-access-groups": [identity],
                "com.apple.security.get-task-allow": False,
                "get-task-allow": False}
    for key in set(actual) - set(expected):
        require(key in optional and type(actual[key]) is type(optional[key]) and
                actual[key] == optional[key], "parent-entitlements-mismatch")


def verify_signature(path, identifier, entitlements, final=True):
    run(["/usr/bin/codesign", "--verify", "--strict", str(path)])
    info = run(["/usr/bin/codesign", "-d", "--verbose=4", str(path)]).stderr.decode("utf-8")
    lines = info.splitlines()
    require("Identifier=" + identifier in lines and "(runtime)" in info, "signature-pattern-mismatch")
    if final:
        require("TeamIdentifier=" + TEAM in lines and
                any(line.startswith("Authority=Apple Distribution:") for line in lines),
                "distribution-signature-mismatch")
    result = run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)])
    verify_entitlements(plistlib.loads(result.stdout), entitlements)


def extract(archive, destination):
    # Inspect every member before writing; no extractall, links, or duplicate names.
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        require(len(members) == 1 and members[0].name == MEMBER and members[0].isfile() and
                0 < members[0].size <= 300 * 1024 * 1024, "unsafe-archive-members")
        with stream.extractfile(members[0]) as source, destination.open("xb") as target:
            while block := source.read(1024 * 1024):
                target.write(block)
    destination.chmod(0o755)


def stage(derived, approval_sha, approval, artifact, files):
    derived = safe_path(derived)
    require(derived.is_dir() and len(derived.parts) >= 5 and derived != REPO and
            derived != Path.home(), "unsafe-derived-directory")
    target = derived / "StorePackaging"
    # Fresh DerivedData required; partial failures deliberately cannot be reused.
    target.mkdir(mode=0o700)
    helper = target / "codex-app-server"
    require(digest(artifact) == ARCHIVE_SHA, "artifact-changed")
    extract(artifact, helper)
    entitlements = target / "helper.entitlements"
    with entitlements.open("xb") as output:
        plistlib.dump(CHILD, output)
    run(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", HELPER_ID,
         "--options", "runtime", "--entitlements", str(entitlements), str(helper)])
    verify_signature(helper, HELPER_ID, CHILD, final=False)
    notices = target / "StoreNotices"
    notices.mkdir()
    for name, source in files.items():
        # Recheck immediately before exclusive write; never overwrite an existing payload.
        data = regular(source).read_bytes()
        require(hashlib.sha256(data).hexdigest() == approval["payloads"][name]["sha256"], "input-changed")
        with (notices / name).open("xb") as output:
            output.write(data)
    with (notices / "packaging-receipt.json").open("x") as output:
        json.dump({"schemaVersion": 1, "approvalSHA256": approval_sha,
                   "artifactSHA256": ARCHIVE_SHA, "sourceCommit": COMMIT,
                   "payloadSHA256": {name: digest(notices / name) for name in files}}, output, sort_keys=True)


def verify_embedded(app, approval, files, approval_sha, parent=False):
    app = safe_path(app)
    require(app.is_dir() and app.suffix == ".app", "unsafe-app-directory")
    helper = regular(app / "Contents/Helpers/codex-app-server")
    verify_signature(helper, HELPER_ID, CHILD)
    notices = safe_path(app / "Contents/Resources/StoreNotices")
    require({item.name for item in notices.iterdir()} == PAYLOADS | {"packaging-receipt.json"},
            "embedded-payload-set-mismatch")
    receipt = load(notices / "packaging-receipt.json")
    require(receipt["approvalSHA256"] == approval_sha and receipt["sourceCommit"] == COMMIT and
            receipt["artifactSHA256"] == ARCHIVE_SHA, "embedded-receipt-mismatch")
    for name, source in files.items():
        require(digest(notices / name) == approval["payloads"][name]["sha256"] == receipt["payloadSHA256"][name],
                "embedded-notice-mismatch")
    info = plistlib.loads(regular(app / "Contents/Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == BID, "embedded-bundle-id-mismatch")
    if parent:
        verify_signature(app, BID, PARENT)


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    for mode in ("preflight", "stage-xcode", "verify-embedded", "verify-app"):
        group.add_argument("--" + mode, action="store_true")
    parser.add_argument("--app")
    args = parser.parse_args()
    env = os.environ
    if args.stage_xcode or args.verify_embedded:
        if env.get("ACTION") != "install":
            print("store-packaging: compile-check-only")
            return
    approval_sha = env.get("AI_USAGE_BUDDY_STORE_APPROVAL_SHA256", "")
    approval, artifact, files = approved_inputs(REPO / "config/EmbeddedAppServer.json",
        env.get("AI_USAGE_BUDDY_STORE_INPUTS", ""), approval_sha)
    if not args.verify_app:
        signing_environment(env, approval)
    if args.stage_xcode:
        stage(env.get("DERIVED_FILE_DIR", ""), approval_sha, approval, artifact, files)
    elif args.verify_embedded or args.verify_app:
        app = args.app if args.verify_app else str(safe_path(env["TARGET_BUILD_DIR"]) / env["FULL_PRODUCT_NAME"])
        verify_embedded(app, approval, files, approval_sha, parent=args.verify_app)
    print("store-packaging: passed")


if __name__ == "__main__":
    try:
        main()
    except Rejected as error:
        print("store-packaging: rejected:" + str(error), file=os.sys.stderr)
        raise SystemExit(1)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, tarfile.TarError):
        # No raw paths, tool stderr, profile contents, or signing details in failure output.
        print("store-packaging: rejected", file=os.sys.stderr)
        raise SystemExit(1)
