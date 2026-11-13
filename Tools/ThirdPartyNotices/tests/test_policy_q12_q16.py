"""Q12-Q16 policy wrapper fixtures (publish-time commit, declaration record, scope, git headers); no network."""
import copy
import io
import json
from pathlib import Path
import sys
import tarfile
import unittest

import test_generator as fixtures
import test_policy as tp
g = fixtures.g
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_policy_draft as p  # noqa: E402

OLD, NEW = "a" * 40, "b" * 40
REPO = "https://github.com/owner/repo"
GIT_COMMIT = "c" * 40
GIT_SOURCE = f"git+https://github.com/owner/gitrepo.git?rev={GIT_COMMIT}#{GIT_COMMIT}"
LICENSE = b"Fixture license text.\n"
ORIG = b'[package]\nname="demo"\nversion="1.0"\nlicense={ workspace = true }\n'
PUBLISHED = b'[package]\nname="demo"\nversion="1.0"\nlicense="Apache-2.0"\n'
WS = b'[workspace.package]\nlicense = "MIT OR Apache-2.0"\nversion = "1.0"\n'
LIB = b"// Copyright 2015 Fixture\n\nfn main() {}\n"
SRC = (b"//! Doc line\n//!\n\n// Copyright (c) 2010 Fixture Developers\n//\n// Permission text\n\n"
       b"use std::io;\n")
REGION = b"//! Doc line\n//!\n\n// Copyright (c) 2010 Fixture Developers\n//\n// Permission text\n"


class Base(unittest.TestCase):
    setUp_base = fixtures.NoticesTests.setUp
    inputs = fixtures.NoticesTests.inputs
    save_inputs = fixtures.NoticesTests.save_inputs
    component = fixtures.NoticesTests.component
    setUp_policy = tp.PolicyTests.setUp
    save = tp.PolicyTests.save
    apply = tp.PolicyTests.apply

    def archive(self, members):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode="w:gz") as tar:
            for name, body in members.items():
                info = tarfile.TarInfo("demo-1.0/" + name)
                info.size = len(body)
                tar.addfile(info, io.BytesIO(body))
        return out.getvalue()

    def put(self, name, body):
        path = self.root / "q" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
        return {"path": "q/" + name, "sha256": g.digest(body), "size": len(body)}

    def reload(self, members, declared, extra_git=False):
        archive = self.archive(members)
        (self.root / "original.crate").write_bytes(archive)
        lock = self.data["cargo-lock-license-inventory.json"]["packages"][0]
        lock["checksum"] = g.digest(archive)
        lock["licenseEvidence"].update(sha256=g.digest(archive), lockChecksum=g.digest(archive))
        self.data["target-closure-followup/metadata-aarch64.json"]["packages"][0]["license"] = declared
        if extra_git:
            self.data["cargo-lock-license-inventory.json"]["packages"].append(
                {"name": "gitdemo", "version": "1.0", "source": GIT_SOURCE, "category": "git",
                 "licenseEvidence": {}})
        self.save_inputs()
        self.components, self.refs = g.load_components(self.root, "inputs", supplement_relative=None,
                                                       historical_relative=None)
        self.demo = next(c for c in self.components if c["name"] == "demo")
        if extra_git:
            git = self.component("gitdemo", f"https://github.com/owner/gitrepo/tree/{GIT_COMMIT}")
            git.update(lockIdentity=["gitdemo", "1.0", GIT_SOURCE], spdxManifestRaw="MIT", evidence=[],
                       identity="gitdemo@1.0|" + GIT_SOURCE)
            self.components.append(git)
            self.git = git

    def setUp(self):
        self.setUp_policy()
        self.manifest = {"schemaVersion": 1, "status": "draft-not-approved", "distributionStatus": "not-ready",
                         "policyApproval": {"items": ["Q12"], "date": "2026-11-11",
                                            "scope": "policy direction only; not approval of the final text"}}
        self.relative = "policy/manifest.json"


