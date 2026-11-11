#!/usr/bin/env python3
"""Draft-only wrapper that applies the 2026-11-11 human policy decisions (Q2, Q3, Q5).

It reuses scripts/generate-third-party-notices.py unchanged and adds an explicit,
hash-pinned policy manifest on top of the standard-terms draft.
Policy approval is not approval of the final text: output stays draft-not-approved / not-ready.
Never executes dependency code and never uses the network.
"""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import tarfile
import tomllib

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/generate-third-party-notices.py"
_spec = importlib.util.spec_from_file_location("notices_generator", SCRIPT)
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)

HEADER_ROLE = "source-header-line-comment-not-license-terms"
LICENSE_FILE_FOR = {"Apache-2.0": "LICENSE-APACHE", "MIT": "LICENSE-MIT"}
SUPERSEDED_ISSUE_MARK = "version-specific scope remains for review"
GITHUB_COMMIT = re.compile("[0-9a-f]{40}")


def _read(root, relative, expected_sha, expected_size):
    data = g.safe_file(root, relative).read_bytes()
    g.need(g.digest(data) == expected_sha and len(data) == expected_size,
           "policy file hash/size mismatch")
    return data


def _crate_members(archive):
    """Regular members only; links are never followed or extracted."""
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if member.isfile() and "/" in member.name:
                files[member.name.split("/", 1)[1]] = tar.extractfile(member).read()
    return files


