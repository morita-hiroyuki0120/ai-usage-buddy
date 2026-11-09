#!/usr/bin/env python3
"""Offline draft-only notice assembler. Never executes dependency code."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tarfile
import tomllib
from urllib.parse import urlsplit, quote

RESULTS = "build/dependency-audit/codex-0.163.0/rust-toolchain-audit-1.95.0/results"
COMMIT = "83086188ae0614bd882818ff1aa23f3194962012"
REGISTRY = "registry+https://github.com/rust-lang/crates.io-index"
SPDX_COMMIT = "31ba1a50e5397e00a304dbadc76531740e89ee48"
SPDX_REPOSITORY = "https://github.com/spdx/license-list-data"
SPDX_TEXT_PINS = {
    "MIT": ("b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5", 1078),
    "Apache-2.0": ("074e6e32c86a4c0ef8b3ed25b721ca23aca83df277cd88106ef7177c354615ff", 10280),
}


class AuditError(Exception):
    pass


def need(ok, message):
    if not ok:
        raise AuditError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_file(root, relative):
    """Reject symlinks at every level, not only escapes at the final file."""
    relative = Path(relative)
    need(not relative.is_absolute() and ".." not in relative.parts,
         "absolute/traversing input path")
    current = root
    for part in relative.parts:
        current = current / part
        need(not current.is_symlink(), "symlink input is forbidden")
    need(current.resolve().is_relative_to(root), "input escapes root")
    need(stat.S_ISREG(current.stat().st_mode), "input is not a regular file")
    return current


def read_json(root, relative):
    data = safe_file(root, relative).read_bytes()
    def unique(pairs):
        result = {}
        for key, value in pairs:
            need(key not in result, "duplicate JSON key")
            result[key] = value
        return result
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique)


def public_url(value):
    need(isinstance(value, str), "missing public URL")
    u = urlsplit(value)
    need(u.scheme == "https" and u.hostname and not u.username and not u.password,
         "non-public or credential-bearing URL")
    need(not any(c in value for c in "\r\n"), "multiline URL")
    return value


def key(package):
    return (package["name"], package["version"], package["source"])


def unique_index(items, keyfn):
    result = {}
    for item in items:
        k = keyfn(item)
        need(k not in result, "ambiguous duplicate identity")
        result[k] = item
    return result


def candidate_role(path):
    name = PurePosixPath(path).name.lower()
    if PurePosixPath(name).suffix in {".rs", ".c", ".h", ".cc", ".pm", ".star", ".a"}:
        return None
    if name.startswith(("notice", "thirdpartynotice", "copyright")):
        return "notice-or-copyright-candidate"
    if re.search(r"(^|[-_])(licen[cs]e|unlicense|copying)", name) or name in {
            "mit.txt", "apache-2.0.txt"}:
        return "license-text-candidate"
    return None


def select_scope(components, closure, scope="release-union"):
    """Select exact graph IDs only AFTER the whole union's evidence was validated."""
    need(scope in {"release-union", "app-server"}, "unknown candidate scope")
    byid = unique_index(components, lambda c: c["identity"])
    union = closure["closures"]["releaseUnion"]
    need(len(set(union)) == len(union) == closure["counts"]["releaseUnionPackages"],
         "invalid union scope IDs/count")
    need(set(byid) == set(union), "components differ from original union")
    if scope == "release-union":
        return components, None  # Preserve all legacy union output bytes.
    ids = closure["closures"]["appServer"]
    need(len(set(ids)) == len(ids) == closure["counts"]["appServerPackages"] and ids,
         "invalid app-server scope IDs/count")
    need(set(ids) <= set(union), "app-server scope is not a union subset")
    need(closure["target"] == "aarch64-apple-darwin", "unexpected app-server target")
    selected = [byid[i] for i in sorted(ids)]
    roots = [c for c in selected if c["name"] == "codex-app-server"]
    need(len(roots) == 1 and roots[0]["normalization"] is not None,
         "missing/ambiguous app-server root")
    root = roots[0]
    selection = {"scope": scope, "closureKey": "appServer", "target": closure["target"],
                 "root": {k: root[k] for k in ("name", "version", "sourceURL")},
                 "selectedComponents": len(ids), "originalUnionComponents": len(union),
                 "excludedUnionComponents": len(union) - len(ids),
                 "selectedIDSetSHA256": digest(json.dumps(sorted(ids)).encode("utf-8")),
                 "interpretation": "Source-derived conservative candidates; not binary inclusion or legal compliance proof."}
    return selected, selection


def select_input_scope(root, components, input_refs, scope="release-union"):
    # Re-read only the graph bound to the load_components input hash, not a new graph.
    refs = [r for r in input_refs if r["path"].endswith(
        "/target-closure-followup/target-closure-inventory.json")]
    need(len(refs) == 1, "missing/ambiguous scope graph reference")
    ref = refs[0]
    graph = read_json(root, ref["path"])
    need(digest(safe_file(root, ref["path"]).read_bytes()) == ref["sha256"],
         "scope graph changed after evidence loading")
    selected, selection = select_scope(components, graph, scope)
    if selection is not None:
        selection["graph"] = dict(ref)
    return selected, selection


