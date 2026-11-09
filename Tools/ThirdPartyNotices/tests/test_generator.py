"""Standard-library fixtures only; no Cargo, network, or real user data."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[3] / "scripts/generate-third-party-notices.py"
spec = importlib.util.spec_from_file_location("notices", SCRIPT)
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)


class NoticesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "build").mkdir()
        self.body = b"Copyright (c) Actual Fixture Holder\r\nLicense terms fixture.\r\n"
        (self.root / "LICENSE").write_bytes(self.body)

    def component(self, name="demo", source="https://example.org/source/abc"):
        return {"identity": name + "@1.0|" + source, "name": name, "version": "1.0",
                "sourceURL": source, "spdxManifestRaw": "MIT OR Apache-2.0", "issues": [],
                "evidence": [{"path": "LICENSE", "publicPath": "LICENSE", "sourceURL": source,
                              "sha256": g.digest(self.body), "size": len(self.body),
                              "role": "license-text-candidate"}]}

    def inputs(self):
        """Tiny schema-equivalent external + explicitly normalized path fixture."""
        p = {"name": "demo", "version": "1.0", "source": g.REGISTRY,
             "id": "registry-demo"}
        local = {"name": "local", "version": "0.163.0", "source": None, "id": "path-local",
                 "manifest_path": "/fixed-copy/local/Cargo.toml"}
        for x in (p, local):
            x["license"] = "MIT"
        self.data = {
            "cargo-lock-license-inventory.json": {
                "audit": {"commit": g.COMMIT, "boundedLockDiff": {
                    "pathVersionChanges": 160, "registryVersionSourceChecksumChanges": 0,
                    "gitVersionRevisionChanges": 0}},
                "packages": [
                    {"name": "demo", "version": "1.0", "source": g.REGISTRY,
                     "category": "registry", "checksum": "abc",
                     "licenseEvidence": {"manifestPackageMatches": True, "sha256": "abc",
                                         "lockChecksum": "abc", "licenseTextFiles": []}},
                    {"name": "local", "version": "0.0.0",
                     "source": "local path (Cargo.lock contains no source URL)", "category": "path",
                     "licenseEvidence": {"manifestCandidates": [
                         {"manifest": "local/Cargo.toml", "currentManifestVersion": "0.163.0"}]}}]},
            "target-closure-followup/metadata-aarch64.json":
                {"packages": [p, local], "workspace_root": "/fixed-copy"},
            "target-closure-followup/target-closure-inventory.json":
                {"closures": {"releaseUnion": [p["id"], local["id"]]},
                 "counts": {"releaseUnionPackages": 2}},
            "target-closure-followup/license-obligations-ledger-20261023.json": {"packages": []},
            "missing-license-followup-20261022/missing-license-inventory.json": {"packages": []},
            "license-text-followup-20261023/license-text-inventory.json": {"packages": []},
            "path-package-shared-license-evidence.json": {
                "sourceCommit": g.COMMIT, "candidates": [
                    {"name": n, "sourcePath": n, "collectedPath": "LICENSE",
                     "sha256": g.digest(self.body), "size": len(self.body)}
                    for n in ["LICENSE", "NOTICE"]],
                "packages": [{"name": "local", "manifestVersion": "0.163.0",
                              "lockVersion": "0.0.0", "manifest": "local/Cargo.toml"}]}}
        self.save_inputs()

    def save_inputs(self):
        for name, value in self.data.items():
            p = self.root / "inputs" / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(value), encoding="utf-8")
        (self.root / "inputs/LICENSE").write_bytes(self.body)

    def test_dedup_bytes_reproducibility_and_missing_visibility(self):
        a, b = self.component(), self.component("another")
        missing = self.component("missing")
        missing["evidence"] = []
        files, report = g.assemble(self.root, [a, b, missing], [])
        again, _ = g.assemble(self.root, [missing, b, a], [])
        self.assertEqual(files, again)
        self.assertEqual(report["summary"]["uniqueTexts"], 1)
        self.assertEqual(report["summary"]["withoutFullLicenseCandidate"], 1)
        self.assertEqual(files["THIRD-PARTY-NOTICES.draft.txt"].count(self.body), 1)
        self.assertNotIn(str(self.root).encode(), files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertEqual(report["distributionStatus"], "not-ready")
        self.assertEqual(len(json.loads(files["unresolved-report.json"])["components"]), 3)
        self.assertNotIn("selectedRoute", report["components"][0])

    def test_hash_and_size_tampering_fail_before_output(self):
        for field, bad in [("sha256", "0"*64), ("size", 9999)]:
            with self.subTest(field=field):
                c = self.component()
                c["evidence"][0][field] = bad
                with self.assertRaises(g.AuditError):
                    g.assemble(self.root, [c], [])
        self.assertFalse((self.root / "build/output").exists())

    def test_absolute_traversal_symlink_and_parent_symlink(self):
        with tempfile.TemporaryDirectory() as external:
            f = Path(external) / "LICENSE"
            f.write_bytes(self.body)
            (self.root / "link").symlink_to(f)
            (self.root / "dirlink").symlink_to(Path(external), target_is_directory=True)
            for name in [str(f), "../LICENSE", "link", "dirlink/LICENSE"]:
                with self.subTest(path=name), self.assertRaises(g.AuditError):
                    g.safe_file(self.root, name)
        # Even an in-root symlink is rejected.
        (self.root / "inside").symlink_to(self.root / "LICENSE")
        with self.assertRaises(g.AuditError):
            g.safe_file(self.root, "inside")

    def test_invalid_utf8_and_source_code_are_explicit_review_needed(self):
        (self.root / "bad").write_bytes(b"\xff")
        c = self.component()
        c["evidence"][0].update(path="bad", sha256=g.digest(b"\xff"), size=1)
        files, report = g.assemble(self.root, [c], [])
        self.assertIn("invalid-UTF8:LICENSE", report["components"][0]["issues"])
        self.assertEqual(report["summary"]["uniqueTexts"], 0)
        self.assertIsNone(g.candidate_role("copyright.rs"))
        self.assertIsNone(g.candidate_role("libwinapi_oemlicense.a"))
        self.assertIsNone(g.candidate_role("README.md"))
        self.assertEqual(g.candidate_role("NOTICE"), "notice-or-copyright-candidate")

    def test_exact_source_version_and_path_manifest_join(self):
        self.inputs()
        c, _ = g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)
        self.assertEqual(len(c), 2)
        local = next(p for p in c if p["name"] == "local")
        self.assertEqual(local["normalization"]["originalLockVersion"], "0.0.0")
        self.assertEqual({e["publicPath"] for e in local["evidence"]}, {"LICENSE", "NOTICE"})
        for value in ["2.0", "registry+https://other.invalid/index"]:
            saved = copy.deepcopy(self.data)
            p = self.data["target-closure-followup/metadata-aarch64.json"]["packages"][0]
            p["version" if value == "2.0" else "source"] = value
            self.save_inputs()
            with self.assertRaises(g.AuditError):
                g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)
            self.data = saved
        self.data["path-package-shared-license-evidence.json"]["packages"][0]["manifest"] = "other/Cargo.toml"
        self.save_inputs()
        with self.assertRaises(g.AuditError):
            g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)

    def test_ambiguous_duplicate_missing_and_dropped_ids_fail(self):
        self.inputs()
        self.data["target-closure-followup/metadata-aarch64.json"]["packages"].append(
            copy.deepcopy(self.data["target-closure-followup/metadata-aarch64.json"]["packages"][0]))
        self.save_inputs()
        with self.assertRaises(g.AuditError):
            g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)
        self.inputs()
        self.data["target-closure-followup/target-closure-inventory.json"]["closures"]["releaseUnion"][0] = "absent"
        self.save_inputs()
        with self.assertRaises(g.AuditError):
            g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)

    def test_git_revision_must_match_exact_lock_source(self):
        self.inputs()
        rev = "a"*40
        source = "git+https://github.com/example/demo?rev=" + rev + "#" + rev
        meta = self.data["target-closure-followup/metadata-aarch64.json"]["packages"][0]
        lock = self.data["cargo-lock-license-inventory.json"]["packages"][0]
        meta["source"] = lock["source"] = source
        lock["category"] = "git"
        lock["licenseEvidence"] = {"source": source, "revision": rev, "repoLicenseTextFiles": []}
        self.save_inputs()
        g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)
        lock["licenseEvidence"]["revision"] = "b"*40
        self.save_inputs()
        with self.assertRaises(g.AuditError):
            g.load_components(self.root, "inputs", historical_relative=None, supplement_relative=None)

    def test_exclusive_output_and_no_completion_on_write_failure(self):
        files, _ = g.assemble(self.root, [self.component()], [])
        marker = g.publish(self.root, "build/new", files)
        self.assertTrue(marker["generationComplete"])
        for name, info in marker["files"].items():
            self.assertEqual(g.digest((self.root / "build/new" / name).read_bytes()), info["sha256"])
        with self.assertRaises(g.AuditError):
            g.publish(self.root, "build/new", files)
        original = Path.open
        def fail(path, *args, **kwargs):
            if path.name == "internal-manifest.json":
                raise OSError("fixture failure")
            return original(path, *args, **kwargs)
        with patch.object(Path, "open", fail):
            with self.assertRaises(OSError):
                g.publish(self.root, "build/partial", files)
        self.assertFalse((self.root / "build/partial/GENERATION-COMPLETE.json").exists())


    def supplement_fixture(self):
        self.inputs()
        import io
        import tarfile
        folder = Path("inputs/license-supplement-20261023-2")
        revision, repo = "a"*40, "https://github.com/example/demo"
        archive = self.root / "archive.crate"
        meta = b'name = "demo"\nversion = "1.0"\nrepository = "https://github.com/example/demo"\nlicense = "MIT"\n'
        meta = b"[package]\n" + meta
        vcs = json.dumps({"git": {"sha1": revision}, "path_in_vcs": "demo"}).encode()
        with tarfile.open(archive, "w") as tar:
            for suffix, body in [("Cargo.toml", meta), (".cargo_vcs_info.json", vcs)]:
                member = tarfile.TarInfo("demo-1.0/" + suffix)
                member.size = len(body)
                tar.addfile(member, io.BytesIO(body))
        lock = self.data["cargo-lock-license-inventory.json"]["packages"][0]
        checksum = g.digest(archive.read_bytes())
        lock["checksum"] = checksum
        lock["licenseEvidence"].update(archive="archive.crate", sha256=checksum,
                                        lockChecksum=checksum)
        files = []
        for source, role, body in [
                ("LICENSE", "full-license-text", self.body),
                ("demo/src/lib.rs", "source-header-not-license-terms",
                 b"/* Copyright (c) Fixture Holder. */\nfn unused() {}\n"),
                ("LICENSE.md", "scope-and-SDK-license-caveat-not-full-license",
                 b"Fixture SDK-derived-work caveat. Not full license terms.\n")]:
            path = folder / source
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_bytes(body)
            files.append({"localPath": str(path), "sourcePath": source, "role": role,
                          "sha256": g.digest(body), "size": len(body),
                          "gitBlobSHA1": g.hashlib.sha1(
                              b"blob "+str(len(body)).encode()+b"\0"+body).hexdigest(),
                          "gitBlobVerified": True,
                          "sourceURL": "https://raw.githubusercontent.com/example/demo/" +
                                       revision + "/" + source})
        package = {"name": "demo", "version": "1.0", "lockSource": g.REGISTRY,
                   "crateSHA256": checksum, "archivePath": "archive.crate",
                   "repository": repo, "commit": revision, "pathInVcs": "demo",
                   "spdxManifestRaw": "MIT", "status": "explicit-missing",
                   "distributionStatus": "not-ready", "files": files,
                   "fullLicensePaths": [files[0]["localPath"]],
                   "attributionPaths": [files[1]["localPath"]],
                   "pathScope": ["fixture-only applicability"], "NOTICEscope": {
                       "coverage": "fixture-only, unreviewed"},
                   "explicitMissing": ["SDK attribution review still pending."]}
        supplement = {"status": "draft-not-approved", "distributionStatus": "not-ready",
                      "packages": [package]}
        self.data["license-supplement-20261023-2/manifest.json"] = supplement
        self.save_inputs()
        return package

    def test_supplement_integration_preserves_caveat_header_and_draft_status(self):
        self.supplement_fixture()
        components, refs = g.load_components(self.root, "inputs", historical_relative=None)
        files, report = g.assemble(self.root, components, refs)
        demo = next(c for c in report["components"] if c["name"] == "demo")
        self.assertEqual(demo["supplementReview"]["status"], "explicit-missing")
        self.assertIn("SDK attribution review still pending.", demo["issues"])
        self.assertNotIn("no-full-license-text-candidate", demo["issues"])
        draft = files["THIRD-PARTY-NOTICES.draft.txt"]
        self.assertIn(b"Fixture SDK-derived-work caveat.", draft)
        self.assertIn(b"/* Copyright (c) Fixture Holder. */", draft)
        self.assertNotIn(b"fn unused()", draft)
        self.assertEqual(report["distributionStatus"], "not-ready")
        again, _ = g.assemble(self.root, list(reversed(components)), refs)
        self.assertEqual(files, again)

    def test_supplement_wrong_identity_pin_vcs_hash_size_and_url_fail(self):
        self.supplement_fixture()
        baseline = copy.deepcopy(self.data)
        changes = [("name", "DEMO"), ("version", "2.0"), ("lockSource", "other-source"),
                   ("crateSHA256", "0"*64), ("commit", "b"*40),
                   ("pathInVcs", "another"), ("spdxManifestRaw", "Apache-2.0")]
        for field, bad in changes:
            with self.subTest(field=field):
                self.data = copy.deepcopy(baseline)
                self.data["license-supplement-20261023-2/manifest.json"]["packages"][0][field] = bad
                self.save_inputs()
                with self.assertRaises(g.AuditError):
                    g.load_components(self.root, "inputs", historical_relative=None)
        for field, bad in [("sha256", "0"*64), ("size", 999), ("gitBlobSHA1", "0"*40),
                           ("sourceURL", "https://raw.githubusercontent.com/example/demo/main/LICENSE")]:
            with self.subTest(fileField=field):
                self.data = copy.deepcopy(baseline)
                self.data["license-supplement-20261023-2/manifest.json"]["packages"][0]["files"][0][field] = bad
                self.save_inputs()
                with self.assertRaises(g.AuditError):
                    g.load_components(self.root, "inputs", historical_relative=None)

    def test_supplement_external_symlink_role_and_target_drop_fail(self):
        self.supplement_fixture()
        baseline = copy.deepcopy(self.data)
        for kind in ["outside", "symlink", "role", "dropped", "duplicate"]:
            with self.subTest(kind=kind):
                self.data = copy.deepcopy(baseline)
                p = self.data["license-supplement-20261023-2/manifest.json"]["packages"][0]
                if kind == "outside":
                    p["files"][0]["localPath"] = "LICENSE"
                elif kind == "symlink":
                    path = self.root / p["files"][0]["localPath"]
                    path.rename(path.with_name("original-LICENSE"))
                    path.symlink_to(self.root / "LICENSE")
                elif kind == "role":
                    p["files"][0]["role"] = "scope-reference-not-license-terms"
                elif kind == "dropped":
                    c = self.data["target-closure-followup/target-closure-inventory.json"]
                    c["closures"]["releaseUnion"] = ["path-local"]
                    c["counts"]["releaseUnionPackages"] = 1
                elif kind == "duplicate":
                    self.data["license-supplement-20261023-2/manifest.json"]["packages"].append(
                        copy.deepcopy(p))
                self.save_inputs()
                with self.assertRaises(g.AuditError):
                    g.load_components(self.root, "inputs", historical_relative=None)
                if kind == "symlink":
                    path.unlink()
                    path.with_name("original-LICENSE").rename(path)


if __name__ == "__main__":
    unittest.main()