def apply_policy(root, components, input_refs, relative):
    """Return new components and refs; the input list is never mutated."""
    manifest = g.read_json(root, relative)
    g.need(manifest["schemaVersion"] == 1 and manifest["status"] == "draft-not-approved" and
           manifest["distributionStatus"] == "not-ready", "unsafe policy supplement status")
    approval = manifest["policyApproval"]
    g.need(approval["items"] and approval["scope"] ==
           "policy direction only; not approval of the final text", "policy approval scope invalid")
    refs = list(input_refs)
    refs.append({"path": str(relative), "sha256": g.digest(g.safe_file(root, relative).read_bytes())})
    inventories = [r for r in input_refs if r["path"].endswith("/cargo-lock-license-inventory.json")]
    g.need(len(inventories) == 1, "missing/ambiguous policy lock inventory")
    g.need(g.digest(g.safe_file(root, inventories[0]["path"]).read_bytes()) ==
           inventories[0]["sha256"], "policy lock inventory changed")
    bylock = g.unique_index(g.read_json(root, inventories[0]["path"])["packages"], g.key)
    bycomponent = g.unique_index(components, lambda c: tuple(c["lockIdentity"]))
    updated, seen = {}, set()

    def target(kind, entry):
        identity = (entry["name"], entry["version"], entry["lockSource"])
        g.need(identity in bycomponent and identity in bylock and (kind, identity) not in seen,
               "policy target absent, duplicated or not in lock")
        seen.add((kind, identity))
        return identity, updated.get(identity, bycomponent[identity]), bylock[identity]

    def crate_files(identity, lock):
        g.need(identity[2] == g.REGISTRY and lock["category"] == "registry", "policy target is not a registry crate")
        archive = g.safe_file(root, lock["licenseEvidence"]["archive"]).read_bytes()
        g.need(g.digest(archive) == lock["checksum"], "policy crate archive hash mismatch")
        return _crate_members(archive)

    def pin(entry):
        _read(root, entry["path"], entry["sha256"], entry["size"])
        refs.append({"path": entry["path"], "sha256": entry["sha256"]})

    # Q2: replace the historical snapshot commit with the version-aligned commit.
    for entry in manifest.get("commitReplacements", []):
        identity, component, lock = target("commit", entry)
        crate = crate_files(identity, lock)
        review = component.get("historicalSupplementReview")
        g.need(review is not None and review["commit"] == entry["previousCommit"] and
               GITHUB_COMMIT.fullmatch(entry["commit"]) and entry["commit"] != entry["previousCommit"],
               "policy previous/new commit mismatch")
        repo = review["sourceSnapshotRepository"]
        g.need(entry["repository"] == repo and review["spdxManifestRaw"] == component["spdxManifestRaw"],
               "policy repository/declaration mismatch")
        directory = entry["pathInVcs"]
        for check in entry["crateMemberEquivalence"]:
            body = _read(root, check["path"], check["sha256"], check["size"])
            g.need(crate.get(check["crateMember"]) == body, "policy crate member differs from fixed commit file")
            refs.append({"path": check["path"], "sha256": check["sha256"]})
            if check["sourcePath"] == directory + "/Cargo.toml":
                meta = tomllib.loads(body.decode("utf-8"))["package"]
                g.need((meta["name"], meta["version"], meta["license"]) ==
                       (identity[0], identity[1], component["spdxManifestRaw"]) and
                       meta["version"] == entry["snapshotManifestVersion"],
                       "policy fixed-commit manifest version/declaration mismatch")
        g.need(any(c["sourcePath"] == directory + "/Cargo.toml" for c in entry["crateMemberEquivalence"]),
               "policy fixed-commit manifest not checked")
        prior = {Path(p).name: p for p in review["upstreamFullLicenseCandidatePaths"]}
        evidence = []
        for f in entry["licenseFiles"]:
            body = _read(root, f["path"], f["sha256"], f["size"])
            old = prior.get(f["sourcePath"])
            g.need(old is not None and g.safe_file(root, old).read_bytes() == body and
                   g.candidate_role(f["sourcePath"]) == "license-text-candidate",
                   "policy license text differs from previously saved text")
            refs.append({"path": f["path"], "sha256": f["sha256"]})
            evidence.append({"path": f["path"], "sha256": f["sha256"], "size": f["size"],
                             "publicPath": f["sourcePath"], "role": "license-text-candidate",
                             "sourceURL": f"https://raw.githubusercontent.com/{repo.split('github.com/')[1]}/"
                                          f"{entry['commit']}/{f['sourcePath']}"})
        g.need(len(evidence) >= 2, "policy license files missing")
        issues = [i for i in component["issues"] if SUPERSEDED_ISSUE_MARK not in i]
        g.need(len(issues) == len(component["issues"]) - 1, "policy superseded issue not found exactly once")
        issues.append("commit-replaced-by-approved-policy-version-aligned-review-pending")
        updated[identity] = {**component, "issues": issues,
            "evidence": [*component["evidence"], *evidence],
            "commitReplacementReview": {
                "previousCommit": entry["previousCommit"],
                "previousSnapshotManifestVersion": review["sourceSnapshotManifestVersion"],
                "commit": entry["commit"], "snapshotManifestVersion": entry["snapshotManifestVersion"],
                "repository": repo, "pathInVcs": directory,
                "verified": "crate members and fixed-commit Cargo.toml checked byte-for-byte; license texts equal the previously saved bytes",
                "notes": entry["notes"],
                "interpretation": "Version-alignment candidate only; applicability, copyright and NOTICE review remain pending."}}

    # Q3: exact leading line-comment header from the crate source member.
    for entry in manifest.get("sourceHeaders", []):
        identity, component, lock = target("header", entry)
        crate = crate_files(identity, lock)
        member = crate.get(entry["crateMember"])
        g.need(member is not None and g.digest(member) == entry["crateMemberSHA256"] and
               len(member) == entry["crateMemberSize"], "policy source member mismatch")
        header = _read(root, entry["headerPath"], entry["headerSHA256"], entry["headerSize"])
        lines = header.split(b"\n")
        g.need(header == member[:len(header)] and header.endswith(b"\n") and
               all(line.startswith(b"//") for line in lines[:-1]) and lines[-1] == b"" and
               member[len(header):len(header) + 1] == b"\n" and b"Copyright" in header,
               "policy header is not the exact leading comment block of the source member")
        header.decode("utf-8", errors="strict")
        refs.append({"path": entry["headerPath"], "sha256": entry["headerSHA256"]})
        url = (f"https://static.crates.io/crates/{identity[0]}/{identity[0]}-{identity[1]}.crate"
               f"#{identity[0]}-{identity[1]}/{entry['crateMember']}")
        g.need(entry["sourceURL"] == url, "policy header source URL mismatch")
        updated[identity] = {**component,
            "evidence": [*component["evidence"], {"path": entry["headerPath"], "sha256": entry["headerSHA256"],
                "size": entry["headerSize"], "publicPath": entry["crateMember"], "sourceURL": url, "role": HEADER_ROLE}],
            "sourceHeaderReview": {"crateMember": entry["crateMember"], "crateMemberSHA256": entry["crateMemberSHA256"],
                "headerSHA256": entry["headerSHA256"], "headerSize": entry["headerSize"],
                "derivation": "Exact leading line-comment bytes of the published crate member; not license terms; nothing added.",
                "referencedCOPYRIGHTFile": "not collected; current Rust COPYRIGHT and years are not applied to this version"}}

    # Q5: record a single human-approved OR selection.
    for entry in manifest.get("licenseSelections", []):
        identity, component, _ = target("selection", entry)
        declared = component["spdxManifestRaw"]
        g.need(entry["declaredRaw"] == declared and entry["selected"] in LICENSE_FILE_FOR and
               set(declared.split(" OR ")) == {entry["selected"], *entry["notSelected"]} and
               entry["selected"] not in entry["notSelected"], "policy OR selection mismatch")
        g.need(any(e["role"] == "license-text-candidate" and e["publicPath"].endswith(LICENSE_FILE_FOR[entry["selected"]])
                   for e in component["evidence"]), "policy selected license text not in evidence")
        updated[identity] = {**component, "issues": [*component["issues"], "OR-selection-recorded-by-approved-policy"],
            "licenseSelection": {"declaredRaw": declared, "selected": entry["selected"],
                "notSelected": sorted(entry["notSelected"]), "approvalItem": entry["approvalItem"],
                "interpretation": "Human policy selection recorded; upstream texts of all alternatives are kept; not a legal conclusion."}}
    return [updated.get(tuple(c["lockIdentity"]), c) for c in components], refs