def attach_standard_terms(root, components, input_refs, relative=None):
    """Opt-in reference terms only; never upstream licensing or OR-route approval."""
    if relative is None:
        return components, input_refs
    path = Path(relative)
    folder = path.parent
    manifest = read_json(root, relative)
    need(manifest["schemaVersion"] == 1 and manifest["status"] == "draft-not-approved" and
         manifest["distributionStatus"] == "not-ready", "unsafe standard supplement status")
    need(manifest["sourceCommit"] == SPDX_COMMIT and
         manifest["sourceRepository"] == SPDX_REPOSITORY, "standard source commit/repository mismatch")
    refs = list(input_refs)
    refs.append({"path": str(path), "sha256": digest(safe_file(root, path).read_bytes())})
    resolution = manifest["commitResolution"]
    need(Path(resolution["path"]).is_relative_to(folder), "standard resolution outside collection")
    data = safe_file(root, resolution["path"]).read_bytes()
    need(digest(data) == resolution["sha256"] and len(data) == resolution["size"] and
         resolution["sourceURL"] == "https://api.github.com/repos/spdx/license-list-data/commits/main" and
         read_json(root, resolution["path"])["sha"] == SPDX_COMMIT,
         "standard commit resolution mismatch")
    refs.append({"path": resolution["path"], "sha256": resolution["sha256"]})
    texts = unique_index(manifest["files"], lambda f: f["licenseID"])
    need(set(texts) == set(SPDX_TEXT_PINS), "unsupported/missing standard license IDs")
    for id_, f in texts.items():
        member = "text/" + id_ + ".txt"
        url = f"https://raw.githubusercontent.com/spdx/license-list-data/{SPDX_COMMIT}/{member}"
        need(f["member"] == member and f["sourceURL"] == url and
             f["sourceCommit"] == SPDX_COMMIT and f["role"] == "standard-license-text",
             "standard member/URL/commit/role mismatch")
        need(Path(f["path"]).is_relative_to(folder), "standard text outside collection")
        body = safe_file(root, f["path"]).read_bytes()
        need((f["sha256"], f["size"]) == SPDX_TEXT_PINS[id_] and
             (digest(body), len(body)) == SPDX_TEXT_PINS[id_], "standard text hash/size mismatch")
        body.decode("utf-8", errors="strict")
    inventories = [r for r in input_refs if r["path"].endswith("/cargo-lock-license-inventory.json")]
    need(len(inventories) == 1, "missing/ambiguous standard lock inventory")
    inventory_ref = inventories[0]
    need(digest(safe_file(root, inventory_ref["path"]).read_bytes()) == inventory_ref["sha256"],
         "standard lock inventory changed")
    bylock = unique_index(read_json(root, inventory_ref["path"])["packages"], key)
    targets = unique_index(manifest["packages"], lambda p: (p["name"], p["version"], p["lockSource"]))
    need(bool(targets), "empty standard supplement targets")
    bycomponent = unique_index(components, lambda c: tuple(c["lockIdentity"]))
    need(set(targets) <= set(bycomponent), "standard target absent from selected scope")
    declared_ids = {"MIT": {"MIT"}, "Apache-2.0": {"Apache-2.0"},
                    "MIT OR Apache-2.0": {"MIT", "Apache-2.0"},
                    "Apache-2.0 OR MIT": {"MIT", "Apache-2.0"},
                    "Apache-2.0/MIT": {"MIT", "Apache-2.0"}}
    attached = {}
    for identity, p in targets.items():
        c, lock = bycomponent[identity], bylock.get(identity)
        need(lock is not None and identity[2] == REGISTRY and lock["category"] == "registry" and
             p["crateSHA256"] == lock["checksum"] and
             p["archivePath"] == lock["licenseEvidence"]["archive"], "standard crate identity/pin mismatch")
        archive = safe_file(root, p["archivePath"]).read_bytes()
        need(digest(archive) == p["crateSHA256"], "standard crate archive hash mismatch")
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            name = identity[0] + "-" + identity[1] + "/Cargo.toml"
            members = [m for m in tar.getmembers() if m.name == name]
            need(len(members) == 1 and members[0].isfile(), "unsafe standard crate manifest")
            meta = tomllib.loads(tar.extractfile(members[0]).read().decode("utf-8"))["package"]
        raw = p["spdxManifestRaw"]
        need((meta["name"], meta["version"], meta["license"]) == (identity[0], identity[1], raw) and
             c["spdxManifestRaw"] == raw, "standard declaration mismatch")
        ids = p["licenseIDs"]
        need(raw in declared_ids and len(ids) == len(set(ids)) and set(ids) == declared_ids[raw] and
             p["chosenLicense"] is None, "standard IDs/declaration/OR selection mismatch")
        evidence = [{**texts[id_], "publicPath": texts[id_]["member"],
                     "sourceRepository": SPDX_REPOSITORY} for id_ in sorted(ids)]
        attached[identity] = {**c, "evidence": [*c["evidence"], *evidence],
            "issues": [*c["issues"], "standard-terms-reference-only-not-upstream-grant-or-approval"],
            "standardTermsReview": {"licenseIDs": sorted(ids), "chosenLicense": None,
                "rawDeclarationPreserved": raw, "sourceCommit": SPDX_COMMIT,
                "interpretation": "Reference standard terms only; alternatives not selected or normalized; placeholders unchanged; not package copyright or upstream full text."}}
    return [attached.get(tuple(c["lockIdentity"]), c) for c in components], refs


