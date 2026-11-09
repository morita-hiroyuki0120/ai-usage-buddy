"""Historical schema-2 fixtures; dependency sources are data, never executed."""
import copy
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

import test_generator as fixtures
g = fixtures.g


class HistoricalTests(unittest.TestCase):
    save_inputs = fixtures.NoticesTests.save_inputs

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "build").mkdir()
        self.body = b"Copyright (c) Fixture Holder.\r\nFixture terms only.\r\n"
        (self.root / "LICENSE").write_bytes(self.body)
        fixtures.NoticesTests.inputs(self)
        self.base = Path("inputs")
        self.folder = self.base / "license-supplement-20261023-3"
        self.commit = "a"*40
        self.repo = "https://github.com/example/demo"
        self.header = b"/* Copyright (c) Fixture Holder. */\nNever execute dependency code.\n"
        self.meta = (b'[package]\nname="demo"\nversion="1.0"\nlicense="MIT"\n'
                     b'repository="https://github.com/example/demo"\n')
        self.source = {"pkg/Cargo.toml": self.meta, "pkg/src/lib.rs": self.header,
                       "LICENSE-MIT": self.body, "NOTICE": b"Actual fixture NOTICE.\n",
                       "Cargo.toml": b'[workspace.package]\nlicense="MIT OR Apache-2.0"\n'}
        self.crate = {"Cargo.toml": self.meta, "Cargo.toml.orig": self.meta,
                      "src/lib.rs": self.header}
        archive = self.tar_bytes(self.crate)
        (self.root / "original.crate").write_bytes(archive)
        lock = self.data["cargo-lock-license-inventory.json"]["packages"][0]
        lock.update(checksum=g.digest(archive))
        lock["licenseEvidence"].update(archive="original.crate", sha256=g.digest(archive),
                                        lockChecksum=g.digest(archive))
        self.files = []
        for path, body in self.crate.items():
            f = self.record("crate/"+path, body,
                sourcePath=path, archiveMember="demo-1.0/"+path,
                sourceURL="https://static.crates.io/crates/demo/demo-1.0.crate#demo-1.0/"+path,
                role="source-header-not-license-terms" if path.endswith(".rs") else "crate-provenance")
            self.files.append(f)
        for path in self.source:
            self.files.append(self.record("snapshot/"+path, self.source[path],
                sourcePath=path, sourceURL=self.raw(path),
                role="full-license-text" if path.startswith("LICENSE") else
                "actual-upstream-NOTICE" if path=="NOTICE" else "scope-reference-not-license-terms"))
        self.rows = []
        for path in ["Cargo.toml.orig", "src/lib.rs"]:
            upstream = "pkg/"+("Cargo.toml" if path=="Cargo.toml.orig" else path)
            self.rows.append({"crateMember":"demo-1.0/"+path, "sourcePath":upstream,
                              "crateSHA256":g.digest(self.crate[path]),
                              "upstreamSHA256":g.digest(self.source[upstream]),
                              "byteIdentical":True, "gitBlobSHA1":self.blob(self.source[upstream])})
        comparison = self.record("comparison.json", self.encode(self.rows), role="comparison-metadata")
        self.package = {"name":"demo", "version":"1.0", "lockSource":g.REGISTRY,
            "archivePath":"original.crate", "crateSHA256":g.digest(archive),
            "repository":self.repo, "sourceSnapshotRepository":self.repo,
            "commit":self.commit, "pathInVcs":"pkg", "sourceSnapshotManifestVersion":"1.0",
            "crateVCSInfo":None, "spdxManifestRaw":"MIT", "status":"evidence-complete-for-review",
            "distributionStatus":"not-ready", "files":self.files, "sourceComparison":comparison,
            "fullLicensePaths":[str(self.folder/"snapshot/LICENSE-MIT")],
            "upstreamFullLicenseCandidatePaths":[str(self.folder/"snapshot/LICENSE-MIT")],
            "attributionPaths":[str(self.folder/"crate/src/lib.rs")],
            "NOTICEpaths":[str(self.folder/"snapshot/NOTICE")],
            "NOTICEscope":{"collected":["NOTICE"]}, "pathScope":["fixture source equivalence"],
            "explicitMissing":[], "reviewPending":["Fixture applicability pending."],
            "commitBinding":"historical snapshot, not original VCS"}
        self.responses = []
        self.response("snapshot.tar.gz", "https://codeload.github.com/example/demo/tar.gz/"+self.commit,
                      self.tar_bytes(self.source))
        self.response("version.json", "https://crates.io/api/v1/crates/demo/1.0", self.encode({
            "version":{"crate":"demo","num":"1.0","checksum":g.digest(archive),
                       "repository":self.repo,"created_at":"2020-01-03T00:00:00Z"}}))
        self.response("commit.json",
            "https://api.github.com/repos/example/demo/commits?until=2020-01-02T00%3A00%3A00Z&per_page=1",
            self.encode([{"sha":self.commit,
                          "html_url":self.repo+"/commit/"+self.commit,
                          "commit":{"committer":{"date":"2020-01-01T00:00:00Z"}}}]))
        self.manifest = {"schemaVersion":2,"status":"draft-not-approved","distributionStatus":"not-ready",
            "packages":[self.package],"reuseVerification":[], "publicHTTPRequests":self.responses,
            "requestLimit":16,"summary":{"filesToVerify":len(self.files)+1}}
        count=len(self.files)
        self.receipt={"manifestSHA256ReportedByParent":"",
            "countClarification":{"packagesFilesReferences":count,
                "packagesFilesUniquePaths":count,"combinedUniqueFileCount":count+1}}
        self.seal()

    @staticmethod
    def encode(value):
        return (json.dumps(value,sort_keys=True)+"\n").encode()

    @staticmethod
    def blob(b):
        return hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()

    @staticmethod
    def tar_bytes(files, unsafe=False):
        out=io.BytesIO()
        with tarfile.open(fileobj=out,mode="w:gz") as tar:
            for path,body in files.items():
                info=tarfile.TarInfo("fixture/"+path)
                info.size=len(body)
                tar.addfile(info,io.BytesIO(body))
            if unsafe:
                info=tarfile.TarInfo("../escape");info.size=1
                tar.addfile(info,io.BytesIO(b"x"))
        return out.getvalue()

    def raw(self,path):
        return "https://raw.githubusercontent.com/example/demo/"+self.commit+"/"+path

    def record(self,path,b,**fields):
        path=self.folder/path
        (self.root/path).parent.mkdir(parents=True,exist_ok=True)
        (self.root/path).write_bytes(b)
        return {"localPath":str(path),"sha256":g.digest(b),"size":len(b),
                "gitBlobSHA1":self.blob(b),**fields}

    def response(self,name,url,b):
        path=self.folder/"downloads"/name
        (self.root/path).parent.mkdir(parents=True,exist_ok=True)
        (self.root/path).write_bytes(b)
        self.responses.append({"request":len(self.responses)+1,"file":name,"url":url,
                               "sha256":g.digest(b),"size":len(b)})

    def replace_response(self,index,b):
        r=self.responses[index]
        (self.root/self.folder/"downloads"/r["file"]).write_bytes(b)
        r.update(sha256=g.digest(b),size=len(b))

    def seal(self):
        self.save_inputs()
        path=self.folder/"manifest.json"
        (self.root/path).write_bytes(self.encode(self.manifest))
        self.receipt["manifestSHA256ReportedByParent"]=g.digest((self.root/path).read_bytes())
        (self.root/self.folder/"parent-verification-20261023.json").write_bytes(self.encode(self.receipt))

    def load(self):
        self.seal()
        return g.load_components(self.root,"inputs",supplement_relative=None)

    def test_success_notice_header_and_counts_not_original_vcs(self):
        components,refs=self.load()
        files,report=g.assemble(self.root,components,refs)
        demo=next(c for c in report["components"] if c["name"]=="demo")
        review=demo["historicalSupplementReview"]
        self.assertEqual(review["validationCounts"]["packageFileReferences"],len(self.files))
        self.assertIn("not original VCS",review["commitBinding"])
        self.assertNotIn("no-full-license-text-candidate",demo["issues"])
        self.assertIn(self.body,files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertIn(b"Actual fixture NOTICE.",files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertNotIn(b"Never execute dependency code.",files["THIRD-PARTY-NOTICES.draft.txt"])
        self.assertEqual(report["distributionStatus"],"not-ready")
        self.assertEqual(files,g.assemble(self.root,list(reversed(components)),refs)[0])

    def test_historical_version_difference_is_not_promoted(self):
        self.source["pkg/Cargo.toml"]=self.meta.replace(b'version="1.0"',b'version="0.8.1"')
        new=self.source["pkg/Cargo.toml"]
        record=next(f for f in self.files if f.get("sourcePath")=="pkg/Cargo.toml")
        record.update(self.record("snapshot/pkg/Cargo.toml",new,sourcePath="pkg/Cargo.toml",
                      sourceURL=self.raw("pkg/Cargo.toml"),role="scope-reference-not-license-terms"))
        row=self.rows[0];row.update(upstreamSHA256=g.digest(new),byteIdentical=False,
                                    gitBlobSHA1=self.blob(new))
        self.package["sourceComparison"].update(self.record(
            "comparison.json",self.encode(self.rows),role="comparison-metadata"))
        self.replace_response(0,self.tar_bytes(self.source))
        self.package.update(sourceSnapshotManifestVersion="0.8.1",status="explicit-missing",
                            fullLicensePaths=[],explicitMissing=["Version scope pending; MIT declaration confirmed."])
        c,refs=self.load();_,report=g.assemble(self.root,c,refs)
        demo=next(c for c in report["components"] if c["name"]=="demo")
        self.assertIn("no-full-license-text-candidate",demo["issues"])
        self.package.update(status="evidence-complete-for-review",
                            fullLicensePaths=self.package["upstreamFullLicenseCandidatePaths"][:])
        with self.assertRaisesRegex(g.AuditError,"version mismatch"):
            self.load()

    def test_comparison_claim_hash_and_coverage_tamper_fail(self):
        baseline=copy.deepcopy(self.rows)
        for kind in ["hash","claim","coverage"]:
            with self.subTest(kind=kind):
                self.rows=copy.deepcopy(baseline)
                if kind=="hash":self.rows[1]["crateSHA256"]="0"*64
                elif kind=="claim":self.rows[1]["byteIdentical"]=False
                else:self.rows.pop()
                self.package["sourceComparison"].update(self.record(
                    "comparison.json",self.encode(self.rows),role="comparison-metadata"))
                with self.assertRaises(g.AuditError):self.load()

    def test_identity_and_snapshot_commit_repo_fail(self):
        for field,bad in [("version","2.0"),("lockSource","other"),
                          ("crateSHA256","0"*64),("commit","b"*40),
                          ("sourceSnapshotRepository","https://github.com/other/repo")]:
            original=self.package[field]
            with self.subTest(field=field):
                self.package[field]=bad
                with self.assertRaises((g.AuditError,KeyError)):self.load()
            self.package[field]=original

    def test_notice_and_copyright_cannot_be_dropped_or_readme_promoted(self):
        for field in ["NOTICEpaths","attributionPaths"]:
            original=self.package[field]
            self.package[field]=[]
            with self.subTest(field=field),self.assertRaises(g.AuditError):self.load()
            self.package[field]=original
        original=self.package["fullLicensePaths"]
        manifest_path=str(self.folder/"snapshot/Cargo.toml")
        f=next(f for f in self.files if f["localPath"]==manifest_path)
        f["role"]="full-license-text"
        self.package["fullLicensePaths"]=[manifest_path]
        self.package["upstreamFullLicenseCandidatePaths"]=[manifest_path]
        with self.assertRaisesRegex(g.AuditError,"ancestor license"):self.load()

    def test_collection_tamper_symlink_response_hash_and_reference_counts(self):
        original=self.files[0]["sha256"]
        self.files[0]["sha256"]="0"*64
        with self.assertRaises(g.AuditError):self.load()
        self.files[0]["sha256"]=original
        self.receipt["countClarification"]["packagesFilesReferences"]+=1
        with self.assertRaisesRegex(g.AuditError,"counts"):self.load()
        self.receipt["countClarification"]["packagesFilesReferences"]-=1
        self.responses[0]["sha256"]="0"*64
        with self.assertRaisesRegex(g.AuditError,"response hash"):self.load()
        self.responses[0]["sha256"]=g.digest((self.root/self.folder/"downloads/snapshot.tar.gz").read_bytes())
        path=self.root/self.files[0]["localPath"]
        original_body=path.read_bytes();path.unlink();path.symlink_to(self.root/"LICENSE")
        with self.assertRaisesRegex(g.AuditError,"symlink"):self.load()
        path.unlink();path.write_bytes(original_body)
        original_path=self.files[0]["localPath"];self.files[0]["localPath"]="LICENSE"
        with self.assertRaisesRegex(g.AuditError,"outside collection"):self.load()
        self.files[0]["localPath"]=original_path

    def test_semantically_invalid_api_or_unsafe_archive_fail(self):
        self.replace_response(1,self.encode({"version":{"crate":"demo","num":"1.0",
            "checksum":"0"*64,"repository":self.repo,"created_at":"2020-01-03T00:00:00Z"}}))
        with self.assertRaisesRegex(g.AuditError,"API identity"):self.load()
        # Archive path validation precedes API identity checks.
        self.replace_response(0,self.tar_bytes(self.source,unsafe=True))
        with self.assertRaisesRegex(g.AuditError,"unsafe historical archive"):self.load()

    def test_inconsistent_shared_reference_is_rejected(self):
        other=copy.deepcopy(self.package);other["name"]="other"
        other["files"][-1]["role"]="full-license-text"
        self.manifest["packages"].append(other)
        with self.assertRaisesRegex(g.AuditError,"duplicate historical reference"):
            self.load()


if __name__=="__main__":
    unittest.main()
