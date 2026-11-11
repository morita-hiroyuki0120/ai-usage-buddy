"""Synthetic, offline fixtures only; no actual helper, codesign, or profile access."""
import copy
import hashlib
import importlib.util
import io
import json
import os
import plistlib
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("packaging_prepare", Path(__file__).parents[1] / "prepare.py")
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.inputs = self.root / "inputs"
        self.inputs.mkdir()
        self.config = self.root / "config.json"
        self.config_data = {"version": "0.163.0", "tag": "rust-v0.163.0", "sourceCommit": p.COMMIT,
                            "artifact": {"sha256": p.ARCHIVE_SHA}, "distributionStatus": "ready"}
        self.archive = self.inputs / "fixture.tar.gz"
        self.make_tar(p.MEMBER)
        fixture_sha = p.digest(self.archive)
        # Only tests substitute synthetic fixture hashes; no production bypass setting exists.
        self.addCleanup(patch.stopall)
        patch.object(p, "ARCHIVE_SHA", fixture_sha).start()
        self.config_data["artifact"]["sha256"] = fixture_sha
        self.config.write_text(json.dumps(self.config_data))
        files = {}
        for name in p.PAYLOADS:
            path = self.inputs / name
            path.write_text("fixture " + name)
            files[name] = self.record(path)
        patch.object(p, "ROOT_HASHES", {name: files[name]["sha256"] for name in ("LICENSE", "NOTICE")}).start()
        patch.object(p, "REPO", self.root).start()
        (self.root / "LICENSE").write_bytes((self.inputs / "App-LICENSE").read_bytes())
        self.approval = {"schemaVersion": 1, "status": "approved-for-store-packaging",
                         "configSHA256": p.digest(self.config), "artifactSHA256": fixture_sha,
                         "sourceCommit": p.COMMIT, "artifact": self.record(self.archive), "payloads": files,
                         "review": {"status": "approved", "reference": "fixture-only", "approvedAt": "fixture"},
                         "signing": {"team": p.TEAM, "bundleID": p.BID, "profileSpecifier": "", "profileUUID": ""}}
        self.env = {"ACTION": "install", "CONFIGURATION": "Release", "DEPLOYMENT_POSTPROCESSING": "YES",
                    "DEVELOPMENT_TEAM": p.TEAM, "PRODUCT_BUNDLE_IDENTIFIER": p.BID,
                    "SKIP_INSTALL": "NO", "ENABLE_HARDENED_RUNTIME": "YES", "CODE_SIGNING_ALLOWED": "YES",
                    "EXPANDED_CODE_SIGN_IDENTITY": "A" * 40,
                    "EXPANDED_CODE_SIGN_IDENTITY_NAME": "Apple Distribution: Fixture (" + p.TEAM + ")",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "AI_USAGE_BUDDY_APP_STORE"}

    def record(self, path):
        return {"path": path.name, "sha256": p.digest(path), "size": path.stat().st_size}

    def make_tar(self, name, kind=tarfile.REGTYPE):
        with tarfile.open(self.archive, "w:gz") as archive:
            member = tarfile.TarInfo(name)
            member.type = kind
            if kind == tarfile.REGTYPE:
                member.size = 7
                archive.addfile(member, io.BytesIO(b"fixture"))
            else:
                member.linkname = "outside"
                archive.addfile(member)

    def inputs_checked(self):
        path = self.inputs / "approval.json"
        path.write_text(json.dumps(self.approval))
        return p.approved_inputs(self.config, self.inputs, p.digest(path))

    def test_approved_fixture_and_profile_optional(self):
        approval, _, _ = self.inputs_checked()
        p.signing_environment(self.env, approval)

    def test_existing_not_ready_stays_rejected(self):
        self.config_data["distributionStatus"] = "not-ready"
        self.config.write_text(json.dumps(self.config_data))
        self.approval["configSHA256"] = p.digest(self.config)
        with self.assertRaisesRegex(p.Rejected, "distribution-not-ready"):
            self.inputs_checked()

    def test_draft_not_accepted_by_ready_config(self):
        self.approval["status"] = "draft-not-approved"
        with self.assertRaises(p.Rejected):
            self.inputs_checked()
        self.approval["status"] = "approved-for-store-packaging"
        self.approval["review"]["status"] = "pending"
        with self.assertRaises(p.Rejected):
            self.inputs_checked()

    def test_config_and_source_binding(self):
        for key in ("configSHA256", "sourceCommit", "artifactSHA256"):
            with self.subTest(key=key):
                old = self.approval[key]
                self.approval[key] = "0" * len(old)
                with self.assertRaises(p.Rejected):
                    self.inputs_checked()
                self.approval[key] = old

    def test_approval_hash_pin(self):
        self.inputs_checked()
        with self.assertRaises(p.Rejected):
            p.approved_inputs(self.config, self.inputs, "0" * 64)

    def test_notice_and_source_offer_tampering(self):
        for name in ("THIRD-PARTY-NOTICES.txt", "SOURCE-AVAILABILITY.txt"):
            with self.subTest(name=name):
                path = self.inputs / name
                old = path.read_bytes()
                path.write_bytes(b"changed")
                with self.assertRaises(p.Rejected):
                    self.inputs_checked()
                path.write_bytes(old)

    def test_missing_source_offer(self):
        del self.approval["payloads"]["SOURCE-AVAILABILITY.txt"]
        with self.assertRaises(p.Rejected):
            self.inputs_checked()

    def test_input_escape_and_symlink(self):
        original = copy.deepcopy(self.approval["artifact"])
        for path in ("../fixture.tar.gz", "/tmp/fixture.tar.gz"):
            self.approval["artifact"]["path"] = path
            with self.assertRaises(p.Rejected):
                self.inputs_checked()
        self.approval["artifact"] = original
        link = self.inputs / "linked"
        link.symlink_to(self.archive)
        self.approval["artifact"]["path"] = link.name
        with self.assertRaises(p.Rejected):
            self.inputs_checked()

    def test_parent_directory_symlink(self):
        link = self.root / "linked"
        link.symlink_to(self.inputs, target_is_directory=True)
        with self.assertRaises(p.Rejected):
            p.safe_path(link / "approval.json")

    def test_wrong_signer_team_bundle_and_profile(self):
        for key, value in (("EXPANDED_CODE_SIGN_IDENTITY_NAME", "Developer ID Application: Fixture"),
                           ("DEVELOPMENT_TEAM", "OTHER"), ("PRODUCT_BUNDLE_IDENTIFIER", p.BID + ".validation"),
                           ("PROVISIONING_PROFILE_SPECIFIER", "unapproved"), ("CODE_SIGNING_ALLOWED", "NO"),
                           ("SKIP_INSTALL", "YES"), ("CONFIGURATION", "Debug"),
                           ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "AI_USAGE_BUDDY_APP_STORE AI_USAGE_BUDDY_RUNTIME_VALIDATION")):
            with self.subTest(key=key), self.assertRaises(p.Rejected):
                p.signing_environment(dict(self.env, **{key: value}), self.approval)

    def test_tar_paths_links_and_duplicates(self):
        for name, kind in (("/absolute", tarfile.REGTYPE), ("../escape", tarfile.REGTYPE),
                           (p.MEMBER, tarfile.SYMTYPE), (p.MEMBER, tarfile.LNKTYPE)):
            self.make_tar(name, kind)
            with self.assertRaises(p.Rejected):
                p.extract(self.archive, self.root / "never-written")
        self.make_tar(p.MEMBER)
        with tarfile.open(self.archive, "r:gz") as source:
            members = source.getmembers()
        with tarfile.open(self.archive, "w:gz") as output:
            for _ in range(2):
                output.addfile(members[0], io.BytesIO(b"fixture"))
        with self.assertRaises(p.Rejected):
            p.extract(self.archive, self.root / "never-written")

    def test_extract_exclusive(self):
        target = self.root / "existing"
        target.write_bytes(b"preserve")
        with self.assertRaises(FileExistsError):
            p.extract(self.archive, target)
        self.assertEqual(target.read_bytes(), b"preserve")

    def test_stage_only_once_without_signing_fixture(self):
        approval, artifact, files = self.inputs_checked()
        derived = self.root / "derived"
        derived.mkdir()
        with patch.object(p, "run") as run, patch.object(p, "verify_signature"):
            p.stage(derived, "fixture-pin", approval, artifact, files)
            self.assertEqual(run.call_count, 1)
            self.assertIn("-", run.call_args.args[0])
            with self.assertRaises(FileExistsError):
                p.stage(derived, "fixture-pin", approval, artifact, files)
        self.assertEqual(set(item.name for item in (derived / "StorePackaging/StoreNotices").iterdir()),
                         p.PAYLOADS | {"packaging-receipt.json"})

    def test_normal_build_no_approval_or_staging(self):
        with patch.dict(os.environ, {"ACTION": "build"}, clear=True), \
             patch("sys.argv", ["prepare.py", "--stage-xcode"]), patch.object(p, "approved_inputs") as inputs:
            p.main()
            inputs.assert_not_called()

    def test_project_archive_only_copy_phases(self):
        project = Path(__file__).parents[3] / "Store/AIUsageBuddy.xcodeproj/project.pbxproj"
        text = project.read_text()
        self.assertEqual(text.count("ATTRIBUTES = (CodeSignOnCopy,"), 1)
        self.assertIn("dstPath = Contents/Helpers;", text)
        self.assertIn("SKIP_INSTALL = NO;", text)
        self.assertNotIn("ENABLE_USER_SCRIPT_SANDBOXING = NO;", text)

    def test_parent_entitlements_identity_allowlist(self):
        p.verify_entitlements(dict(p.PARENT), p.PARENT)
        actual = dict(p.PARENT, **{"com.apple.application-identifier": p.TEAM + "." + p.BID,
                                  "com.apple.developer.team-identifier": p.TEAM,
                                  "keychain-access-groups": [p.TEAM + "." + p.BID],
                                  "com.apple.security.get-task-allow": False})
        p.verify_entitlements(actual, p.PARENT)

    def test_parent_entitlements_reject_escalation(self):
        invalid = (("com.apple.application-identifier", p.TEAM + ".other"),
                   ("application-identifier", p.TEAM + ".*"),
                   ("com.apple.developer.team-identifier", "OTHER"),
                   ("keychain-access-groups", [p.TEAM + ".*"]),
                   ("keychain-access-groups", [p.TEAM + "." + p.BID, p.TEAM + ".other"]),
                   ("com.apple.security.get-task-allow", True),
                   ("get-task-allow", True), ("com.apple.security.files.user-selected.read-write", True),
                   ("com.apple.security.network.client", 1), ("com.apple.security.inherit", True))
        for key, value in invalid:
            with self.subTest(key=key), self.assertRaises(p.Rejected):
                p.verify_entitlements(dict(p.PARENT, **{key: value}), p.PARENT)

    def test_signature_runtime_flag_parsing(self):
        def sig(flags):
            line = "CodeDirectory v=20500 size=371628 flags=%s hashes=11602+7 location=embedded" % flags
            err = "Identifier=%s\n%s\n" % (p.HELPER_ID, line)
            return type("R", (), {"stderr": err.encode(), "stdout": plistlib.dumps(p.CHILD)})()
        def runner(flags):
            return lambda cmd, *a, **k: sig(flags) if "--verbose=4" in cmd or "--entitlements" in cmd else sig(flags)
        for flags in ("0x10002(adhoc,runtime)", "0x10000(runtime)"):
            with patch.object(p, "run", runner(flags)):
                p.verify_signature(Path("/x"), p.HELPER_ID, p.CHILD, final=False)
        for flags in ("0x2(adhoc)", "0x0(none)", "0x10002(adhoc,notruntime)"):
            with patch.object(p, "run", runner(flags)), self.assertRaises(p.Rejected):
                p.verify_signature(Path("/x"), p.HELPER_ID, p.CHILD, final=False)

    def test_child_entitlements_remain_exact(self):
        p.verify_entitlements(dict(p.CHILD), p.CHILD)
        for key, value in (("com.apple.security.get-task-allow", False),
                           ("com.apple.developer.team-identifier", p.TEAM),
                           ("com.apple.security.network.client", True),
                           ("com.apple.security.inherit", 1)):
            with self.subTest(key=key), self.assertRaises(p.Rejected):
                p.verify_entitlements(dict(p.CHILD, **{key: value}), p.CHILD)


if __name__ == "__main__":
    unittest.main()