def assemble(root, components, input_refs, scope_selection=None):
    """Validate everything before any output directory is created."""
    components = sorted(components, key=lambda c: (c["name"], c["version"], c["sourceURL"]))
    unique_index(components, lambda c: c["identity"])
    blobs, records = {}, []
    with_standard = any(c.get("standardTermsReview") for c in components)
    for component in components:
        record = dict(component)
        record["texts"] = []
        issues = list(component.get("issues", []))
        # Even an evidence-complete acquisition has unreviewed distribution duties.
        issues.append("distribution-applicability-copyright-NOTICE-review-pending")
        for evidence in component["evidence"]:
            original = safe_file(root, evidence["path"]).read_bytes()
            need(digest(original) == evidence["sha256"], "evidence SHA-256 mismatch")
            if evidence.get("size") is not None:
                need(len(original) == evidence["size"], "evidence size mismatch")
            else:
                issues.append("recorded-size-unavailable:" + evidence["publicPath"])
            public_url(evidence["sourceURL"])
            item = dict(evidence)
            item["actualSize"] = len(original)
            try:
                original.decode("utf-8", errors="strict")
            except UnicodeDecodeError:
                item["disposition"] = "invalid-UTF8-review-needed"
                issues.append("invalid-UTF8:" + evidence["publicPath"])
                record["texts"].append(item)
                continue
            payload = original
            if evidence["role"] == "source-header-not-license-terms":
                need(original.startswith(b"/*") and b"*/" in original, "missing source header")
                payload = original[:original.index(b"*/") + 2]
                item["derivation"] = "Exact leading block comment bytes; not license terms."
            if evidence["role"] is None:
                item["disposition"] = "not-recognized-as-license-or-notice-review-needed"
                issues.append("non-license-candidate:" + evidence["publicPath"])
            else:
                sha = digest(payload)
                blobs.setdefault(sha, payload)
                item["textSHA256"] = sha
                item["textSize"] = len(payload)
                item["disposition"] = "included-unreviewed"
            record["texts"].append(item)
        included = [t for t in record["texts"] if "textSHA256" in t]
        if not any(t["role"] == "license-text-candidate" for t in included):
            issues.append("no-full-license-text-candidate")
        if with_standard:
            record["licenseEvidenceAvailability"] = {
                "upstreamFullTextAvailable": any(t["role"] == "license-text-candidate" for t in included),
                "standardTermsAvailable": any(t["role"] == "standard-license-text" for t in included),
                "attributionReview": "pending", "scopeReview": "pending"}
        record.pop("evidence")
        record["issues"] = sorted(set(issues))
        records.append(record)
    # Public draft contains no local IDs/paths, manifest authors, or chosen OR route.
    parts = [b"THIRD-PARTY NOTICES\ndraft-not-approved\ndistributionStatus: not-ready\n"
             b"Source-derived conservative candidate set; not binary inclusion or legal compliance proof.\n"
             b"All applicability, copyright and NOTICE duties require review. No OR route is inferred.\n\n"]
    if with_standard:
        parts.append(b"Standard-license-text: SPDX reference terms, NOT text obtained from the component upstream.\n"
                     b"Holder/year placeholders are unchanged reference placeholders, NOT actual package attribution.\n"
                     b"No license alternative is selected. Upstream full-text gaps, SDK caveats and version-scope reviews remain open.\n\n")
    if scope_selection is not None:
        need(scope_selection["scope"] == "app-server" and
             scope_selection["selectedComponents"] == len(records) and
             scope_selection["selectedIDSetSHA256"] == digest(json.dumps(
                 sorted(c["identity"] for c in records)).encode("utf-8")),
             "scope selection does not match assembled components")
        r = scope_selection["root"]
        parts.append((f"Scope: app-server\nRoot: {r['name']} {r['version']}\n"
                      f"Candidates: {len(records)} source-derived conservative candidates; "
                      "not binary inclusion proof.\n\n").encode("utf-8"))
    for c in records:
        header = f"Component: {c['name']} {c['version']}\nSource: {c['sourceURL']}\n"
        header += "Applicability: unreviewed\n"
        if c.get("standardTermsReview"):
            header += (f"Declared license (raw): {c['spdxManifestRaw']}\n"
                       "Standard terms: reference only; not upstream full text or copyright; OR not selected.\n")
        for t in c["texts"]:
            if "textSHA256" in t:
                header += f"Text: {t['textSHA256']} | {t['role']} | {t['sourceURL']}\n"
        if "no-full-license-text-candidate" in c["issues"]:
            header += "Full license text candidate: missing\n"
        parts.append((header + "\n").encode("utf-8"))
    for sha, body in sorted(blobs.items()):
        parts.append(f"===== TEXT SHA256 {sha} | {len(body)} bytes =====\n".encode())
        parts.append(body)  # Exact original/explicitly bounded header bytes, no newline normalization.
        parts.append(b"\n===== END TEXT =====\n\n")
    draft = b"".join(parts)
    need(b"/Users/" not in draft and b"file://" not in draft, "local path in public draft")
    report = {"schemaVersion": 1, "status": "draft-not-approved",
              "distributionStatus": "not-ready", "components": records,
              "inputs": input_refs,
              "summary": {"components": len(records), "uniqueTexts": len(blobs),
                          "unresolvedComponents": len(records),
                          "withoutFullLicenseCandidate": sum(
                              "no-full-license-text-candidate" in c["issues"] for c in records),
                          "noticeOrCopyrightReferences": sum(
                              t["role"] == "notice-or-copyright-candidate" and "textSHA256" in t
                              for c in records for t in c["texts"])},
              "draftSHA256": digest(draft), "draftSize": len(draft),
              "scope": "Normalized release two-binary union candidate, not proven binary contents."}
    unresolved = {"status": "draft-not-approved", "distributionStatus": "not-ready",
                  "components": [{"identity": c["identity"], "name": c["name"],
                                  "version": c["version"], "sourceURL": c["sourceURL"],
                                  "issues": c["issues"]} for c in records]}
    if scope_selection is not None:
        report["scope"] = scope_selection["interpretation"]
        report["scopeSelection"] = scope_selection
        unresolved["scopeSelection"] = scope_selection
    if with_standard:
        report["summary"]["standardTermsComponents"] = sum(
            c["licenseEvidenceAvailability"]["standardTermsAvailable"] for c in records)
        report["summary"]["standardTermsReferences"] = sum(
            t["role"] == "standard-license-text" and "textSHA256" in t for c in records for t in c["texts"])
        for c, item in zip(records, unresolved["components"]):
            item["licenseEvidenceAvailability"] = c["licenseEvidenceAvailability"]
            if "standardTermsReview" in c:
                item["standardTermsReview"] = c["standardTermsReview"]
    def encode(value):
        return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return {"THIRD-PARTY-NOTICES.draft.txt": draft,
            "internal-manifest.json": encode(report),
            "unresolved-report.json": encode(unresolved)}, report