class CommitCorrectionTests(Base):
    def setUp(self):
        super().setUp()
        self.reload({"Cargo.toml": tp.CARGO, "Cargo.toml.orig": tp.CARGO, "lib.rs": LIB,
                     "extra.txt": b"extra\n"}, "MIT OR Apache-2.0")
        self.demo["historicalSupplementReview"] = {"commit": OLD, "sourceSnapshotRepository": REPO,
            "pathInVcs": "pkg", "sourceSnapshotManifestVersion": "1.0", "spdxManifestRaw": "MIT OR Apache-2.0",
            "upstreamFullLicenseCandidatePaths": []}
        self.demo["issues"].append("historical-snapshot-scope-and-NOTICE-review-pending")
        self.demo["evidence"] = []
        for name, role, body in (("LICENSE-APACHE", "license-text-candidate", LICENSE),
                                 ("LICENSE-MIT", "license-text-candidate", LICENSE + b"MIT\n"),
                                 ("NOTICE", "notice-or-copyright-candidate", b"Old notice.\n")):
            old = self.put("old/" + name, body)
            self.demo["evidence"].append({**old, "publicPath": name, "role": role,
                "sourceURL": f"https://raw.githubusercontent.com/owner/repo/{OLD}/{name}"})
        self.new_notice = b"New notice.\n"
        self.manifest["commitCorrections"] = [{"name": "demo", "version": "1.0", "lockSource": g.REGISTRY,
            "repository": REPO, "pathInVcs": "pkg", "previousCommit": OLD, "commit": NEW,
            "snapshotManifestVersion": "1.0", "notes": ["fixture"],
            "crateMemberEquivalence": [
                {"crateMember": "Cargo.toml.orig", "sourcePath": "pkg/Cargo.toml", **self.put("new/Cargo.toml", tp.CARGO)},
                {"crateMember": "lib.rs", "sourcePath": "pkg/lib.rs", **self.put("new/lib.rs", LIB)},
                {"crateMember": "extra.txt", "sourcePath": "pkg/extra.txt", **self.put("new/extra.txt", b"extra\n")}],
            "rootFiles": [{"sourcePath": "LICENSE-APACHE", **self.put("new/LICENSE-APACHE", LICENSE)},
                          {"sourcePath": "LICENSE-MIT", **self.put("new/LICENSE-MIT", LICENSE + b"MIT\n")},
                          {"sourcePath": "NOTICE", **self.put("new/NOTICE", self.new_notice)}]}]
        self.save()

    def mutate(self, fn):
        bad = copy.deepcopy(self.manifest)
        fn(bad["commitCorrections"][0])
        (self.root / self.relative).write_text(json.dumps(bad))
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_urls_replaced_notice_difference_recorded_history_kept(self):
        before = copy.deepcopy(self.components)
        components, refs = self.apply()
        self.assertEqual(before, self.components)
        demo = next(c for c in components if c["name"] == "demo")
        self.assertEqual([e["sourceURL"] for e in demo["evidence"]],
                         [f"https://raw.githubusercontent.com/owner/repo/{NEW}/{n}" for n in ("LICENSE-APACHE", "LICENSE-MIT", "NOTICE")])
        self.assertEqual(demo["evidence"][0]["role"], "license-text-candidate")
        self.assertEqual(demo["evidence"][2]["sha256"], g.digest(self.new_notice))
        review = demo["commitCorrectionReview"]
        self.assertEqual(review["comparedPublishedMembers"], 3)
        self.assertEqual([c["publicPath"] for c in review["changedNoticeTexts"]], ["NOTICE"])
        self.assertEqual(demo["historicalSupplementReview"]["commit"], OLD)
        self.assertIn("historical-snapshot-scope-and-NOTICE-review-pending", demo["issues"])
        self.assertIn("commit-replaced-by-approved-policy-publish-time-commit-review-pending", demo["issues"])
        files, report = g.assemble(self.root, components, refs)
        self.assertEqual(report["distributionStatus"], "not-ready")
        self.assertNotIn(OLD.encode(), files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertIn(self.new_notice, files["THIRD-PARTY-NOTICES.draft.txt"])

    def test_unchanged_notice_is_not_reported_as_changed(self):
        (self.root / "q/new/NOTICE").write_bytes(b"Old notice.\n")
        self.manifest["commitCorrections"][0]["rootFiles"][2].update(sha256=g.digest(b"Old notice.\n"), size=12)
        self.save()
        demo = next(c for c in self.apply()[0] if c["name"] == "demo")
        self.assertEqual(demo["commitCorrectionReview"]["changedNoticeTexts"], [])

    def test_tampering_rejected(self):
        self.mutate(lambda e: e.update(previousCommit="c" * 40))
        self.mutate(lambda e: e.update(commit=OLD))
        self.mutate(lambda e: e.update(commit="short"))
        self.mutate(lambda e: e.update(repository="https://github.com/other/repo"))
        self.mutate(lambda e: e.update(pathInVcs="other"))
        self.mutate(lambda e: e["crateMemberEquivalence"].pop())  # a published member is not covered
        self.mutate(lambda e: e["crateMemberEquivalence"].pop(0))  # Cargo.toml.orig is not covered
        self.mutate(lambda e: e["crateMemberEquivalence"].append(
            {"crateMember": "ghost.rs", "sourcePath": "pkg/ghost.rs", **e["crateMemberEquivalence"][1]}))
        self.mutate(lambda e: e["crateMemberEquivalence"][1].update(sha256="0" * 64))
        self.mutate(lambda e: e["rootFiles"].pop())  # evidence for NOTICE would be left on the old commit
        self.mutate(lambda e: e["rootFiles"][0].update(sha256="0" * 64))

    def test_license_bytes_must_equal_saved_text_but_notice_may_differ(self):
        body = b"Changed license.\n"
        self.manifest["commitCorrections"][0]["rootFiles"][0].update(**self.put("new/LICENSE-APACHE", body))
        self.save()
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_crate_member_difference_rejected(self):
        body = LIB + b"// changed\n"
        self.manifest["commitCorrections"][0]["crateMemberEquivalence"][1].update(**self.put("new/lib.rs", body))
        self.save()
        with self.assertRaises(p.g.AuditError):
            self.apply()


class DeclarationRecordTests(Base):
    def setUp(self):
        super().setUp()
        self.reload({"Cargo.toml": PUBLISHED, "Cargo.toml.orig": ORIG, "lib.rs": LIB}, "Apache-2.0")
        self.manifest["declarationRecords"] = [{"name": "demo", "version": "1.0", "lockSource": g.REGISTRY,
            "approvalItem": "Q13", "declaredRaw": "Apache-2.0", "repositoryDeclaredRaw": "MIT OR Apache-2.0",
            "workspaceManifest": {**self.put("ws/Cargo.toml", WS), "commit": NEW}}]
        self.save()

    def test_both_declarations_recorded_without_selection(self):
        components, refs = self.apply()
        demo = next(c for c in components if c["name"] == "demo")
        record = demo["declarationRecord"]
        self.assertEqual((record["publishedManifestDeclaration"], record["repositoryWorkspaceDeclaration"]),
                         ("Apache-2.0", "MIT OR Apache-2.0"))
        self.assertEqual(demo["spdxManifestRaw"], "Apache-2.0")
        self.assertNotIn("licenseSelection", demo)
        self.assertEqual(demo["evidence"], self.demo["evidence"])

    def test_mismatches_rejected(self):
        for field, value in [("declaredRaw", "MIT"), ("repositoryDeclaredRaw", "MIT"),
                             ("repositoryDeclaredRaw", "Apache-2.0")]:
            with self.subTest(field=field, value=value):
                bad = copy.deepcopy(self.manifest)
                bad["declarationRecords"][0][field] = value
                (self.root / self.relative).write_text(json.dumps(bad))
                with self.assertRaises(p.g.AuditError):
                    self.apply()
        bad = copy.deepcopy(self.manifest)
        bad["declarationRecords"][0]["workspaceManifest"]["sha256"] = "0" * 64
        (self.root / self.relative).write_text(json.dumps(bad))
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_original_manifest_must_inherit_workspace_license(self):
        self.reload({"Cargo.toml": PUBLISHED, "Cargo.toml.orig": PUBLISHED, "lib.rs": LIB}, "Apache-2.0")
        with self.assertRaises(p.g.AuditError):
            self.apply()


class ScopeResolutionTests(Base):
    def setUp(self):
        super().setUp()
        self.reload({"Cargo.toml": tp.CARGO, "Cargo.toml.orig": tp.CARGO, "LICENSE": LICENSE}, "MIT OR Apache-2.0")
        self.demo["issues"].append("repository-license-scope-unreviewed")
        self.demo["evidence"] = [{**self.put("LICENSE", LICENSE), "publicPath": "LICENSE",
            "role": "license-text-candidate", "sourceURL": "https://example.org/LICENSE"}]
        archive = self.put("crate.crate", (self.root / "original.crate").read_bytes())
        self.entry = {"name": "demo", "version": "1.0", "lockSource": g.REGISTRY, "approvalItem": "Q14",
            "declaredRaw": "MIT OR Apache-2.0", "manifest": {"sourcePath": "Cargo.toml", **self.put("Cargo.toml", tp.CARGO)},
            "licenseFiles": [{"sourcePath": "LICENSE", "relation": "displayed-evidence", **self.put("LICENSE", LICENSE)},
                             {"sourcePath": "sub/LICENSE", "relation": "git-symlink-target-text", **self.put("link", b"../LICENSE")}],
            "corroboration": [{"archive": archive["path"], "archiveSHA256": archive["sha256"], "archiveSize": archive["size"],
                               "member": "LICENSE", "equalsLicenseSourcePath": "LICENSE"}],
            "mustContain": ["Fixture license"], "observations": ["fixture"], "remainingOpen": ["fixture"]}
        self.manifest["scopeResolutions"] = [self.entry]
        self.save()

    def mutate(self, fn):
        bad = copy.deepcopy(self.manifest)
        fn(bad["scopeResolutions"][0])
        (self.root / self.relative).write_text(json.dumps(bad))
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_issue_replaced_and_review_state_updated_only_for_target(self):
        self.demo["standardTermsReview"] = {"chosenLicense": None}  # switches the availability block on
        components, refs = self.apply()
        demo = next(c for c in components if c["name"] == "demo")
        local = next(c for c in components if c["name"] == "local")
        self.assertNotIn("repository-license-scope-unreviewed", demo["issues"])
        self.assertIn("scope-resolution-recorded-by-approved-policy", demo["issues"])
        self.assertEqual(local, next(c for c in self.components if c["name"] == "local"))
        files, report = g.assemble(self.root, components, refs)
        files = p.finish(files, report, self.manifest)
        out = json.loads(files["internal-manifest.json"])
        record = next(c for c in out["components"] if c["name"] == "demo")
        self.assertEqual(record["licenseEvidenceAvailability"]["scopeReview"], "scope-resolution-recorded-by-approved-policy")
        self.assertEqual(record["licenseEvidenceAvailability"]["attributionReview"], "pending")
        self.assertIn("distribution-applicability-copyright-NOTICE-review-pending", record["issues"])
        unresolved = json.loads(files["unresolved-report.json"])
        item = next(c for c in unresolved["components"] if c["name"] == "demo")
        self.assertIn("scopeResolution", item)
        self.assertEqual(item["licenseEvidenceAvailability"]["scopeReview"], "scope-resolution-recorded-by-approved-policy")
        self.assertEqual(out["approvedPolicy"]["scopeResolutions"], ["demo 1.0"])
        self.assertEqual(out["distributionStatus"], "not-ready")

    def test_tampering_rejected(self):
        self.mutate(lambda e: e.update(declaredRaw="MIT"))
        self.mutate(lambda e: e["manifest"].update(sha256="0" * 64))
        self.mutate(lambda e: e["licenseFiles"][0].update(sha256="0" * 64))
        self.mutate(lambda e: e["licenseFiles"][0].update(sourcePath="OTHER"))  # not the displayed evidence
        self.mutate(lambda e: e["licenseFiles"][1].update(**self.put("link2", b"elsewhere")))
        self.mutate(lambda e: e["licenseFiles"][1].update(relation="displayed-evidence"))
        self.mutate(lambda e: e["licenseFiles"].pop(0))
        self.mutate(lambda e: e.update(mustContain=["absent wording"]))
        self.mutate(lambda e: e["corroboration"][0].update(member="Cargo.toml"))
        self.mutate(lambda e: e["corroboration"][0].update(archiveSHA256="0" * 64))

    def test_open_issue_is_required_exactly_once(self):
        self.demo["issues"].remove("repository-license-scope-unreviewed")
        with self.assertRaises(p.g.AuditError):
            self.apply()

    def test_workspace_inheritance_needs_a_pinned_workspace_manifest(self):
        inherit = b'[package]\nname="demo"\nversion={ workspace = true }\nlicense={ workspace = true }\n'
        self.entry["manifest"] = {"sourcePath": "Cargo.toml", **self.put("Cargo.toml", inherit)}
        self.manifest["scopeResolutions"] = [self.entry]
        self.save()
        with self.assertRaises(p.g.AuditError):
            self.apply()
        self.entry["workspaceManifest"] = {"sourcePath": "w/Cargo.toml", **self.put("w/Cargo.toml", WS)}
        self.save()
        self.assertIn("scope-resolution-recorded-by-approved-policy", next(c for c in self.apply()[0] if c["name"] == "demo")["issues"])
        self.entry["workspaceManifest"] = {"sourcePath": "w/Cargo.toml", **self.put("w/Cargo.toml", WS.replace(b'"1.0"', b'"2.0"'))}
        self.save()
        with self.assertRaises(p.g.AuditError):
            self.apply()


class GitHeaderTests(Base):
    def setUp(self):
        super().setUp()
        self.reload({"Cargo.toml": tp.CARGO, "Cargo.toml.orig": tp.CARGO, "lib.rs": LIB}, "MIT OR Apache-2.0", extra_git=True)
        self.url = f"https://raw.githubusercontent.com/owner/gitrepo/{GIT_COMMIT}/src/x.rs"
        self.manifest["gitSourceHeaders"] = [self.entry(SRC, REGION)]
        self.save()

    def entry(self, source, header, path="src/x.rs"):
        return {"name": "gitdemo", "version": "1.0", "lockSource": GIT_SOURCE, "approvalItem": "Q16",
                "sourcePath": path, "sourceFile": self.put("src/x.rs", source),
                "headerPath": self.put("header.txt", header)["path"], "headerSHA256": g.digest(header),
                "headerSize": len(header), "sourceURL": self.url}

    def attempt(self, source, header):
        bad = copy.deepcopy(self.manifest)
        bad["gitSourceHeaders"] = [self.entry(source, header)]
        (self.root / self.relative).write_text(json.dumps(bad))
        return self.apply()

    def test_region_function_boundaries(self):
        self.assertEqual(p.leading_comment_region(SRC), REGION)
        self.assertEqual(p.leading_comment_region(b"// a\n\n\n// b\n\n\ncode\n"), b"// a\n\n\n// b\n")
        self.assertEqual(p.leading_comment_region(b"// a\ncode // not comment\n"), b"// a\n")
        self.assertEqual(p.leading_comment_region(b"code\n// a\n"), b"")
        self.assertEqual(p.leading_comment_region(b"\n// a\n"), b"\n// a\n")  # rejected later: must start with //
        self.assertEqual(p.leading_comment_region(b"// only\n\n\n"), b"// only\n")
        self.assertEqual(p.leading_comment_region(b""), b"")

    def test_exact_region_is_added_as_header_role_and_text_is_unmodified(self):
        components, refs = self.apply()
        git = next(c for c in components if c["name"] == "gitdemo")
        self.assertEqual(git["evidence"][-1]["role"], p.HEADER_ROLE)
        self.assertEqual(git["evidence"][-1]["sourceURL"], self.url)
        self.assertIsNone(self.git.get("gitSourceHeaderReview"))
        files, report = g.assemble(self.root, components, refs)
        self.assertIn(REGION, files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertIn(REGION + b"\n===== END TEXT =====", files["THIRD-PARTY-NOTICES.draft.txt"])

    def test_two_headers_for_one_component(self):
        second = self.entry(b"// Copyright 2011 Second\n\nfn f() {}\n", b"// Copyright 2011 Second\n", "src/y.rs")
        second["sourceURL"] = self.url.replace("x.rs", "y.rs")
        first = self.manifest["gitSourceHeaders"][0]
        second["sourceFile"] = self.put("src/y.rs", b"// Copyright 2011 Second\n\nfn f() {}\n")
        second["headerPath"] = self.put("header2.txt", b"// Copyright 2011 Second\n")["path"]
        first["sourceFile"] = self.put("src/x.rs", SRC)
        first["headerPath"] = self.put("header.txt", REGION)["path"]
        self.manifest["gitSourceHeaders"] = [first, second]
        self.save()
        git = next(c for c in self.apply()[0] if c["name"] == "gitdemo")
        self.assertEqual(sum(e["role"] == p.HEADER_ROLE for e in git["evidence"]), 2)

    def test_range_boundaries_rejected(self):
        lines = REGION.splitlines(True)
        cases = {
            "short-last-line-missing": REGION[:-len(lines[-1])],
            "starts-after-first-block": b"".join(lines[3:]),
            "trailing-blank-included": REGION + b"\n",
            "code-included": REGION + b"\nuse std::io;\n",
            "no-final-newline": REGION[:-1],
            "edited": REGION.replace(b"2010", b"2011"),
            "empty": b"",
        }
        for name, header in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(p.g.AuditError):
                    self.attempt(SRC, header)

    def test_source_shape_rejected(self):
        with self.subTest("no copyright statement"):
            source = SRC.replace(b"Copyright", b"Notice")
            with self.assertRaises(p.g.AuditError):
                self.attempt(source, p.leading_comment_region(source))
        with self.subTest("two blank lines before code"):
            source = SRC.replace(b"Permission text\n\n", b"Permission text\n\n\n")
            with self.assertRaises(p.g.AuditError):
                self.attempt(source, p.leading_comment_region(source))
        with self.subTest("blank line before the first comment"):
            source = b"\n" + SRC
            with self.assertRaises(p.g.AuditError):
                self.attempt(source, p.leading_comment_region(source))
        with self.subTest("source without code after comments"):
            source = REGION
            with self.assertRaises(p.g.AuditError):
                self.attempt(source, REGION)

    def test_identity_and_url_rejected(self):
        for field, value in [("sourceURL", self.url.replace(GIT_COMMIT, "d" * 40)),
                             ("sourceURL", "https://example.org/x.rs"), ("lockSource", g.REGISTRY),
                             ("name", "demo")]:
            with self.subTest(field=field):
                bad = copy.deepcopy(self.manifest)
                bad["gitSourceHeaders"][0][field] = value
                (self.root / self.relative).write_text(json.dumps(bad))
                with self.assertRaises(p.g.AuditError):
                    self.apply()

    def test_finish_lists_all_q12_to_q16_sections(self):
        components, refs = self.apply()
        files, report = g.assemble(self.root, components, refs)
        out = json.loads(p.finish(files, report, self.manifest)["internal-manifest.json"])
        self.assertEqual(out["approvedPolicy"]["gitSourceHeaders"], ["gitdemo 1.0"])
        for key in ("commitCorrections", "declarationRecords", "scopeResolutions"):
            self.assertEqual(out["approvedPolicy"][key], [])


class AttributionReviewTests(Base):
    def setUp(self):
        super().setUp()
        self.reload({"Cargo.toml": tp.CARGO, "Cargo.toml.orig": tp.CARGO, "lib.rs": LIB, "README.md": b"Ported from Original Project.\n"},
                    "Apache-2.0")
        self.manifest["attributionReviews"] = [{"name": "demo", "version": "1.0", "lockSource": g.REGISTRY, "approvalItem": "Q19",
            "conclusion": "no further text", "basis": ["fixture"], "addedText": "none", "remainingOpen": ["fixture"],
            "crateStatements": [{"member": "README.md", "text": "Ported from Original Project."}],
            "sources": [{"url": "https://example.test/x", **self.put("src/x.txt", b"upstream statement\n")}]}]

    def test_review_is_recorded_without_adding_text(self):
        self.save()
        components, refs = self.apply(self.components)
        demo = next(c for c in components if c["name"] == "demo")
        self.assertEqual(demo["attributionReview"]["addedText"], "none")
        self.assertEqual(demo["evidence"], self.demo["evidence"])

    def test_absent_statement_changed_source_or_added_text_is_rejected(self):
        for mutate in (lambda e: e["crateStatements"][0].update(text="Not in the crate"),
                       lambda e: e["sources"][0].update(sha256="0" * 64),
                       lambda e: e.update(addedText="LICENSE")):
            self.setUp()
            mutate(self.manifest["attributionReviews"][0])
            self.save()
            with self.assertRaises(p.g.AuditError):
                self.apply(self.components)


if __name__ == "__main__":
    unittest.main()
