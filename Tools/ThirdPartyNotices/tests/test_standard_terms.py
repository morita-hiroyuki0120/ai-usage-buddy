"""Opt-in reference terms fixtures; not real copyright or licensing approval."""
import copy
import io
import json
import tarfile
import unittest
from unittest.mock import patch

import test_generator as fixtures
g = fixtures.g


class StandardTermsTests(unittest.TestCase):
    setUp_base = fixtures.NoticesTests.setUp
    inputs = fixtures.NoticesTests.inputs
    save_inputs = fixtures.NoticesTests.save_inputs

    def setUp(self):
        self.setUp_base()
        self.inputs()
        self.relative = "inputs/standard-reference/manifest.json"
        self.folder = (self.root/self.relative).parent
        (self.folder/"text").mkdir(parents=True)
        self.bodies = {"MIT": b"Fixture MIT reference. Copyright (c) <year> <copyright holders>\n",
                       "Apache-2.0": b"Fixture Apache reference. Copyright [yyyy] [name of copyright owner]\n"}
        pins = {id_:(g.digest(b),len(b)) for id_,b in self.bodies.items()}
        pin_patch = patch.dict(g.SPDX_TEXT_PINS, pins, clear=True)
        pin_patch.start()
        self.addCleanup(pin_patch.stop)
        self.files = []
        for id_, body in self.bodies.items():
            member = "text/"+id_+".txt"
            path = self.folder/member
            path.write_bytes(body)
            self.files.append({"licenseID": id_, "member": member,
                "sourceURL": f"https://raw.githubusercontent.com/spdx/license-list-data/{g.SPDX_COMMIT}/{member}",
                "sourceCommit":g.SPDX_COMMIT,"path":str(path.relative_to(self.root)),
                "sha256":g.digest(body),"size":len(body),"role":"standard-license-text"})
        resolution = json.dumps({"sha":g.SPDX_COMMIT}).encode()
        (self.folder/"commit.json").write_bytes(resolution)
        raw = "MIT OR Apache-2.0"
        meta = ('[package]\nname="demo"\nversion="1.0"\nlicense="'+raw+'"\n').encode()
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode="w:gz") as tar:
            info = tarfile.TarInfo("demo-1.0/Cargo.toml")
            info.size = len(meta)
            tar.addfile(info,io.BytesIO(meta))
        archive = out.getvalue()
        (self.root/"original.crate").write_bytes(archive)
        lock = self.data["cargo-lock-license-inventory.json"]["packages"][0]
        lock["checksum"] = g.digest(archive)
        lock["licenseEvidence"].update(archive="original.crate",sha256=g.digest(archive),lockChecksum=g.digest(archive))
        self.data["target-closure-followup/metadata-aarch64.json"]["packages"][0]["license"] = raw
        self.save_inputs()
        self.components,self.refs = g.load_components(self.root,"inputs",supplement_relative=None,historical_relative=None)
        demo = next(c for c in self.components if c["name"]=="demo")
        demo["issues"] += ["SDK caveat pending.","Historical version 0.8.1 versus 0.9.0."]
        demo["historicalSupplementReview"] = {"status":"explicit-missing"}
        self.package = {"name":"demo","version":"1.0","lockSource":g.REGISTRY,
                        "crateSHA256":g.digest(archive),"archivePath":"original.crate",
                        "spdxManifestRaw":raw,"licenseIDs":["MIT","Apache-2.0"],"chosenLicense":None}
        self.manifest = {"schemaVersion":1,"status":"draft-not-approved","distributionStatus":"not-ready",
            "sourceRepository":g.SPDX_REPOSITORY,"sourceCommit":g.SPDX_COMMIT,"files":self.files,
            "commitResolution":{"path":str((self.folder/"commit.json").relative_to(self.root)),
                "sha256":g.digest(resolution),"size":len(resolution),
                "sourceURL":"https://api.github.com/repos/spdx/license-list-data/commits/main"},
            "packages":[self.package]}
        self.save()

    def save(self):
        (self.root/self.relative).write_text(json.dumps(self.manifest),encoding="utf-8")

    def attach(self):
        return g.attach_standard_terms(self.root,self.components,self.refs,self.relative)

    def test_opt_in_only_leaves_legacy_bytes_unchanged(self):
        before = g.assemble(self.root,self.components,self.refs)[0]
        components,refs = g.attach_standard_terms(self.root,self.components,self.refs)
        self.assertIs(components,self.components)
        self.assertIs(refs,self.refs)
        self.assertEqual(before,g.assemble(self.root,components,refs)[0])
        self.assertNotIn(b"Standard-license-text:",before["THIRD-PARTY-NOTICES.draft.txt"])

    def test_roles_placeholders_raw_OR_and_caveats_remain_separate(self):
        components,refs = self.attach()
        files,report = g.assemble(self.root,components,refs)
        demo = next(c for c in report["components"] if c["name"]=="demo")
        self.assertFalse(demo["licenseEvidenceAvailability"]["upstreamFullTextAvailable"])
        self.assertTrue(demo["licenseEvidenceAvailability"]["standardTermsAvailable"])
        self.assertIsNone(demo["standardTermsReview"]["chosenLicense"])
        self.assertEqual(demo["spdxManifestRaw"],"MIT OR Apache-2.0")
        self.assertEqual({e["role"] for e in demo["texts"]},{"standard-license-text"})
        for issue in ("SDK caveat pending.","Historical version 0.8.1 versus 0.9.0.",
                      "no-full-license-text-candidate","distribution-applicability-copyright-NOTICE-review-pending"):
            self.assertIn(issue,demo["issues"])
        self.assertEqual(demo["historicalSupplementReview"],{"status":"explicit-missing"})
        self.assertEqual(report["summary"]["standardTermsComponents"],1)
        self.assertEqual(report["summary"]["standardTermsReferences"],2)
        self.assertEqual(report["summary"]["withoutFullLicenseCandidate"],1)
        text = files["THIRD-PARTY-NOTICES.draft.txt"]
        self.assertIn(b"NOT text obtained from the component upstream",text)
        self.assertIn(b"Holder/year placeholders are unchanged",text)
        for body in self.bodies.values():self.assertIn(body,text)
        self.assertIn(self.body,text)  # Existing root license and NOTICE unchanged.
        self.assertEqual(report["summary"]["unresolvedComponents"],2)
        unresolved = json.loads(files["unresolved-report.json"])
        self.assertTrue(next(c for c in unresolved["components"] if c["name"]=="demo")["licenseEvidenceAvailability"]["standardTermsAvailable"])
        self.assertEqual(files,g.assemble(self.root,list(reversed(components)),refs)[0])
        # Adapter must not mutate the legacy component list.
        self.assertFalse(any(c.get("standardTermsReview") for c in self.components))

    def test_wrong_commit_hash_member_role_and_license_ID_rejected(self):
        baseline = copy.deepcopy(self.manifest)
        for field,value in [("sourceCommit","a"*40),("sourceRepository","https://github.com/other/repo")]:
            with self.subTest(field=field):
                self.manifest = copy.deepcopy(baseline);self.manifest[field]=value;self.save()
                with self.assertRaises(g.AuditError):self.attach()
        for field,value in [("sourceCommit","a"*40),("sha256","0"*64),("size",1),
                            ("licenseID","BSD-3-Clause"),("member","text/Apache-2.0.txt"),
                            ("role","license-text-candidate"),
                            ("sourceURL","https://raw.githubusercontent.com/spdx/license-list-data/main/text/MIT.txt")]:
            with self.subTest(fileField=field):
                self.manifest = copy.deepcopy(baseline);self.manifest["files"][0][field]=value;self.save()
                with self.assertRaises(g.AuditError):self.attach()

    def test_name_version_source_checksum_declaration_and_OR_selection_rejected(self):
        baseline = copy.deepcopy(self.manifest)
        for field,value in [("name","DEMO"),("version","2.0"),("lockSource","other"),
                            ("crateSHA256","0"*64),("archivePath","LICENSE"),
                            ("spdxManifestRaw","MIT"),("licenseIDs",["MIT"]),
                            ("licenseIDs",["MIT","MIT"]),("chosenLicense","MIT")]:
            with self.subTest(field=field,value=value):
                self.manifest = copy.deepcopy(baseline);self.manifest["packages"][0][field]=value;self.save()
                with self.assertRaises(g.AuditError):self.attach()

    def test_body_tamper_even_with_rewritten_record_hash_rejected(self):
        f=self.files[0];path=self.root/f["path"];body=path.read_bytes()+b"tampered"
        path.write_bytes(body);f.update(sha256=g.digest(body),size=len(body));self.save()
        with self.assertRaises(g.AuditError):self.attach()

    def test_outside_collection_symlink_and_missing_target_rejected(self):
        baseline=copy.deepcopy(self.manifest)
        self.manifest["files"][0]["path"]="LICENSE";self.save()
        with self.assertRaises(g.AuditError):self.attach()
        self.manifest=copy.deepcopy(baseline);self.save()
        path=self.root/self.manifest["files"][0]["path"]
        path.unlink();path.symlink_to(self.root/"LICENSE")
        with self.assertRaises(g.AuditError):self.attach()
        path.unlink();path.write_bytes(self.bodies["MIT"])
        with self.assertRaises(g.AuditError):
            g.attach_standard_terms(self.root,[],self.refs,self.relative)

    def test_commit_resolution_and_original_archive_tamper_rejected(self):
        p=self.folder/"commit.json";p.write_text(json.dumps({"sha":"a"*40}))
        self.manifest["commitResolution"].update(sha256=g.digest(p.read_bytes()),size=len(p.read_bytes()));self.save()
        with self.assertRaises(g.AuditError):self.attach()
        p.write_text(json.dumps({"sha":g.SPDX_COMMIT}))
        self.manifest["commitResolution"].update(sha256=g.digest(p.read_bytes()),size=len(p.read_bytes()));self.save()
        (self.root/"original.crate").write_bytes(b"tampered")
        with self.assertRaises(g.AuditError):self.attach()


if __name__ == "__main__":
    unittest.main()