def supplement_evidence(root, base, manifest, bylock):
    """Validate source-qualified supplement and archive provenance before importing."""
    need(manifest["status"] == "draft-not-approved" and
         manifest["distributionStatus"] == "not-ready", "unsafe supplement status")
    result = {}
    folder = base / "license-supplement-20261023-2"
    for package in manifest["packages"]:
        identity = (package["name"], package["version"], package["lockSource"])
        need(identity not in result and identity in bylock, "supplement identity mismatch")
        lock = bylock[identity]
        need(lock["category"] == "registry" and identity[2] == REGISTRY and
             package["crateSHA256"] == lock["checksum"], "supplement crate pin mismatch")
        need(package["archivePath"] == lock["licenseEvidence"]["archive"],
             "supplement archive reference mismatch")
        archive = safe_file(root, package["archivePath"]).read_bytes()
        need(digest(archive) == package["crateSHA256"], "supplement archive hash mismatch")
        commit = package["commit"]
        need(re.fullmatch("[0-9a-f]{40}", commit), "invalid supplement revision")
        repo = public_url(package["repository"])
        need(urlsplit(repo).hostname == "github.com", "unsupported supplement repository")
        scope = PurePosixPath(package["pathInVcs"])
        need(not scope.is_absolute() and ".." not in scope.parts, "invalid VCS package path")
        prefix = identity[0] + "-" + identity[1] + "/"
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            def member_bytes(name):
                matches = [m for m in tar.getmembers() if m.name == name]
                need(len(matches) == 1 and matches[0].isfile(), "unsafe/ambiguous crate member")
                return tar.extractfile(matches[0]).read()
            vcs = json.loads(member_bytes(prefix + ".cargo_vcs_info.json").decode("utf-8"))
            meta = tomllib.loads(member_bytes(prefix + "Cargo.toml").decode("utf-8"))["package"]
            need((vcs["git"]["sha1"], vcs["path_in_vcs"]) ==
                 (commit, str(scope)), "supplement VCS provenance mismatch")
            need((meta["name"], meta["version"], meta["repository"], meta["license"]) ==
                 (identity[0], identity[1], repo, package["spdxManifestRaw"]),
                 "supplement crate manifest mismatch")
            files = unique_index(package["files"], lambda f: f["localPath"])
            for path, f in files.items():
                need(Path(path).is_relative_to(folder), "supplement path outside collection")
                body = safe_file(root, path).read_bytes()
                need(digest(body) == f["sha256"] and len(body) == f["size"],
                     "supplement file hash/size mismatch")
                need(hashlib.sha1(b"blob " + str(len(body)).encode() + b"\0" + body).hexdigest()
                     == f["gitBlobSHA1"], "supplement Git blob mismatch")
                body.decode("utf-8", errors="strict")
                public_url(f["sourceURL"])
                if "archiveMember" in f:
                    member = f["archiveMember"]
                    need(member.startswith(prefix) and ".." not in PurePosixPath(member).parts,
                         "supplement archive member identity mismatch")
                    need(body == member_bytes(member), "supplement archive member bytes mismatch")
                    expected = (f"https://static.crates.io/crates/{identity[0]}/"
                                f"{identity[0]}-{identity[1]}.crate#{member}")
                else:
                    expected = f"https://raw.githubusercontent.com{urlsplit(repo).path}/{commit}/{f['sourcePath']}"
                need(f["sourceURL"] == expected, "supplement public source mismatch")
                if "fixedSourceURL" in f:
                    need(f["fixedSourceURL"] ==
                         f"https://raw.githubusercontent.com{urlsplit(repo).path}/{commit}/{f['sourcePath']}",
                         "supplement fixed source mismatch")
        full, attribution = package["fullLicensePaths"], package["attributionPaths"]
        need(len(set(full)) == len(full) and len(set(attribution)) == len(attribution) and
             not set(full).intersection(attribution) and
             set(full + attribution).issubset(files), "supplement role path mismatch")
        need(package["status"] in {"evidence-complete-for-review", "explicit-missing"} and
             package["distributionStatus"] == "not-ready", "invalid package review status")
        evidence = []
        for path, f in files.items():
            role = None
            if path in full:
                need(f["role"] == "full-license-text" and f.get("gitBlobVerified") is True,
                     "non-license supplement promoted to full terms")
                role = "license-text-candidate"
            elif path in attribution:
                need(f["role"] == "source-header-not-license-terms" and
                     f.get("gitBlobVerified") is True, "unverified supplement attribution")
                role = f["role"]
            elif f["role"] == "scope-and-SDK-license-caveat-not-full-license":
                role = f["role"]  # Preserve actual caveat text without calling it MIT terms.
            if role:
                evidence.append({"path": path, "sha256": f["sha256"], "size": f["size"],
                                 "publicPath": f["sourcePath"],
                                 "sourceURL": f.get("fixedSourceURL", f["sourceURL"]), "role": role})
        result[identity] = {"evidence": evidence, "review": {
            k: package[k] for k in ("status", "commit", "pathInVcs", "NOTICEscope",
                                    "pathScope", "explicitMissing", "crateSHA256")}}
    # Every declared supplement must attach to a target component later; none silently dropped.
    return result


