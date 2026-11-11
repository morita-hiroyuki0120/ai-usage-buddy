"""Approved-policy wrapper fixtures (Q2, Q3, Q5); fixture data only, no network."""
import copy
import io
import json
from pathlib import Path
import sys
import tarfile
import unittest

import test_generator as fixtures
g = fixtures.g
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_policy_draft as p  # noqa: E402

OLD, NEW = "a" * 40, "b" * 40
REPO = "https://github.com/owner/repo"
HEADER = b"// Copyright 2015 Fixture Developers. See the COPYRIGHT\n// file in this distribution.\n"
LIB = HEADER + b"\n#![deny(missing_docs)]\n"
CARGO = b'[package]\nname="demo"\nversion="1.0"\nlicense="MIT OR Apache-2.0"\n'


class PolicyTests(unittest.TestCase):
    setUp_base = fixtures.NoticesTests.setUp
    inputs = fixtures.NoticesTests.inputs
    save_inputs = fixtures.NoticesTests.save_inputs

    def setUp(self):
        self.setUp_base()
        self.inputs()
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode="w:gz") as tar:
            for name, body in (("Cargo.toml", CARGO), ("Cargo.toml.orig", CARGO), ("lib.rs", LIB)):
                info = tarfile.TarInfo("demo-1.0/" + name)
                info.size = len(body)
                tar.addfile(info, io.BytesIO(body))
        archive = out.getvalue()
        (self.root / "original.crate").write_bytes(archive)
        lock = self.data["cargo-lock-license-inventory.json"]["packages"][0]
        lock["checksum"] = g.digest(archive)
        lock["licenseEvidence"].update(archive="original.crate", sha256=g.digest(archive),
                                       lockChecksum=g.digest(archive))
        self.data["target-closure-followup/metadata-aarch64.json"]["packages"][0]["license"] = "MIT OR Apache-2.0"
        self.save_inputs()
        self.components, self.refs = g.load_components(self.root, "inputs", supplement_relative=None,
                                                       historical_relative=None)
        demo = next(c for c in self.components if c["name"] == "demo")
        folder = self.root / "policy"
        folder.mkdir()
        self.old_license = b"Fixture upstream license text.\n"
        (folder / "old-LICENSE-APACHE").write_bytes(self.old_license)
        (folder / "LICENSE-APACHE").write_bytes(self.old_license)
        (folder / "LICENSE-GPL").write_bytes(b"GPL fixture\n")
        (folder / "Cargo.toml").write_bytes(CARGO)
        (folder / "lib.rs").write_bytes(LIB)
        (folder / "header.txt").write_bytes(HEADER)
        # The fixture directory name keeps the basename lookup the generator performs.
        (folder / "old").mkdir()
        (folder / "old/LICENSE-APACHE").write_bytes(self.old_license)
        demo["issues"] += ["Texts collected but snapshot manifest 0.8.1; version-specific scope remains for review."]
        demo["historicalSupplementReview"] = {
            "commit": OLD, "sourceSnapshotRepository": REPO, "sourceSnapshotManifestVersion": "0.8.1",
            "spdxManifestRaw": "MIT OR Apache-2.0", "upstreamFullLicenseCandidatePaths": ["policy/old/LICENSE-APACHE"]}
        demo["evidence"].append({"path": "policy/old/LICENSE-APACHE", "publicPath": "demo-1.0/LICENSE-APACHE",
            "sourceURL": "https://static.crates.io/crates/demo/demo-1.0.crate#demo-1.0/LICENSE-APACHE",
            "sha256": g.digest(self.old_license), "size": len(self.old_license), "role": "license-text-candidate"})
        self.demo = demo

        def info(name):
            body = (folder / name).read_bytes()
            return {"path": "policy/" + name, "sha256": g.digest(body), "size": len(body)}
        self.manifest = {
            "schemaVersion": 1, "status": "draft-not-approved", "distributionStatus": "not-ready",
            "policyApproval": {"items": ["Q2", "Q3", "Q5"], "date": "2026-11-11",
                               "scope": "policy direction only; not approval of the final text"},
            "commitReplacements": [{"name": "demo", "version": "1.0", "lockSource": g.REGISTRY,
                "repository": REPO, "pathInVcs": "pkg", "previousCommit": OLD, "commit": NEW,
                "snapshotManifestVersion": "1.0", "notes": ["fixture"],
                "crateMemberEquivalence": [
                    {"crateMember": "Cargo.toml.orig", "sourcePath": "pkg/Cargo.toml", **info("Cargo.toml")},
                    {"crateMember": "lib.rs", "sourcePath": "pkg/lib.rs", **info("lib.rs")}],
                "licenseFiles": [{"sourcePath": "LICENSE-APACHE", **info("LICENSE-APACHE")},
                                 {"sourcePath": "LICENSE-MIT", **info("LICENSE-APACHE")}]}],
            "sourceHeaders": [{"name": "demo", "version": "1.0", "lockSource": g.REGISTRY, "crateMember": "lib.rs",
                "crateMemberSHA256": g.digest(LIB), "crateMemberSize": len(LIB),
                "headerPath": "policy/header.txt", "headerSHA256": g.digest(HEADER), "headerSize": len(HEADER),
                "sourceURL": "https://static.crates.io/crates/demo/demo-1.0.crate#demo-1.0/lib.rs"}],
            "licenseSelections": []}
        # LICENSE-MIT in the fixture must have its own previous candidate with identical bytes.
        (folder / "old/LICENSE-MIT").write_bytes(self.old_license)
        demo["historicalSupplementReview"]["upstreamFullLicenseCandidatePaths"].append("policy/old/LICENSE-MIT")
        self.manifest["commitReplacements"][0]["licenseFiles"][1]["sourcePath"] = "LICENSE-MIT"
        self.relative = "policy/manifest.json"
        self.save()

    def save(self):
        (self.root / self.relative).write_text(json.dumps(self.manifest), encoding="utf-8")

    def apply(self, components=None):
        return p.apply_policy(self.root, components or self.components, self.refs, self.relative)

    def test_replacement_header_and_issue_changes_are_isolated(self):
        before = copy.deepcopy(self.components)
        components, refs = self.apply()
        self.assertEqual(before, self.components)  # input is not mutated
        demo = next(c for c in components if c["name"] == "demo")
        local = next(c for c in components if c["name"] == "local")
        self.assertEqual(local, next(c for c in before if c["name"] == "local"))
        urls = {e["sourceURL"] for e in demo["evidence"]}
        self.assertIn(f"https://raw.githubusercontent.com/owner/repo/{NEW}/LICENSE-APACHE", urls)
        self.assertFalse(any(OLD in u for e in demo["evidence"][1:] for u in [e["sourceURL"]]))
        self.assertFalse(any("version-specific scope" in i for i in demo["issues"]))
        self.assertEqual(demo["historicalSupplementReview"]["commit"], OLD)  # history kept
        self.assertEqual(demo["commitReplacementReview"]["commit"], NEW)
        self.assertEqual(demo["evidence"][-1]["role"], p.HEADER_ROLE)
        self.assertEqual(len(refs), len(self.refs) + 1 + 2 + 2 + 1)
        files, report = g.assemble(self.root, components, refs)
        out = next(c for c in report["components"] if c["name"] == "demo")
        self.assertNotIn("no-full-license-text-candidate", out["issues"])
        self.assertIn(HEADER, files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertEqual(report["distributionStatus"], "not-ready")

    def test_selection_is_recorded_only_with_matching_declaration_and_text(self):
        self.demo["spdxManifestRaw"] = "Apache-2.0 OR GPL-2.0-only"
        self.manifest["commitReplacements"] = []
        self.manifest["sourceHeaders"] = []
        self.manifest["licenseSelections"] = [{"name": "demo", "version": "1.0", "lockSource": g.REGISTRY,
            "declaredRaw": "Apache-2.0 OR GPL-2.0-only", "selected": "Apache-2.0",
            "notSelected": ["GPL-2.0-only"], "approvalItem": "Q5"}]
        self.save()
        components, refs = self.apply()
        files, report = g.assemble(self.root, components, refs)
        files = p.finish(files, report, self.manifest)
        text = files["THIRD-PARTY-NOTICES.draft.txt"]
        self.assertIn(b"Apache-2.0 selected from declared 'Apache-2.0 OR GPL-2.0-only'; GPL-2.0-only not selected", text)
        self.assertEqual(report["approvedPolicy"]["licenseSelections"][0]["selected"], "Apache-2.0")
        self.assertEqual(report["draftSHA256"], g.digest(text))
        self.assertEqual(json.loads(files["internal-manifest.json"])["draftSize"], len(text))
        self.assertEqual(report["distributionStatus"], "not-ready")
        for field, value in [("selected", "GPL-2.0-only"), ("selected", "MIT"), ("declaredRaw", "MIT"),
                             ("notSelected", ["MIT"]), ("notSelected", ["Apache-2.0"])]:
            with self.subTest(field=field, value=value):
                bad = copy.deepcopy(self.manifest)
                bad["licenseSelections"][0][field] = value
                (self.root / self.relative).write_text(json.dumps(bad))
                with self.assertRaises(p.g.AuditError):
                    self.apply()

    def test_commit_replacement_tampering_rejected(self):
        baseline = copy.deepcopy(self.manifest)
        def mutate(fn):
            self.manifest = copy.deepcopy(baseline)
            fn(self.manifest["commitReplacements"][0])
            self.save()
            with self.assertRaises(p.g.AuditError):
                self.apply()
        mutate(lambda e: e.update(previousCommit="c" * 40))
        mutate(lambda e: e.update(commit=OLD))
        mutate(lambda e: e.update(commit="short"))
        mutate(lambda e: e.update(repository="https://github.com/other/repo"))
        mutate(lambda e: e.update(snapshotManifestVersion="0.8.1"))
        mutate(lambda e: e["licenseFiles"][0].update(sha256="0" * 64))
        mutate(lambda e: e["crateMemberEquivalence"][1].update(crateMember="Cargo.toml.orig"))
        # License text that differs from the previously saved bytes is rejected.
        (self.root / "policy/LICENSE-APACHE").write_bytes(b"changed\n")
        self.manifest = copy.deepcopy(baseline)
        body = b"changed\n"
        self.manifest["commitReplacements"][0]["licenseFiles"][0].update(sha256=g.digest(body), size=len(body))
        self.save()
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_header_must_be_exact_leading_comment_of_checksummed_member(self):
        baseline = copy.deepcopy(self.manifest)
        for name, body in [("short", HEADER.splitlines(True)[0]),
                           ("extra-code", HEADER + b"\n#![deny(missing_docs)]\n"),
                           ("edited", HEADER.replace(b"2015", b"2016")),
                           ("no-newline", HEADER[:-1])]:
            with self.subTest(name=name):
                (self.root / "policy/header.txt").write_bytes(body)
                self.manifest = copy.deepcopy(baseline)
                self.manifest["sourceHeaders"][0].update(headerSHA256=g.digest(body), headerSize=len(body))
                self.save()
                with self.assertRaises(p.g.AuditError):
                    self.apply()
        (self.root / "policy/header.txt").write_bytes(HEADER)
        self.manifest = copy.deepcopy(baseline)
        self.manifest["sourceHeaders"][0]["crateMemberSHA256"] = "0" * 64
        self.save()
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_status_and_approval_scope_cannot_be_promoted(self):
        for field, value in [("status", "approved"), ("distributionStatus", "ready")]:
            with self.subTest(field=field):
                bad = copy.deepcopy(self.manifest)
                bad[field] = value
                (self.root / self.relative).write_text(json.dumps(bad))
                with self.assertRaises(p.g.AuditError):
                    self.apply()
        bad = copy.deepcopy(self.manifest)
        bad["policyApproval"]["scope"] = "final text approved"
        (self.root / self.relative).write_text(json.dumps(bad))
        with self.assertRaises(p.g.AuditError):
            self.apply()


if __name__ == "__main__":
    unittest.main()
