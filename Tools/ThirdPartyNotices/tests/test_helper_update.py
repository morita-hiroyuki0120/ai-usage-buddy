"""Fixtures for the 0.167.2 helper update inputs (tree parsing, archive safety, component loading); no network."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_policy_draft  # noqa: E402,F401  (registers the shared generator module)
import helper_update as h  # noqa: E402

g = h.g
REG = g.REGISTRY
COMMIT = h.CODEX_COMMIT


def pkg(name, version, source=REG, license_="MIT", path=None):
    ident = f"{source}#{name}@{version}" if source else f"path+file:///ws/{path or name}#{name}@{version}"
    return {"id": ident, "name": name, "version": version, "source": source, "license": license_,
            "manifest_path": f"/ws/{path or name}/Cargo.toml"}


class TreeTests(unittest.TestCase):
    def test_tree_lines_map_to_unique_ids(self):
        packages = [pkg("root", "0.1.0", None, "Apache-2.0"), pkg("dup", "1.0.0"),
                    pkg("dup", "1.0.0", "git+https://github.com/o/r?rev=" + "a" * 40 + "#" + "a" * 40),
                    pkg("macro", "0.2.0")]
        text = ("0root v0.1.0 (/ws/root)\n1dup v1.0.0\n1dup v1.0.0 (https://github.com/o/r?rev=" + "a" * 40 + "#" + "a" * 40 + ")\n"
                "1macro v0.2.0 (proc-macro)\n2dup v1.0.0 (*)\n\n")
        ids = h.parse_tree_ids(text, packages)
        self.assertEqual(len(ids), 4)
        self.assertIn(packages[2]["id"], ids)

    def test_unknown_or_ambiguous_tree_line_is_rejected(self):
        packages = [pkg("a", "1.0.0"), pkg("a", "1.0.0", "git+https://github.com/o/r#" + "a" * 40)]
        with self.assertRaises(g.AuditError):
            h.parse_tree_ids("0zzz v1.0.0\n", packages)
        with self.assertRaises(g.AuditError):
            h.parse_tree_ids("0a v1.0.0 (https://elsewhere.example/x)\n", packages)
        with self.assertRaises(g.AuditError):
            h.parse_tree_ids("not a tree line\n", packages)

    def test_reachability_follows_normal_and_build_but_not_dev_edges(self):
        nodes = [{"id": "r", "deps": [{"pkg": "n", "dep_kinds": [{"kind": None}]},
                                       {"pkg": "b", "dep_kinds": [{"kind": "build"}]},
                                       {"pkg": "d", "dep_kinds": [{"kind": "dev"}]}]},
                 {"id": "n", "deps": []}, {"id": "b", "deps": [{"pkg": "bb", "dep_kinds": [{"kind": None}]}]},
                 {"id": "bb", "deps": []}, {"id": "d", "deps": []}]
        self.assertEqual(h.reachable_ids({"resolve": {"nodes": nodes}}, {"r"}), {"r", "n", "b", "bb"})


class ArchiveTests(unittest.TestCase):
    def archive(self, entries):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode="w") as tar:
            for name, body in entries:
                if body is None:
                    info = tarfile.TarInfo(name)
                    info.type = tarfile.SYMTYPE
                    info.linkname = "/etc/passwd"
                    tar.addfile(info)
                else:
                    info = tarfile.TarInfo(name)
                    info.size = len(body)
                    tar.addfile(info, io.BytesIO(body))
        return out.getvalue()

    def test_regular_members_only_and_links_are_not_followed(self):
        files, root = h.archive_members(self.archive([("c-1/LICENSE", b"x"), ("c-1/link", None)]))
        self.assertEqual((files, root), ({"LICENSE": b"x"}, "c-1"))

    def test_unsafe_duplicate_or_multi_root_archives_are_rejected(self):
        for entries in ([("../x/LICENSE", b"x")], [("c-1/LICENSE", b"x"), ("c-1/LICENSE", b"y")],
                        [("c-1/LICENSE", b"x"), ("d-1/LICENSE", b"x")]):
            with self.assertRaises(g.AuditError):
                h.archive_members(self.archive(entries))


class GitHeadTests(unittest.TestCase):
    def test_detached_symbolic_and_escaping_heads(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a/.git").mkdir(parents=True)
            (root / "a/.git/HEAD").write_text("a" * 40 + "\n")
            self.assertEqual(h._read_git_head(root / "a"), "a" * 40)
            (root / "b/.git/refs/heads").mkdir(parents=True)
            (root / "b/.git/HEAD").write_text("ref: refs/heads/main\n")
            (root / "b/.git/refs/heads/main").write_text("b" * 40 + "\n")
            self.assertEqual(h._read_git_head(root / "b"), "b" * 40)
            (root / "c/.git").mkdir(parents=True)
            (root / "c/.git/HEAD").write_text("ref: ../../outside\n")
            (root / "c/outside").write_text("c" * 40)
            self.assertIsNone(h._read_git_head(root / "c"))
            (root / "d/.git").mkdir(parents=True)
            (root / "d/.git/HEAD").write_text("not-a-sha\n")
            self.assertIsNone(h._read_git_head(root / "d"))


class LoaderTests(unittest.TestCase):
    """Minimal project root: one path crate, one reused registry crate, one fresh registry crate, one fresh git crate."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name).resolve()
        self.old_load = g.load_components
        self.addCleanup(setattr, g, "load_components", self.old_load)

    def put(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else json.dumps(data).encode())
        return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size": path.stat().st_size}

    def build(self, reused_license="MIT", reused_checksum="r" * 64):
        revision = "d" * 40
        git_source = f"git+https://github.com/o/gitrepo.git?rev={revision}#{revision}"
        packages = [pkg("codex-app-server", "0.167.2", None, "Apache-2.0", "app-server"),
                    pkg("kept", "1.0.0", license_=reused_license), pkg("fresh", "2.0.0"),
                    {**pkg("gitdep", "3.0.0", git_source, "MIT"), "id": f"{git_source.split('#')[0]}#gitdep@3.0.0"}]
        metadata = {"packages": packages, "workspace_root": "/ws"}
        ids = sorted(p["id"] for p in packages)
        closure = {"codexCommit": COMMIT, "counts": {"releaseUnionPackages": len(ids)}, "closures": {"releaseUnion": ids}}
        lic = self.put("res/lockfile-license-texts/fresh-2.0.0/fresh-2.0.0/LICENSE", b"fresh license\n")
        gitlic = self.put("res/git-license-texts/o_gitrepo-ddd/LICENSE", b"git license\n")
        shared_lic = self.put("res/path-workspace-license-texts/LICENSE", b"root license\n")
        shared_not = self.put("res/path-workspace-license-texts/NOTICE", b"root notice\n")
        inventory = {"audit": {"commit": COMMIT, "boundedLockDiff": {
            "registryVersionSourceChecksumChanges": 0, "gitVersionRevisionChanges": 0}}, "packages": [
            {"name": "codex-app-server", "version": "0.0.0", "source": h.LOCAL_PATH_SOURCE, "category": "path",
             "checksum": None, "licenseEvidence": {}},
            {"name": "kept", "version": "1.0.0", "source": REG, "category": "registry", "checksum": "r" * 64,
             "licenseEvidence": {"evidenceOrigin": "reused-from-0.163.0-identical-lock-entry"}},
            {"name": "fresh", "version": "2.0.0", "source": REG, "category": "registry", "checksum": "f" * 64,
             "licenseEvidence": {"evidenceOrigin": "collected-for-0.167.2", "manifestPackageMatches": True,
                                 "sha256": "f" * 64, "lockChecksum": "f" * 64,
                                 "vcsInfo": {"git": {"sha1": "e" * 40}},
                                 "licenseTextFiles": [{"archiveMember": "fresh-2.0.0/LICENSE", **lic,
                                     "collectedPath": "res/lockfile-license-texts/fresh-2.0.0/fresh-2.0.0/LICENSE"}]}},
            {"name": "gitdep", "version": "3.0.0", "source": git_source, "category": "git", "checksum": None,
             "licenseEvidence": {"evidenceOrigin": "collected-for-0.167.2", "revision": revision, "source": git_source,
                                 "repoLicenseTextFiles": [{"sourcePath": "LICENSE", **gitlic,
                                     "collectedPath": "res/git-license-texts/o_gitrepo-ddd/LICENSE"}]}}]}
        shared = {"sourceCommit": COMMIT, "candidates": [
            {"name": "LICENSE", "sourcePath": "repository-root/LICENSE", "collectedPath": "res/path-workspace-license-texts/LICENSE", **shared_lic},
            {"name": "NOTICE", "sourcePath": "repository-root/NOTICE", "collectedPath": "res/path-workspace-license-texts/NOTICE", **shared_not}],
            "packages": [{"name": "codex-app-server", "lockVersion": "0.0.0", "manifest": "app-server/Cargo.toml",
                          "manifestVersion": "0.167.2"}]}
        self.put("res/cargo-lock-license-inventory.json", inventory)
        self.put("res/target-closure-followup/metadata-aarch64.json", metadata)
        self.put("res/target-closure-followup/target-closure-inventory.json", closure)
        self.put("res/path-package-shared-license-evidence.json", shared)
        self.put("old/inventory.json", {"packages": [
            {"name": "kept", "version": "1.0.0", "source": REG, "checksum": "r" * 64, "category": "registry"}]})
        kept_id = next(p["id"] for p in packages if p["name"] == "kept")
        old = {"identity": kept_id, "name": "kept", "version": "1.0.0", "sourceURL": "https://static.crates.io/x",
               "lockIdentity": ["kept", "1.0.0", REG], "normalization": None, "spdxManifestRaw": "MIT",
               "issues": [], "evidence": []}
        g.load_components = lambda root: ([old], [{"path": "old/cargo-lock-license-inventory.json", "sha256": "0"},
                                                 {"path": "old/other.json", "sha256": "1"}])
        # the loader reads the old inventory via the ref path
        self.put("old/cargo-lock-license-inventory.json", {"packages": [
            {"name": "kept", "version": "1.0.0", "source": REG, "checksum": reused_checksum, "category": "registry"}]})
        return old

    def test_loads_path_reused_fresh_registry_and_fresh_git_components(self):
        old = self.build()
        components, refs = h.load_components(self.root, "res")
        by = {c["name"]: c for c in components}
        self.assertEqual(len(components), 4)
        self.assertIs(by["kept"], old)
        app = by["codex-app-server"]
        self.assertEqual(app["normalization"], {"originalLockVersion": "0.0.0", "normalizedManifestVersion": "0.167.2",
                                                "manifest": "app-server/Cargo.toml"})
        self.assertEqual([e["role"] for e in app["evidence"]], ["license-text-candidate", "notice-or-copyright-candidate"])
        self.assertTrue(all(e["size"] for e in app["evidence"]))
        self.assertIn(COMMIT, app["sourceURL"])
        fresh = by["fresh"]
        self.assertEqual(fresh["evidence"][0]["sourceURL"], "https://static.crates.io/crates/fresh/fresh-2.0.0.crate#fresh-2.0.0/LICENSE")
        self.assertEqual(fresh["evidence"][0]["role"], "license-text-candidate")
        git = by["gitdep"]
        self.assertIn("repository-license-scope-unreviewed", git["issues"])
        self.assertEqual(git["evidence"][0]["sourceURL"], "https://raw.githubusercontent.com/o/gitrepo/" + "d" * 40 + "/LICENSE")
        self.assertEqual(sum(r["path"].endswith("/cargo-lock-license-inventory.json") for r in refs), 1)
        self.assertTrue(any(r["path"] == "old/other.json" for r in refs))

    def test_reused_component_must_match_the_verified_old_component(self):
        self.build(reused_checksum="x" * 64)
        with self.assertRaises(g.AuditError):
            h.load_components(self.root, "res")

    def test_reused_component_with_changed_declaration_is_rejected(self):
        self.build(reused_license="Apache-2.0")
        with self.assertRaises(g.AuditError):
            h.load_components(self.root, "res")

    def test_other_commit_in_inputs_is_rejected(self):
        self.build()
        path = self.root / "res/path-package-shared-license-evidence.json"
        data = json.loads(path.read_text())
        data["sourceCommit"] = "0" * 40
        path.write_text(json.dumps(data))
        with self.assertRaises(g.AuditError):
            h.load_components(self.root, "res")

    def test_unknown_input_set_is_rejected(self):
        with self.assertRaises(g.AuditError):
            generate_policy_draft.build(self.root, "app-server", "x", "y", inputs="helper-9")


if __name__ == "__main__":
    unittest.main()