def historical_supplement_evidence(root, base, manifest, receipt, bylock):
    """Schema-2 snapshot adapter, deliberately separate from strict crate-VCS -2."""
    from datetime import datetime
    from urllib.parse import parse_qs
    folder = base / "license-supplement-20261023-3"
    need(manifest["schemaVersion"] == 2 and manifest["status"] == "draft-not-approved" and
         manifest["distributionStatus"] == "not-ready", "invalid historical supplement schema/status")
    need(digest(safe_file(root, folder / "manifest.json").read_bytes()) ==
         receipt["manifestSHA256ReportedByParent"], "historical receipt manifest hash mismatch")
    all_files, bodies, ref_count = {}, {}, 0

    def checked(f):
        path = f["localPath"]
        need(Path(path).is_relative_to(folder), "historical file outside collection")
        if path in all_files:
            need(all_files[path] == f, "inconsistent duplicate historical reference")
            return bodies[path]
        b = safe_file(root, path).read_bytes()
        need(type(f["size"]) is int and len(b) == f["size"] and digest(b) == f["sha256"],
             "historical file hash/size mismatch")
        need(hashlib.sha1(b"blob " + str(len(b)).encode() + b"\0" + b).hexdigest() ==
             f["gitBlobSHA1"], "historical Git blob mismatch")
        b.decode("utf-8", errors="strict")
        all_files[path], bodies[path] = f, b
        return b

    def archive_files(b):
        need(len(b) <= 50_000_000, "historical archive exceeds bound")
        files, seen, roots, total = {}, set(), set(), 0
        with tarfile.open(fileobj=io.BytesIO(b)) as tar:
            for member in tar.getmembers():
                path = PurePosixPath(member.name)
                need(not path.is_absolute() and ".." not in path.parts and path.parts,
                     "unsafe historical archive path")
                need(member.name not in seen, "duplicate historical archive entry")
                seen.add(member.name)
                roots.add(path.parts[0])
                total += member.size
                need(total <= 400_000_000 and len(seen) <= 200_000, "expanded archive exceeds bound")
                if not member.isfile():
                    continue  # Never follow/extract links or devices.
                need(len(path.parts) >= 2, "historical archive has unrooted member")
                relative = "/".join(path.parts[1:])
                files[relative] = tar.extractfile(member).read()
        need(len(roots) == 1, "historical archive has multiple roots")
        return files

    def github_repo(url):
        parsed = urlsplit(public_url(url))
        need(parsed.hostname == "github.com" and not parsed.query and not parsed.fragment,
             "invalid historical repository URL")
        need(len(parsed.path.strip("/").split("/")) == 2, "invalid historical repository path")
        return parsed.path.strip("/")

    def raw_source(f, repo, commit, snapshot=None):
        url = public_url(f["sourceURL"])
        path = f["sourcePath"]
        need(not PurePosixPath(path).is_absolute() and ".." not in PurePosixPath(path).parts,
             "unsafe historical source path")
        need(url == f"https://raw.githubusercontent.com/{repo}/{commit}/{path}",
             "historical fixed source URL mismatch")
        if "sourceCommit" in f:
            need(f["sourceCommit"] == commit, "historical file revision mismatch")
        b = checked(f)
        if snapshot is not None:
            need(path in snapshot and snapshot[path] == b, "historical snapshot member mismatch")
        return b

    # Validate every repeated reference, including metadata, without conflating counts.
    package_paths = set()
    for p in manifest["packages"]:
        unique_index(p["files"], lambda f: f["localPath"])
        for f in p["files"]:
            ref_count += 1
            package_paths.add(f["localPath"])
            checked(f)
        checked(p["sourceComparison"])
    for f in manifest["reuseVerification"]:
        checked(f)
    counts = receipt["countClarification"]
    need((ref_count, len(package_paths), len(all_files)) ==
         (counts["packagesFilesReferences"], counts["packagesFilesUniquePaths"],
          counts["combinedUniqueFileCount"]), "historical corrected reference counts mismatch")
    need(len(all_files) == manifest["summary"]["filesToVerify"], "historical combined count mismatch")

    snapshots, release_versions, commit_queries = {}, [], []
    requests = manifest["publicHTTPRequests"]
    unique_index(requests, lambda r: r["request"])
    unique_index(requests, lambda r: r["file"])
    need(len(requests) <= manifest["requestLimit"] <= 16, "historical request count invalid")
    for request in requests:
        filename = Path(request["file"])
        need(len(filename.parts) == 1 and not filename.is_absolute(), "unsafe response filename")
        b = safe_file(root, folder / "downloads" / filename).read_bytes()
        need(digest(b) == request["sha256"] and len(b) == request["size"],
             "historical downloaded response hash/size mismatch")
        url = urlsplit(public_url(request["url"]))
        if url.hostname == "codeload.github.com":
            match = re.fullmatch(r"/([^/]+/[^/]+)/tar.gz/([0-9a-f]{40})", url.path)
            need(match is not None and not url.query, "snapshot URL is not fixed")
            identity = match.groups()
            need(identity not in snapshots, "duplicate historical snapshot")
            snapshots[identity] = archive_files(b)
        elif url.hostname == "crates.io":
            match = re.fullmatch(r"/api/v1/crates/([^/]+)/([^/]+)", url.path)
            need(match is not None, "unexpected version API URL")
            data = json.loads(b.decode("utf-8"))["version"]
            identity = (match[1], match[2], REGISTRY)
            need(identity in bylock and (data["crate"], data["num"]) == identity[:2] and
                 data["checksum"] == bylock[identity]["checksum"], "historical version API identity mismatch")
            github_repo(data["repository"])
            release_versions.append(data)
        elif url.hostname == "api.github.com":
            match = re.fullmatch(r"/repos/([^/]+/[^/]+)/commits", url.path)
            query = parse_qs(url.query)
            data = json.loads(b.decode("utf-8"))
            need(match is not None and len(data) == 1 and query.get("per_page") == ["1"] and
                 len(query.get("until", [])) == 1, "unexpected historical commit query")
            commit, repo = data[0]["sha"], match[1]
            need(re.fullmatch("[0-9a-f]{40}", commit) and data[0]["html_url"] ==
                 f"https://github.com/{repo}/commit/{commit}", "commit API repository/revision mismatch")
            date = datetime.fromisoformat(data[0]["commit"]["committer"]["date"].replace("Z", "+00:00"))
            until = datetime.fromisoformat(query["until"][0].replace("Z", "+00:00"))
            need(date <= until, "historical snapshot newer than selection cutoff")
            commit_queries.append((repo, commit, until))
        else:
            raise AuditError("unsupported historical response origin")
    for repo, commit, until in commit_queries:
        need((repo, commit) in snapshots and any(
            github_repo(v["repository"]) == repo and until <=
            datetime.fromisoformat(v["created_at"].replace("Z", "+00:00"))
            for v in release_versions), "historical cutoff has no matching published-version evidence")

    for f in manifest["reuseVerification"]:
        url = urlsplit(f["sourceURL"])
        match = re.fullmatch(r"/([^/]+/[^/]+)/([0-9a-f]{40})/(.+)", url.path)
        need(url.hostname == "raw.githubusercontent.com" and match is not None,
             "invalid reused historical source URL")
        repo, commit, _ = match.groups()
        need((repo, commit) in snapshots, "reused source lacks fixed snapshot")
        raw_source(f, repo, commit, snapshots[(repo, commit)])
        need(safe_file(root, f["reusedFrom"]).read_bytes() == checked(f),
             "historical reuse bytes mismatch")

    result = {}
    for p in manifest["packages"]:
        identity = (p["name"], p["version"], p["lockSource"])
        need(identity not in result and identity in bylock, "historical package identity mismatch")
        lock = bylock[identity]
        need(lock["category"] == "registry" and identity[2] == REGISTRY and
             p["crateSHA256"] == lock["checksum"] and
             p["archivePath"] == lock["licenseEvidence"]["archive"], "historical package pin mismatch")
        b = safe_file(root, p["archivePath"]).read_bytes()
        need(digest(b) == p["crateSHA256"], "historical original crate hash mismatch")
        crate = archive_files(b)
        meta = tomllib.loads(crate["Cargo.toml"].decode())["package"]
        need((meta["name"], meta["version"], meta["repository"], meta["license"]) ==
             (p["name"], p["version"], p["repository"], p["spdxManifestRaw"]),
             "historical normalized crate identity mismatch")
        vcs = json.loads(crate[".cargo_vcs_info.json"]) if ".cargo_vcs_info.json" in crate else None
        need(vcs == p["crateVCSInfo"], "historical crate VCS record mismatch")
        repo = github_repo(p["sourceSnapshotRepository"])
        commit, directory = p["commit"], p["pathInVcs"]
        need(re.fullmatch("[0-9a-f]{40}", commit) and isinstance(directory, str) and
             not PurePosixPath(directory).is_absolute() and ".." not in PurePosixPath(directory).parts,
             "invalid historical package source location")
        snapshot = snapshots.get((repo, commit))
        if vcs:
            need(vcs["git"]["sha1"] == commit and vcs.get("path_in_vcs", "") == directory and
                 repo == github_repo(p["repository"]), "historical crate VCS binding mismatch")
        else:
            need(snapshot is not None and (repo, commit) in {(r, c) for r, c, _ in commit_queries},
                 "historical package lacks snapshot provenance")
        files = unique_index(p["files"], lambda f: f["localPath"])
        prefix = p["name"] + "-" + p["version"] + "/"
        for f in p["files"]:
            body = checked(f)
            if "archiveMember" in f:
                member = f["archiveMember"]
                need(member.startswith(prefix), "historical archive-member identity mismatch")
                suffix = member[len(prefix):]
                need(suffix in crate and crate[suffix] == body and f["sourceURL"] ==
                     f"https://static.crates.io/crates/{p['name']}/{p['name']}-{p['version']}.crate#{member}",
                     "historical crate-member bytes/URL mismatch")
            else:
                raw_source(f, repo, commit, snapshot)
                if snapshot is None:
                    need("reusedFrom" in f and safe_file(root, f["reusedFrom"]).read_bytes() == body,
                         "historical prior-source reuse mismatch")

        comparisons = json.loads(checked(p["sourceComparison"]))
        bymember = unique_index(comparisons, lambda c: c["crateMember"])
        manifest_path = (directory + "/" if directory else "") + "Cargo.toml"
        if snapshot is not None:
            need(manifest_path in snapshot, "historical snapshot package manifest missing")
            smeta = tomllib.loads(snapshot[manifest_path].decode())["package"]
            need(smeta["name"] == p["name"] and smeta["version"] ==
                 p["sourceSnapshotManifestVersion"], "historical snapshot manifest identity mismatch")
            expected = {prefix + k for k in crate if k.endswith(".rs") or k == "Cargo.toml.orig"}
            need(set(bymember) == expected, "historical source comparison coverage mismatch")
            for member, row in bymember.items():
                suffix = member[len(prefix):]
                path = (directory + "/" if directory else "") + (
                    "Cargo.toml" if suffix == "Cargo.toml.orig" else suffix)
                need(row["sourcePath"] == path and path in snapshot, "historical comparison path mismatch")
                original, upstream = crate[suffix], snapshot[path]
                need(row["crateSHA256"] == digest(original) and row["upstreamSHA256"] == digest(upstream) and
                     row["byteIdentical"] is (original == upstream) and row["gitBlobSHA1"] ==
                     hashlib.sha1(b"blob "+str(len(upstream)).encode()+b"\0"+upstream).hexdigest(),
                     "historical source comparison bytes/hash mismatch")
                if suffix.endswith(".rs"):
                    need(original == upstream, "historical Rust source differs")
            # Confirm inherited licensing scope, without picking an OR branch.
            snapshot_license = smeta.get("license")
            if isinstance(snapshot_license, dict):
                need(snapshot_license == {"workspace": True}, "unknown snapshot license inheritance")
                snapshot_license = tomllib.loads(snapshot["Cargo.toml"].decode())["workspace"]["package"]["license"]
            need(isinstance(snapshot_license, str) and snapshot_license, "snapshot licensing scope absent")
        else:
            need(not comparisons and p["status"] == "explicit-missing" and
                 not p["fullLicensePaths"], "unbacked historical license/source comparison")

        full, headers, notices, candidates = (
            p[k] for k in ("fullLicensePaths", "attributionPaths", "NOTICEpaths",
                          "upstreamFullLicenseCandidatePaths"))
        for paths in (full, headers, notices, candidates):
            need(len(paths) == len(set(paths)) and set(paths).issubset(files),
                 "historical selected evidence paths invalid")
        need(set(full).issubset(candidates) and not set(headers).intersection(candidates + notices),
             "historical evidence roles overlap")
        expected_headers = {path for path, f in files.items() if "archiveMember" in f and
            checked(f).startswith(b"/*") and b"Copyright" in checked(f)[:1000]}
        need(set(headers) == expected_headers, "historical source attribution dropped")
        need(set(notices) == {path for path, f in files.items() if f["role"] == "actual-upstream-NOTICE"},
             "historical NOTICE reference dropped")
        need(sorted(files[path]["sourcePath"] for path in notices) ==
             sorted(p["NOTICEscope"]["collected"]), "historical NOTICE scope differs")
        complete = p["status"] == "evidence-complete-for-review"
        need(p["distributionStatus"] == "not-ready" and
             p["status"] in {"evidence-complete-for-review", "explicit-missing"},
             "invalid historical review status")
        if complete:
            need(snapshot is not None and smeta["version"] == p["version"] and full,
                 "historical version mismatch promoted to complete")
            need(set(full) == set(candidates), "historical license alternatives dropped")
        if snapshot is not None:
            ancestors = {""}
            ancestor = PurePosixPath(directory)
            while str(ancestor) not in {"", "."}:
                ancestors.add(str(ancestor))
                ancestor = ancestor.parent
            expected_notices = {path for path in snapshot
                if ("" if str(PurePosixPath(path).parent) == "." else str(PurePosixPath(path).parent))
                in ancestors and PurePosixPath(path).name.upper().startswith("NOTICE")}
            need(expected_notices.issubset({files[path]["sourcePath"] for path in notices}),
                 "historical ancestor NOTICE omitted")
            for path in candidates:
                f = files[path]
                parent = str(PurePosixPath(f["sourcePath"]).parent)
                parent = "" if parent == "." else parent
                need(parent in ancestors and f["role"] == "full-license-text" and
                     candidate_role(f["sourcePath"]) == "license-text-candidate",
                     "historical candidate is not an ancestor license")
        evidence = []
        for path in dict.fromkeys(full + notices + headers):
            f = files[path]
            if path in full:
                need(f["role"] == "full-license-text", "historical non-license promoted to terms")
                role = "license-text-candidate"
            elif path in notices:
                need(f["role"] == "actual-upstream-NOTICE", "historical non-NOTICE promoted")
                role = "notice-or-copyright-candidate"
            else:
                need(f["role"] == "source-header-not-license-terms" and "archiveMember" in f,
                     "historical attribution not from original source")
                role = f["role"]
            evidence.append({"path": path, "sha256": f["sha256"], "size": f["size"],
                             "publicPath": f["sourcePath"], "sourceURL": f["sourceURL"], "role": role})
        result[identity] = {"evidence": evidence, "review": {
            k: p[k] for k in ("status", "commit", "pathInVcs", "sourceSnapshotRepository",
                              "sourceSnapshotManifestVersion", "commitBinding", "NOTICEscope",
                              "pathScope", "explicitMissing", "spdxManifestRaw", "reviewPending",
                              "upstreamFullLicenseCandidatePaths")}}
    audit = {"packageFileReferences": ref_count, "packageFileUniquePaths": len(package_paths),
             "combinedUniqueFiles": len(all_files), "downloadedResponses": len(requests)}
    for item in result.values():
        item["review"]["validationCounts"] = audit
    return result