def finish(files, report, manifest):
    """Insert the recorded selections into the public draft text and refresh derived hashes."""
    def once(data, old, new):
        g.need(data.count(old) == 1, "policy text anchor not found exactly once")
        return data.replace(old, new)
    text = files["THIRD-PARTY-NOTICES.draft.txt"]
    text = once(text, b"No OR route is inferred.\n",
                b"No OR route is inferred by the generator; the only recorded selection is the human-approved entry marked below"
                b" (policy approval 2026-11-11, not approval of this text).\n")
    if b"No license alternative is selected. " in text:
        text = once(text, b"No license alternative is selected. ",
                    b"No license alternative is selected for the standard-terms components. ")
    selections = []
    for c in report["components"]:
        if c.get("licenseSelection"):
            s = c["licenseSelection"]
            anchor = f"Component: {c['name']} {c['version']}\nSource: {c['sourceURL']}\nApplicability: unreviewed\n".encode()
            line = (f"License selection (human policy approval 2026-11-11; not a legal conclusion): {s['selected']} selected from declared "
                    f"'{s['declaredRaw']}'; {', '.join(s['notSelected'])} not selected; upstream texts kept.\n").encode()
            text = once(text, anchor, anchor + line)
            selections.append({"name": c["name"], "version": c["version"], **s})
    assert b"/Users/" not in text and b"file://" not in text
    report["draftSHA256"], report["draftSize"] = g.digest(text), len(text)
    report["approvedPolicy"] = {"approval": manifest["policyApproval"], "licenseSelections": selections,
        "commitReplacements": [c["name"] + " " + c["version"] for c in report["components"] if c.get("commitReplacementReview")],
        "sourceHeaders": [c["name"] + " " + c["version"] for c in report["components"] if c.get("sourceHeaderReview")]}
    unresolved = json.loads(files["unresolved-report.json"])
    byid = {c["identity"]: c for c in report["components"]}
    for item in unresolved["components"]:
        for field in ("licenseSelection", "commitReplacementReview", "sourceHeaderReview"):
            if field in byid[item["identity"]]:
                item[field] = byid[item["identity"]][field]
    def encode(value):
        return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return {"THIRD-PARTY-NOTICES.draft.txt": text, "internal-manifest.json": encode(report),
            "unresolved-report.json": encode(unresolved)}


def build(root, scope, standard, policy):
    components, refs = g.load_components(root)
    components, selection = g.select_input_scope(root, components, refs, scope)
    components, refs = g.attach_standard_terms(root, components, refs, standard)
    components, refs = apply_policy(root, components, refs, policy)
    files, report = g.assemble(root, components, refs, selection)
    return finish(files, report, g.read_json(root, policy)), selection, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", required=True, help="New project-relative build directory")
    parser.add_argument("--standard-license-supplement", required=True)
    parser.add_argument("--policy-supplement", required=True)
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        files, selection, report = build(root, "app-server", args.standard_license_supplement, args.policy_supplement)
        g.publish(root, args.output, files, selection)
        print(json.dumps({"output": args.output, **report["summary"],
                          "draftSHA256": g.digest(files["THIRD-PARTY-NOTICES.draft.txt"]),
                          "status": "draft-not-approved", "distributionStatus": "not-ready"}, sort_keys=True))
        return 0
    except (g.AuditError, OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        reason = str(error) if isinstance(error, g.AuditError) else type(error).__name__
        print("ERROR: policy draft generation failed: " + reason + "; no completion marker was issued.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
