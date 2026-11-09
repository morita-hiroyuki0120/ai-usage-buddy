"""Exact-ID scope selection fixtures. No dependencies or network executed."""
import copy
import io
import json
import unittest
from unittest.mock import patch

import test_generator as fixtures
g = fixtures.g


class ScopeTests(unittest.TestCase):
    setUp = fixtures.NoticesTests.setUp
    component = fixtures.NoticesTests.component
    inputs = fixtures.NoticesTests.inputs
    save_inputs = fixtures.NoticesTests.save_inputs

    def scope_fixture(self):
        root = self.component("codex-app-server")
        root["normalization"] = {"originalLockVersion": "0.0.0"}
        dep = self.component("app-dep")
        other = self.component("union-only")
        # Same display name, different exact ID/source must not be merged.
        other["name"] = dep["name"]
        other["issues"] = ["Only union evidence."]
        root["issues"] = ["SDK caveat pending.", "Version scope pending."]
        root["historicalSupplementReview"] = {"status": "explicit-missing"}
        dep["evidence"] = []
        components = [other, root, dep]
        graph = {"target": "aarch64-apple-darwin",
                 "closures": {"releaseUnion": [c["identity"] for c in components],
                              "appServer": [dep["identity"], root["identity"]]},
                 "counts": {"releaseUnionPackages": 3, "appServerPackages": 2}}
        return components, graph

    def test_union_default_and_explicit_output_bytes_are_legacy_identical(self):
        self.inputs()
        components, refs = g.load_components(self.root, "inputs", supplement_relative=None,
                                             historical_relative=None)
        expected = {
            "THIRD-PARTY-NOTICES.draft.txt": "42f0528b66650a676d82386fd74a7045c7654a5e6f06ac25ac5a6ca7cb4a6cf8",
            "internal-manifest.json": "2541c6eb727f11c82c31c334d619ca6856e06b7e00d652ac87128dfd7a893354",
            "unresolved-report.json": "adf6d3aa605a190859a749e92f3f4d13e277a69b6cc7a7ae0e342b71298598f5"}
        for args in [(), ("release-union",)]:
            selected, context = g.select_input_scope(self.root, components, refs, *args)
            self.assertIsNone(context)
            files, _ = g.assemble(self.root, selected, refs, context)
            self.assertEqual({n:g.digest(b) for n,b in files.items()}, expected)

    def test_app_server_exact_ids_exclude_union_only_not_name_matching(self):
        components, graph = self.scope_fixture()
        selected, context = g.select_scope(components, graph, "app-server")
        self.assertEqual({c["identity"] for c in selected}, set(graph["closures"]["appServer"]))
        self.assertNotIn(components[0]["identity"], {c["identity"] for c in selected})
        self.assertEqual(context["root"]["name"], "codex-app-server")
        self.assertEqual(context["excludedUnionComponents"], 1)

    def test_unknown_scope_rejected_by_api_and_cli_before_output(self):
        components, graph = self.scope_fixture()
        with self.assertRaises(g.AuditError):
            g.select_scope(components, graph, "appserver")
        with patch("sys.argv", ["generator", "--scope", "wrong", "--output", "build/new"]), \
             patch("sys.stderr", new_callable=io.StringIO), patch.object(g, "load_components") as load:
            with self.assertRaises(SystemExit) as result:
                g.main()
            self.assertEqual(result.exception.code, 2)
            load.assert_not_called()

    def test_graph_subset_count_duplicates_root_target_and_union_mismatch_fail(self):
        components, original = self.scope_fixture()
        for kind in ("outside", "count", "duplicate", "root", "target", "union"):
            with self.subTest(kind=kind):
                graph = copy.deepcopy(original)
                if kind == "outside":
                    graph["closures"]["appServer"][0] = "unknown-exact-ID"
                elif kind == "count":
                    graph["counts"]["appServerPackages"] = 3
                elif kind == "duplicate":
                    graph["closures"]["appServer"] = [components[1]["identity"]]*2
                elif kind == "root":
                    graph["closures"]["appServer"] = [components[0]["identity"], components[2]["identity"]]
                elif kind == "target":
                    graph["target"] = "x86_64-unknown-linux-gnu"
                else:
                    graph["closures"]["releaseUnion"][0] = "unknown-exact-ID"
                with self.assertRaises(g.AuditError):
                    g.select_scope(components, graph, "app-server")

    def test_header_manifest_completion_and_obligations_preserved(self):
        components, graph = self.scope_fixture()
        selected, context = g.select_scope(components, graph, "app-server")
        files, report = g.assemble(self.root, selected, [], context)
        text = files["THIRD-PARTY-NOTICES.draft.txt"]
        self.assertIn(b"Scope: app-server\nRoot: codex-app-server 1.0\n", text)
        self.assertIn(b"2 source-derived conservative candidates; not binary inclusion proof", text)
        self.assertNotIn(b"Only union evidence.", text)
        self.assertEqual(report["summary"]["unresolvedComponents"], 2)
        self.assertEqual(report["summary"]["withoutFullLicenseCandidate"], 1)
        root = next(c for c in report["components"] if c["name"] == "codex-app-server")
        self.assertIn("SDK caveat pending.", root["issues"])
        self.assertIn("Version scope pending.", root["issues"])
        self.assertEqual(root["historicalSupplementReview"]["status"], "explicit-missing")
        self.assertTrue(all("distribution-applicability-copyright-NOTICE-review-pending" in c["issues"]
                            for c in report["components"]))
        marker = g.publish(self.root, "build/scoped", files, context)
        for doc in (report, json.loads(files["unresolved-report.json"]), marker):
            self.assertEqual(doc["scopeSelection"], context)
            self.assertEqual(doc["status"], "draft-not-approved")
            self.assertEqual(doc["distributionStatus"], "not-ready")
        self.assertEqual(files, g.assemble(self.root, list(reversed(selected)), [], context)[0])

    def test_scope_graph_hash_tampering_and_symlink_rejected(self):
        components, graph = self.scope_fixture()
        path = "inputs/target-closure-followup/target-closure-inventory.json"
        actual = self.root/path
        actual.parent.mkdir(parents=True)
        original = json.dumps(graph).encode()
        actual.write_bytes(original)
        refs = [{"path": path, "sha256": g.digest(original)}]
        _, context = g.select_input_scope(self.root, components, refs, "app-server")
        self.assertEqual(context["graph"], refs[0])
        actual.write_bytes(original+b" ")
        with self.assertRaises(g.AuditError):
            g.select_input_scope(self.root, components, refs, "app-server")
        actual.unlink()
        actual.symlink_to(self.root/"LICENSE")
        with self.assertRaises(g.AuditError):
            g.select_input_scope(self.root, components, refs, "app-server")

    def test_cli_default_and_app_scope_are_explicitly_forwarded(self):
        components, graph = self.scope_fixture()
        path = "inputs/target-closure-followup/target-closure-inventory.json"
        actual = self.root/path
        actual.parent.mkdir(parents=True)
        original = json.dumps(graph).encode()
        actual.write_bytes(original)
        refs = [{"path": path, "sha256": g.digest(original)}]
        for option, scope, count in [([], None, 3), (["--scope", "release-union"], None, 3),
                                     (["--scope", "app-server"], "app-server", 2)]:
            with self.subTest(scope=option), \
                 patch("sys.argv", ["generator", "--root", str(self.root), "--output", "build/new"]+option), \
                 patch.object(g, "load_components", return_value=(components, refs)), \
                 patch.object(g, "publish") as publish, patch("sys.stdout", new_callable=io.StringIO) as out:
                self.assertEqual(g.main(), 0)
                result = json.loads(out.getvalue())
                self.assertEqual(result["components"], count)
                self.assertEqual(result.get("scopeSelection", {}).get("scope"), scope)
                self.assertEqual(publish.call_args.args[3], result.get("scopeSelection"))

    def test_assembly_rejects_context_component_drop(self):
        components, graph = self.scope_fixture()
        selected, context = g.select_scope(components, graph, "app-server")
        with self.assertRaises(g.AuditError):
            g.assemble(self.root, selected[:-1], [], context)


if __name__ == "__main__":
    unittest.main()