def load_components(root, results=RESULTS,
                    supplement_relative="license-supplement-20261023-2/manifest.json",
                    historical_relative="license-supplement-20261023-3/manifest.json"):
    base = Path(results)
    refs = []
    def load(rel):
        path = str(base / rel)
        value = read_json(root, path)
        refs.append({"path": path, "sha256": digest(safe_file(root, path).read_bytes())})
        return value
    inventory = load("cargo-lock-license-inventory.json")
    metadata = load("target-closure-followup/metadata-aarch64.json")
    closure = load("target-closure-followup/target-closure-inventory.json")
    ledger = load("target-closure-followup/license-obligations-ledger-20261023.json")
    missing = load("missing-license-followup-20261022/missing-license-inventory.json")
    followup = load("license-text-followup-20261023/license-text-inventory.json")
    shared = load("path-package-shared-license-evidence.json")
    need(inventory["audit"]["commit"] == shared["sourceCommit"] == COMMIT,
         "fixed source commit mismatch")
    diff = inventory["audit"]["boundedLockDiff"]
    need(diff["pathVersionChanges"] == 160 and
         diff["registryVersionSourceChecksumChanges"] == diff["gitVersionRevisionChanges"] == 0,
         "normalization is not limited to 160 internal versions")
    bylock = unique_index(inventory["packages"], key)
    supplements = (supplement_evidence(root, base, load(supplement_relative), bylock)
                   if supplement_relative is not None else {})
    attached_supplements = set()
    historical = (historical_supplement_evidence(
        root, base, load(historical_relative),
        load("license-supplement-20261023-3/parent-verification-20261023.json"), bylock)
        if historical_relative is not None else {})
    attached_historical = set()
    byid = unique_index(metadata["packages"], lambda p: p["id"])
    ids = closure["closures"]["releaseUnion"]
    need(len(set(ids)) == len(ids) == closure["counts"]["releaseUnionPackages"],
         "duplicate/dropped closure IDs")
    bymissing = unique_index(missing["packages"],
                             lambda p: (p["name"], p["version"], p["lockSource"]))
    byledger = unique_index(ledger["packages"], key)
    byfollow = unique_index(followup["packages"], lambda p: (p["name"], p["version"]))
    pathmap = unique_index(shared["packages"], lambda p: (p["name"], p["manifestVersion"],
                                                         p["manifest"]))
    components = []
    for id_ in sorted(ids):
        need(id_ in byid, "closure ID absent from metadata")
        p = byid[id_]
        name, version, source = p["name"], p["version"], p["source"]
        issues, evidence = [], []
        def add(f, url, role=None, prefix=None, role_auto=True):
            path = f.get("collectedPath", f.get("localPath"))
            need(path is not None, "missing collected path")
            if prefix:
                path = str(prefix / path)
            public_path = f.get("sourcePath", f.get("archiveMember", Path(path).name))
            evidence.append({"path": path, "sha256": f["sha256"], "size": f.get("size"),
                             "publicPath": public_path, "sourceURL": public_url(url),
                             "role": candidate_role(public_path) if role_auto else role})
        if source is None:
            manifest = Path(p["manifest_path"]).relative_to(Path(metadata["workspace_root"])).as_posix()
            alias = pathmap.get((name, version, manifest))
            need(alias is not None, "missing exact normalized path mapping")
            lockkey = (name, alias["lockVersion"], "local path (Cargo.lock contains no source URL)")
            need(lockkey in bylock and bylock[lockkey]["category"] == "path",
                 "normalized path not present in original lock")
            lp = bylock[lockkey]
            candidates = lp["licenseEvidence"]["manifestCandidates"]
            need(any(c["manifest"] == manifest and c["currentManifestVersion"] == version
                     for c in candidates), "path manifest mapping mismatch")
            url = f"https://github.com/openai/codex/blob/{COMMIT}/codex-rs/{manifest}"
            for f in shared["candidates"]:
                add(f, f"https://raw.githubusercontent.com/openai/codex/{COMMIT}/{f['name']}",
                    prefix=base)
            need({f["name"] for f in shared["candidates"]} >= {"LICENSE", "NOTICE"},
                 "shared root NOTICE or LICENSE absent")
            issues.append("shared-root-applicability-unreviewed")
            normalization = {"originalLockVersion": alias["lockVersion"],
                             "normalizedManifestVersion": version, "manifest": manifest}
        else:
            lockkey = (name, version, source)
            need(lockkey in bylock, "exact external name/version/source absent from lock")
            lp = bylock[lockkey]
            normalization = None
            e = lp["licenseEvidence"]
            if source.startswith("registry+"):
                need(source == REGISTRY and lp["category"] == "registry", "unsupported registry")
                need(e["manifestPackageMatches"] and e["sha256"] == lp["checksum"] ==
                     e["lockChecksum"], "registry checksum/manifest mismatch")
                url = f"https://static.crates.io/crates/{name}/{name}-{version}.crate"
                for f in e.get("licenseTextFiles", []):
                    add(f, url + "#" + quote(f["archiveMember"], safe="/"))
                extra = bymissing.get(lockkey)
                if extra:
                    need(extra["lockChecksum"] == lp["checksum"], "upstream crate checksum mismatch")
                    for f in extra["upstreamCandidates"]:
                        need(extra["vcsInfo"]["gitSha1"] in f["sourceURL"],
                             "upstream candidate lacks exact VCS commit")
                        add(f, f["sourceURL"])
                        issues.append("upstream-candidate-applicability-unreviewed")
                selected = byfollow.get((name, version))
                if selected:
                    need(lockkey in byledger, "followup has no source-qualified ledger identity")
                    need(byledger[lockkey]["nextAcquisition"]["fixedVcsCommit"] ==
                         selected["commit"], "followup ledger revision mismatch")
                    for f in selected["files"]:
                        need((f["package"], f["version"], f["commit"]) ==
                             (name, version, selected["commit"]), "followup file identity mismatch")
                        if f["sourcePath"] in selected["fullLicensePaths"]:
                            add(f, f["sourceURL"], "license-text-candidate", role_auto=False)
                        elif f["sourcePath"] in selected["attributionPaths"]:
                            role = ("source-header-not-license-terms"
                                    if f["sourcePath"].endswith(".rs") else
                                    "attribution-metadata-not-license-terms")
                            add(f, f["sourceURL"], role, role_auto=False)
                    issues.extend(selected["missing"])
            elif source.startswith("git+"):
                need(lp["category"] == "git", "category mismatch")
                parsed = urlsplit(source[4:])
                revision = parsed.fragment
                need(re.fullmatch("[0-9a-f]{40}", revision) and
                     e["revision"] == revision and e["source"] == source,
                     "Git revision mismatch")
                need(parsed.hostname == "github.com" and not parsed.username and not parsed.password,
                     "unsupported Git public origin")
                repo = parsed.path.rstrip("/").removesuffix(".git")
                url = f"https://github.com{repo}/tree/{revision}"
                for f in e["repoLicenseTextFiles"]:
                    add(f, f"https://raw.githubusercontent.com{repo}/{revision}/{f['sourcePath']}")
                issues.append("repository-license-scope-unreviewed")
            else:
                raise AuditError("unsupported external source")
        if lockkey in byledger:
            issues.extend(byledger[lockkey]["missing"])
        supplement = supplements.get(lockkey)
        if supplement:
            evidence.extend(supplement["evidence"])
            issues.extend(supplement["review"]["explicitMissing"])
            issues.append("supplement-scope-and-NOTICE-review-pending")
            attached_supplements.add(lockkey)
        components.append({"identity": id_, "name": name, "version": version,
                           "sourceURL": public_url(url), "lockIdentity": list(lockkey),
                           "normalization": normalization,
                           "spdxManifestRaw": p["license"], "issues": issues, "evidence": evidence})
        if supplement:
            components[-1]["supplementReview"] = supplement["review"]
        extra_history = historical.get(lockkey)
        if extra_history:
            # Keep old acquisition notes as history, not current missing-full-text claims.
            prior_missing = byledger.get(lockkey, {}).get("missing", [])
            components[-1]["issues"] = [i for i in issues if i not in prior_missing]
            components[-1]["issues"].extend(extra_history["review"]["explicitMissing"])
            components[-1]["issues"].append("historical-snapshot-scope-and-NOTICE-review-pending")
            components[-1]["evidence"].extend(extra_history["evidence"])
            components[-1]["historicalSupplementReview"] = {
                **extra_history["review"], "priorLedgerAcquisitionNotes": prior_missing}
            attached_historical.add(lockkey)
    need(len(components) == len(ids), "target component dropped")
    need(attached_supplements == set(supplements), "supplement target missing from closure")
    need(attached_historical == set(historical), "historical supplement target missing from closure")
    return components, refs


