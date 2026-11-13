#!/usr/bin/env python3
"""Draft-only wrapper that applies the 2026-11-11 human policy decisions (Q2, Q3, Q5, Q12-Q16).

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

sys.path.insert(0, str(Path(__file__).resolve().parent))
SCRIPT = Path(__file__).resolve().parents[2] / "scripts/generate-third-party-notices.py"
_spec = importlib.util.spec_from_file_location("notices_generator", SCRIPT)
g = importlib.util.module_from_spec(_spec)
sys.modules["notices_generator"] = g  # shared with helper_update so AuditError is one class
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


def leading_comment_region(data):
    """Maximal leading run of blank/line-comment lines, without trailing blank lines (exact bytes)."""
    kept = []
    for line in data.splitlines(keepends=True):
        if line.strip() == b"" or line.startswith(b"//"):
            kept.append(line)
        else:
            break
    while kept and kept[-1].strip() == b"":
        kept.pop()
    return b"".join(kept)


def _declared_license(manifest_bytes, workspace_bytes, name, version):
    """(package.license, package.version) with workspace inheritance resolved from the pinned workspace manifest."""
    package = tomllib.loads(manifest_bytes.decode("utf-8"))["package"]
    workspace = None
    if workspace_bytes is not None:
        workspace = tomllib.loads(workspace_bytes.decode("utf-8"))["workspace"]["package"]
    def resolve(field):
        value = package[field]
        if isinstance(value, dict):
            g.need(value == {"workspace": True} and workspace is not None, "policy manifest inherits without workspace")
            return workspace[field]
        return value
    g.need(package["name"] == name, "policy manifest package name mismatch")
    return resolve("license"), resolve("version")


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
    # Q12: replace the root-snapshot commit with the crate's publish-time commit (every published member compared).
    for entry in manifest.get("commitCorrections", []):
        identity, component, lock = target("correction", entry)
        crate = crate_files(identity, lock)
        review = component.get("historicalSupplementReview")
        g.need(review is not None and review["commit"] == entry["previousCommit"] and
               GITHUB_COMMIT.fullmatch(entry["commit"]) and entry["commit"] != entry["previousCommit"] and
               entry["repository"] == review["sourceSnapshotRepository"] and
               entry["pathInVcs"] == review["pathInVcs"] and
               component.get("commitCorrectionReview") is None, "policy correction previous/new commit mismatch")
        repo = entry["repository"].split("github.com/")[1]
        directory = entry["pathInVcs"]
        generated = {"Cargo.toml", "Cargo.lock", ".cargo_vcs_info.json"}
        expected = {m: directory + "/" + ("Cargo.toml" if m == "Cargo.toml.orig" else m)
                    for m in crate if m not in generated}
        listed = {c["crateMember"]: c["sourcePath"] for c in entry["crateMemberEquivalence"]}
        g.need(len(listed) == len(entry["crateMemberEquivalence"]) and listed == expected and "Cargo.toml.orig" in listed,
               "policy correction does not cover every published member")
        for check in entry["crateMemberEquivalence"]:
            body = _read(root, check["path"], check["sha256"], check["size"])
            g.need(crate[check["crateMember"]] == body, "policy correction crate member differs from fixed commit file")
            refs.append({"path": check["path"], "sha256": check["sha256"]})
        old_prefix = f"https://raw.githubusercontent.com/{repo}/{entry['previousCommit']}/"
        files = {f["sourcePath"]: f for f in entry["rootFiles"]}
        g.need(len(files) == len(entry["rootFiles"]) and
               {e["publicPath"] for e in component["evidence"] if e["sourceURL"].startswith(old_prefix)} == set(files),
               "policy correction root files do not match previous-commit evidence")
        evidence, changed = [], []
        for e in component["evidence"]:
            if not e["sourceURL"].startswith(old_prefix):
                evidence.append(e)
                continue
            f = files[e["publicPath"]]
            body = _read(root, f["path"], f["sha256"], f["size"])
            old = g.safe_file(root, e["path"]).read_bytes()
            g.need(e["sourceURL"] == old_prefix + e["publicPath"], "policy correction previous URL mismatch")
            if e["role"] == "license-text-candidate":
                g.need(old == body, "policy correction license text differs from previously saved text")
            else:
                g.need(e["role"] == "notice-or-copyright-candidate", "policy correction replaces an unexpected role")
                if old != body:
                    changed.append({"publicPath": e["publicPath"], "previousSHA256": g.digest(old), "sha256": f["sha256"]})
            refs.append({"path": f["path"], "sha256": f["sha256"]})
            evidence.append({**e, "path": f["path"], "sha256": f["sha256"], "size": f["size"],
                             "sourceURL": f"https://raw.githubusercontent.com/{repo}/{entry['commit']}/{e['publicPath']}"})
        updated[identity] = {**component, "evidence": evidence,
            "issues": [*component["issues"], "commit-replaced-by-approved-policy-publish-time-commit-review-pending"],
            "commitCorrectionReview": {
                "previousCommit": entry["previousCommit"], "commit": entry["commit"], "repository": entry["repository"],
                "pathInVcs": directory, "snapshotManifestVersion": entry["snapshotManifestVersion"],
                "comparedPublishedMembers": len(listed),
                "verified": "every published member except generated Cargo.toml/Cargo.lock equals the fixed-commit file byte-for-byte (Cargo.toml.orig vs Cargo.toml); license text bytes equal the previously saved bytes",
                "changedNoticeTexts": changed, "notes": entry["notes"],
                "interpretation": "Publish-time commit inferred from path history and byte comparison (the .crate has no .cargo_vcs_info.json); applicability, copyright and NOTICE review remain pending."}}

    # Q13: keep the published declaration and the repository declaration side by side; nothing is selected or rewritten.
    for entry in manifest.get("declarationRecords", []):
        identity, component, lock = target("declaration", entry)
        crate = crate_files(identity, lock)
        g.need(component["spdxManifestRaw"] == entry["declaredRaw"] != entry["repositoryDeclaredRaw"] and
               "OR" in entry["repositoryDeclaredRaw"], "policy declaration record mismatch")
        published, _ = _declared_license(crate["Cargo.toml"], None, identity[0], identity[1])
        g.need(published == entry["declaredRaw"], "policy published manifest declaration mismatch")
        orig = tomllib.loads(crate["Cargo.toml.orig"].decode("utf-8"))["package"]["license"]
        g.need(orig == {"workspace": True}, "policy original manifest does not inherit the workspace license")
        root_manifest = _read(root, entry["workspaceManifest"]["path"], entry["workspaceManifest"]["sha256"],
                              entry["workspaceManifest"]["size"])
        g.need(tomllib.loads(root_manifest.decode("utf-8"))["workspace"]["package"]["license"] ==
               entry["repositoryDeclaredRaw"], "policy repository declaration mismatch")
        refs.append({"path": entry["workspaceManifest"]["path"], "sha256": entry["workspaceManifest"]["sha256"]})
        updated[identity] = {**updated.get(identity, component),
            "declarationRecord": {"approvalItem": entry["approvalItem"], "publishedManifestDeclaration": entry["declaredRaw"],
                "repositoryWorkspaceDeclaration": entry["repositoryDeclaredRaw"],
                "repositoryManifestSHA256": entry["workspaceManifest"]["sha256"],
                "repositoryManifestCommit": entry["workspaceManifest"]["commit"],
                "interpretation": "Both declarations and both upstream texts are kept; no alternative is selected and no declaration is rewritten. Why the published declaration differs was not established."}}

    # Q14/Q15: record why the repository-level LICENSE reaches the package (placement vs. declaration).
    for entry in manifest.get("scopeResolutions", []):
        identity, component, _ = target("scope", entry)
        issues = component["issues"]
        g.need(issues.count("repository-license-scope-unreviewed") == 1 and
               component["spdxManifestRaw"] == entry["declaredRaw"], "policy scope target has no exactly-once open scope issue")
        ws = entry.get("workspaceManifest")
        ws_bytes = _read(root, ws["path"], ws["sha256"], ws["size"]) if ws else None
        m = entry["manifest"]
        declared, version = _declared_license(_read(root, m["path"], m["sha256"], m["size"]), ws_bytes, identity[0], identity[1])
        g.need(declared == entry["declaredRaw"] and version == identity[1], "policy scope manifest declaration/version mismatch")
        refs.extend({"path": x["path"], "sha256": x["sha256"]} for x in ([m, ws] if ws else [m]))
        bodies = {}
        for f in entry["licenseFiles"]:
            body = _read(root, f["path"], f["sha256"], f["size"])
            bodies[f["sourcePath"]] = body
            if f["relation"] == "displayed-evidence":
                g.need(any(e["role"] == "license-text-candidate" and e["publicPath"] == f["sourcePath"] and
                           e["sha256"] == f["sha256"] for e in component["evidence"]),
                       "policy scope license file is not the displayed evidence")
            else:
                g.need(f["relation"] == "git-symlink-target-text" and body == b"../LICENSE", "policy scope symlink text mismatch")
            refs.append({"path": f["path"], "sha256": f["sha256"]})
        g.need(any(f["relation"] == "displayed-evidence" for f in entry["licenseFiles"]), "policy scope has no displayed license")
        for needle in entry.get("mustContain", []):
            g.need(sum(needle.encode("utf-8") in b for b in bodies.values()) >= 1, "policy scope expected license wording absent")
        for c in entry.get("corroboration", []):
            archive = _read(root, c["archive"], c["archiveSHA256"], c["archiveSize"])
            g.need(_crate_members(archive).get(c["member"]) == bodies[c["equalsLicenseSourcePath"]],
                   "policy scope published crate member differs from the pinned LICENSE")
            refs.append({"path": c["archive"], "sha256": c["archiveSHA256"]})
        updated[identity] = {**updated.get(identity, component),
            "issues": [i for i in issues if i != "repository-license-scope-unreviewed"] +
                      ["scope-resolution-recorded-by-approved-policy"],
            "scopeResolution": {"approvalItem": entry["approvalItem"], "declaredRaw": entry["declaredRaw"],
                "basis": "LICENSE placement in the pinned repository matches the package manifest declaration (workspace inheritance resolved from the pinned workspace manifest where used)",
                "manifestPath": m["sourcePath"], "manifestSHA256": m["sha256"],
                "licenseFiles": [{k: f[k] for k in ("sourcePath", "sha256", "size", "relation")} for f in entry["licenseFiles"]],
                "publishedCrateCorroboration": [{k: c[k] for k in ("member", "equalsLicenseSourcePath", "archiveSHA256")}
                                                for c in entry.get("corroboration", [])],
                "recordedObservations": entry["observations"], "remainingOpen": entry["remainingOpen"],
                "interpretation": "Scope basis recorded from LICENSE placement and the declared license; not a legal conclusion. Copyright-holder completeness, applicability and NOTICE review remain pending."}}

    # Q16: exact leading comment region of a pinned git source file (third-party header kept unmodified).
    for entry in manifest.get("gitSourceHeaders", []):
        identity, component, _ = target("githeader:" + entry["sourcePath"], entry)
        parsed = identity[2]
        g.need(parsed.startswith("git+https://github.com/") and "#" in parsed, "policy git header target is not a GitHub git dependency")
        commit = parsed.split("#", 1)[1]
        repo = parsed[len("git+https://github.com/"):].split("?", 1)[0].split("#", 1)[0].removesuffix(".git")
        g.need(GITHUB_COMMIT.fullmatch(commit) and component["sourceURL"] == f"https://github.com/{repo}/tree/{commit}",
               "policy git header source mismatch")
        source = _read(root, entry["sourceFile"]["path"], entry["sourceFile"]["sha256"], entry["sourceFile"]["size"])
        header = _read(root, entry["headerPath"], entry["headerSHA256"], entry["headerSize"])
        region = leading_comment_region(source)
        g.need(header == region and source.startswith(header) and header.endswith(b"\n") and
               not header.endswith(b"\n\n") and header.startswith(b"//") and b"Copyright" in header and
               source[len(header):len(header) + 1] == b"\n" and
               source[len(header) + 1:len(header) + 2] not in (b"\n", b"") and
               not source[len(header) + 1:].startswith(b"//"),
               "policy git header is not the exact leading comment region of the pinned source file")
        header.decode("utf-8", errors="strict")
        url = f"https://raw.githubusercontent.com/{repo}/{commit}/{entry['sourcePath']}"
        g.need(entry["sourceURL"] == url, "policy git header source URL mismatch")
        refs.extend([{"path": entry["headerPath"], "sha256": entry["headerSHA256"]},
                     {"path": entry["sourceFile"]["path"], "sha256": entry["sourceFile"]["sha256"]}])
        base = updated.get(identity, component)
        updated[identity] = {**base,
            "evidence": [*base["evidence"], {"path": entry["headerPath"], "sha256": entry["headerSHA256"],
                "size": entry["headerSize"], "publicPath": entry["sourcePath"], "sourceURL": url, "role": HEADER_ROLE}],
            "gitSourceHeaderReview": {"approvalItem": entry["approvalItem"], "sourcePath": entry["sourcePath"],
                "sourceFileSHA256": entry["sourceFile"]["sha256"], "headerSHA256": entry["headerSHA256"],
                "headerSize": entry["headerSize"],
                "derivation": "Exact leading line-comment region of the pinned file (blank lines inside the region kept, trailing blank line excluded); not license terms of the component; nothing added or edited.",
                "holderYearNote": "Wording is shown as found in the file, including any typos; no holder or year is added."}}

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
        "sourceHeaders": [c["name"] + " " + c["version"] for c in report["components"] if c.get("sourceHeaderReview")],
        "commitCorrections": [c["name"] + " " + c["version"] for c in report["components"] if c.get("commitCorrectionReview")],
        "declarationRecords": [c["name"] + " " + c["version"] for c in report["components"] if c.get("declarationRecord")],
        "scopeResolutions": [c["name"] + " " + c["version"] for c in report["components"] if c.get("scopeResolution")],
        "gitSourceHeaders": [c["name"] + " " + c["version"] for c in report["components"] if c.get("gitSourceHeaderReview")]}
    extra_fields = ("commitCorrectionReview", "declarationRecord", "scopeResolution", "gitSourceHeaderReview")
    for c in report["components"]:
        if c.get("scopeResolution") and "licenseEvidenceAvailability" in c:
            c["licenseEvidenceAvailability"] = {**c["licenseEvidenceAvailability"],
                "scopeReview": "scope-resolution-recorded-by-approved-policy"}
    unresolved = json.loads(files["unresolved-report.json"])
    byid = {c["identity"]: c for c in report["components"]}
    for item in unresolved["components"]:
        for field in ("licenseSelection", "commitReplacementReview", "sourceHeaderReview", *extra_fields):
            if field in byid[item["identity"]]:
                item[field] = byid[item["identity"]][field]
        if byid[item["identity"]].get("scopeResolution") and "licenseEvidenceAvailability" in item:
            item["licenseEvidenceAvailability"] = byid[item["identity"]]["licenseEvidenceAvailability"]
    def encode(value):
        return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return {"THIRD-PARTY-NOTICES.draft.txt": text, "internal-manifest.json": encode(report),
            "unresolved-report.json": encode(unresolved)}


def build(root, scope, standard, policy, inputs="helper-0.163.0"):
    g.need(inputs in ("helper-0.163.0", "helper-0.167.2"), "unknown input set")
    if inputs == "helper-0.167.2":
        # New 0.167.2 inputs; identical lock entries reuse the verified 0.163.0 components.
        import helper_update
        components, refs = helper_update.load_components(root)
    else:
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
    parser.add_argument("--inputs", choices=("helper-0.163.0", "helper-0.167.2"), default="helper-0.163.0",
                        help="Which saved input set to read (default keeps the 0.163.0 behaviour)")
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        files, selection, report = build(root, "app-server", args.standard_license_supplement, args.policy_supplement, args.inputs)
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