def publish(root, output, files, scope_selection=None):
    """Exclusive new directory; completion marker appears only after all writes."""
    output = Path(output)
    need(not output.is_absolute() and ".." not in output.parts, "unsafe output path")
    need(output.parts and output.parts[0] == "build", "output must be under build")
    parent = root
    for part in output.parts[:-1]:
        parent = parent / part
        need(parent.exists() and not parent.is_symlink() and parent.is_dir(),
             "output parent must already exist and not be a symlink")
    target = root / output
    need(not target.exists() and not target.is_symlink(), "output already exists")
    target.mkdir()
    for name, body in sorted(files.items()):
        with (target / name).open("xb") as handle:
            handle.write(body)
    marker = {"status": "draft-not-approved", "distributionStatus": "not-ready",
              "generationComplete": True,
              "files": {n: {"sha256": digest(b), "size": len(b)}
                        for n, b in sorted(files.items())}}
    if scope_selection is not None:
        marker["scopeSelection"] = scope_selection
    with (target / "GENERATION-COMPLETE.json").open("x", encoding="utf-8") as handle:
        json.dump(marker, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return marker


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", required=True, help="New project-relative build directory")
    parser.add_argument("--scope", choices=("release-union", "app-server"),
                        default="release-union", help="Source-derived candidate scope (not binary inclusion)")
    parser.add_argument("--standard-license-supplement", help="Explicit project-relative reference-terms manifest; opt-in only")
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        components, refs = load_components(root)
        components, selection = select_input_scope(root, components, refs, args.scope)
        components, refs = attach_standard_terms(root, components, refs, args.standard_license_supplement)
        files, report = assemble(root, components, refs, selection)
        publish(root, args.output, files, selection)
        result = {"output": args.output, **report["summary"],
                  "draftSHA256": report["draftSHA256"],
                  "status": "draft-not-approved", "distributionStatus": "not-ready"}
        if selection is not None:
            result["scopeSelection"] = selection
        print(json.dumps(result, sort_keys=True))
        return 0  # Successful draft generation, NEVER a compliance success.
    except (AuditError, OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        # Do not echo paths, content or arbitrary source-controlled error strings.
        reason = str(error) if isinstance(error, AuditError) else type(error).__name__
        print("ERROR: draft generation failed: " + reason +
              "; no new completion marker was issued.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
