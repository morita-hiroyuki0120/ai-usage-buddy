#!/usr/bin/env python3
"""Draft-only input preparation and component loading for the Codex helper 0.167.2 update.

`prepare` turns saved, hash-checked downloads (Cargo.lock, cargo metadata, cargo tree output, registry
.crate archives, git checkouts) into the same JSON shapes that the 0.163.0 notice generator reads.
`load_components` then combines those new inputs with the unchanged, already verified 0.163.0 components.
Dependency code, build scripts and the network are never used here; only regular files are read.
Output stays draft-not-approved / not-ready.
"""
import argparse
import glob
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile
import tomllib
from urllib.parse import quote, urlsplit

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/generate-third-party-notices.py"
if "notices_generator" in sys.modules:
    g = sys.modules["notices_generator"]
else:
    _spec = importlib.util.spec_from_file_location("notices_generator", SCRIPT)
    g = importlib.util.module_from_spec(_spec)
    sys.modules["notices_generator"] = g
    _spec.loader.exec_module(g)

CODEX_COMMIT = "ce21072c90d32c40af7a55b60b2fb35c84a43a6a"
CODEX_VERSION = "0.167.2"
AUDIT = "build/dependency-audit/codex-0.167.2"
SOURCE_AUDIT = AUDIT + "/source-audit-ce21072c"
RESULTS = AUDIT + "/rust-toolchain-audit-1.95.0/results"
OLD_RESULTS = g.RESULTS
LOCAL_PATH_SOURCE = "local path (Cargo.lock contains no source URL)"
V8_SOURCE = ("git+https://github.com/seanh-oai/rusty_v8.git?rev=350c5a859a9b3c84ab8701b3ad51e3b7699b30c0"
             "#350c5a859a9b3c84ab8701b3ad51e3b7699b30c0")
V8_REPLACEMENT_NOTE = ("v8 is a [patch.crates-io] git dependency whose submodules are not needed for metadata. "
                       "The scratch workspace copy points it at a path extract of the same commit; "
                       "the lock source and package id are restored to the git form.")
GITHUB_COMMIT = re.compile("[0-9a-f]{40}")
GENERATED_BY_CARGO = {"Cargo.toml", "Cargo.lock", ".cargo_vcs_info.json"}


def sha256_file(root, relative):
    return g.digest(g.safe_file(root, relative).read_bytes())


def dump(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def write_new(root, relative, data):
    target = root / relative
    g.need(not target.is_symlink(), "refusing to write through a symlink")
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as handle:
        handle.write(data)


def parse_tree_ids(text, packages):
    """Map `cargo tree --prefix depth --format {p}` lines to metadata package ids; every line must map uniquely."""
    byname = {}
    for p in packages:
        byname.setdefault((p["name"], p["version"]), []).append(p)
    found = set()
    for line in text.splitlines():
        if not line.strip():
            continue
        m = re.fullmatch(r"(\d+)(\S+) v(\S+)((?: \([^)]*\))*)", line)
        g.need(m is not None, "unparseable cargo tree line")
        _, name, version, tail = m.groups()
        shown = [s for s in re.findall(r"\(([^)]*)\)", tail) if s not in ("*", "proc-macro")]
        candidates = byname.get((name, version), [])
        g.need(candidates, "tree package absent from metadata")
        if len(candidates) > 1:
            def matches(p):
                if not shown:
                    return bool(p["source"]) and p["source"].startswith("registry+")
                if p["source"] is None:
                    return shown[0] in p["id"]
                return shown[0].split("#")[0].split("?")[0] in p["source"]
            candidates = [p for p in candidates if matches(p)]
            g.need(len(candidates) == 1, "ambiguous cargo tree line")
        found.add(candidates[0]["id"])
    return found


def reachable_ids(metadata, roots):
    """Reachability over normal and build edges only (target filter applied by cargo metadata already)."""
    nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
    seen, stack = set(), list(roots)
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        for dep in nodes[current]["deps"]:
            kinds = dep.get("dep_kinds") or [{"kind": None}]
            if any(k["kind"] in (None, "build") for k in kinds):
                stack.append(dep["pkg"])
    return seen


def archive_members(data):
    """Regular members of a .crate keyed by path below the root directory; links are never followed."""
    files, roots = {}, set()
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            g.need(not path.is_absolute() and ".." not in path.parts and path.parts, "unsafe crate member path")
            roots.add(path.parts[0])
            if not member.isfile():
                continue
            g.need(len(path.parts) >= 2, "crate member without root directory")
            relative = "/".join(path.parts[1:])
            g.need(relative not in files, "duplicate crate member")
            files[relative] = tar.extractfile(member).read()
    g.need(len(roots) == 1, "crate has multiple roots")
    return files, roots.pop()


def walk_license_files(base):
    """Regular, non-symlink license/notice-named files below a checkout (no .git); returns relative paths."""
    result = []
    for path in sorted(base.rglob("*")):
        relative = path.relative_to(base)
        if ".git" in relative.parts or path.is_symlink() or not path.is_file():
            continue
        if g.candidate_role(relative.as_posix()) is not None:
            result.append(relative.as_posix())
    return result


def prepare(root, upstream_candidates=None):
    """Create the new-shape input files under RESULTS. Every output path must not exist yet."""
    results = Path(RESULTS)
    followup = results / "target-closure-followup"
    original_lock_bytes = g.safe_file(root, SOURCE_AUDIT + "/Cargo.lock").read_bytes()
    original_lock = tomllib.loads(original_lock_bytes.decode("utf-8"))["package"]
    normalized_path = AUDIT + "/rust-toolchain-audit-1.95.0/workspace-copy-for-resolution/Cargo.lock"
    normalized_lock = tomllib.loads(g.safe_file(root, normalized_path).read_text("utf-8"))["package"]
    raw_metadata_path = str(results / "metadata-aarch64.json")
    raw_metadata = g.read_json(root, raw_metadata_path)
    workspace_root = raw_metadata["workspace_root"]

    def category(p):
        source = p.get("source")
        return "path" if source is None else ("registry" if source.startswith("registry+") else "git")

    lock_external = {(p["name"], p["version"], p["source"]): p for p in original_lock if category(p) != "path"}
    norm_external = {(p["name"], p["version"], p["source"]): p for p in normalized_lock if category(p) != "path"}
    v8_key = ("v8", "152.2.0", V8_SOURCE)
    g.need(v8_key in lock_external and set(lock_external) - {v8_key} == set(norm_external) and
           all(lock_external[k] == norm_external[k] for k in norm_external),
           "normalized lock differs from the original beyond path versions and the v8 scratch override")
    lock_path = {p["name"]: p for p in original_lock if category(p) == "path"}
    norm_path = {p["name"]: p for p in normalized_lock if category(p) == "path"}
    g.need(set(lock_path) <= set(norm_path) and len(norm_path) - len(lock_path) == 1 and
           set(norm_path) - set(lock_path) == {"v8"} and
           all({k: v for k, v in lock_path[n].items() if k != "version"} ==
               {k: v for k, v in norm_path[n].items() if k != "version"} for n in lock_path),
           "path packages differ beyond their version field")
    g.need({p["version"] for p in original_lock if category(p) == "path"} == {"0.0.0"}, "unexpected original path version")

    # --- normalized metadata (v8 restored to its git identity) and closure
    packages = []
    v8_path_id = None
    for p in raw_metadata["packages"]:
        if p["name"] == "v8" and p["source"] is None:
            v8_path_id = p["id"]
            p = {**p, "id": "git+https://github.com/seanh-oai/rusty_v8.git?rev=350c5a859a9b3c84ab8701b3ad51e3b7699b30c0#v8@152.2.0",
                 "source": V8_SOURCE}
        packages.append(p)
    g.need(v8_path_id is not None, "v8 scratch override not found in metadata")
    rename = {v8_path_id: next(p["id"] for p in packages if p["name"] == "v8")}
    normalized_metadata = {"packages": packages, "workspace_root": workspace_root,
                           "workspace_members": raw_metadata["workspace_members"],
                           "normalization": {"note": V8_REPLACEMENT_NOTE, "v8PathId": v8_path_id}}
    byid = {p["id"]: p for p in packages}
    raw_by_id = {p["id"]: p for p in raw_metadata["packages"]}

    def tree(name):
        return g.safe_file(root, str(followup / name)).read_text("utf-8")

    sets = {}
    for key, name in (("appServer", "tree-app-server.txt"), ("codeModeHost", "tree-code-mode-host.txt"),
                      ("releaseUnion", "tree-release-union.txt")):
        ids = parse_tree_ids(tree(name), raw_metadata["packages"])
        sets[key] = {rename.get(i, i) for i in ids}
    g.need(sets["appServer"] <= sets["releaseUnion"] and sets["codeModeHost"] <= sets["releaseUnion"] and
           sets["releaseUnion"] == sets["appServer"] | sets["codeModeHost"], "tree sets are inconsistent")
    root_ids = {key: {p["id"] for p in packages if p["name"] == name and p["source"] is None}
                for key, name in (("appServer", "codex-app-server"), ("codeModeHost", "codex-code-mode-host"))}
    g.need(all(len(v) == 1 for v in root_ids.values()), "release root package missing or ambiguous")
    reach = {}
    for key, ids in (("appServer", root_ids["appServer"]), ("releaseUnion", root_ids["appServer"] | root_ids["codeModeHost"])):
        raw_ids = {i if i not in rename.values() else v8_path_id for i in ids}
        reach[key] = {rename.get(i, i) for i in reachable_ids(raw_metadata, raw_ids)}
    unreached = {k: sorted(sets[k] - reach[k]) for k in reach}
    g.need(not any(unreached.values()), "tree package not reachable through normal/build metadata edges")
    closure = {
        "schemaVersion": 1, "target": "aarch64-apple-darwin",
        "hostAssumption": "official aarch64-apple-darwin toolchain 1.95.0; host and target coincide",
        "method": ("Cargo tree normal/build activation sets (--locked --offline) map to metadata package ids; "
                   "reachability is re-checked over normal/build metadata edges without cfg evaluation. "
                   "Dev edges excluded. v8 scratch override restored to its git identity."),
        "caveat": ("Source-derived conservative candidate only; not binary inclusion, reproduction, or legal-compliance proof. "
                   "Two root packages approximate the official simultaneous two-bin feature union."),
        "codexCommit": CODEX_COMMIT, "codexVersion": CODEX_VERSION,
        "workspaceMetadataPackageCount": len(packages),
        "counts": {"appServerPackages": len(sets["appServer"]), "codeModeHostPackages": len(sets["codeModeHost"]),
                   "releaseUnionPackages": len(sets["releaseUnion"]), "metadataEnvelopePackages": len(packages)},
        "validation": {"appTreeIDs": len(sets["appServer"]), "appReachable": len(sets["appServer"] & reach["appServer"]),
                       "unionTreeIDs": len(sets["releaseUnion"]),
                       "unionReachable": len(sets["releaseUnion"] & reach["releaseUnion"]),
                       "appUnreached": unreached["appServer"], "unionUnreached": unreached["releaseUnion"]},
        "closures": {k: sorted(v) for k, v in sets.items()},
        "rootIds": {k: sorted(v) for k, v in root_ids.items()}}

    # --- cargo-lock-license-inventory.json
    cache_dirs = glob.glob(str(root / AUDIT / "rust-toolchain-audit-1.95.0/cargo-home/registry/cache/*/"))
    g.need(len(cache_dirs) == 1, "expected exactly one registry cache directory")
    cache_rel = Path(cache_dirs[0]).relative_to(root)
    old_inventory = g.read_json(root, OLD_RESULTS + "/cargo-lock-license-inventory.json")
    old_lock = g.unique_index(old_inventory["packages"], g.key)
    old_closure = g.read_json(root, OLD_RESULTS + "/target-closure-followup/target-closure-inventory.json")
    old_metadata = {p["id"]: p for p in g.read_json(root, OLD_RESULTS + "/target-closure-followup/metadata-aarch64.json")["packages"]}
    old_union_external = {(old_metadata[i]["name"], old_metadata[i]["version"], old_metadata[i]["source"])
                          for i in old_closure["closures"]["releaseUnion"] if old_metadata[i]["source"] is not None}
    union_external = {(byid[i]["name"], byid[i]["version"], byid[i]["source"])
                      for i in sets["releaseUnion"] if byid[i]["source"] is not None}
    union_path = [byid[i] for i in sets["releaseUnion"] if byid[i]["source"] is None]
    upstream = g.read_json(root, f"{RESULTS}/upstream-candidates-20261113/manifest.json")["candidates"]
    inventory, fresh_registry, fresh_git, git_cache = [], [], [], {}
    for key in sorted(lock_external):
        name, version, source = key
        p = lock_external[key]
        if source.startswith("registry+"):
            archive = cache_rel / f"{name}-{version}.crate"
            entry = {"name": name, "version": version, "source": source, "category": "registry", "checksum": p["checksum"]}
            if (root / archive).is_file():
                data = g.safe_file(root, archive).read_bytes()
                g.need(g.digest(data) == p["checksum"], "registry archive checksum differs from the lock")
                files, prefix = archive_members(data)
                g.need(prefix == f"{name}-{version}", "crate root directory mismatch")
                manifest = tomllib.loads(files["Cargo.toml"].decode("utf-8"))["package"]
                evidence = {"archive": str(archive), "archivePathsSafe": True,
                            "archiveSource": "isolated cargo registry cache; lock checksum verified",
                            "licenseExpression": manifest.get("license"), "licenseFile": manifest.get("license-file"),
                            "licenseFilePresent": False, "lockChecksum": p["checksum"], "sha256": p["checksum"],
                            "manifestPackageMatches": (manifest["name"], manifest["version"]) == (name, version),
                            "status": "checksum-verified", "licenseTextFiles": []}
                old = old_lock.get(key)
                if key in union_external and key in old_union_external and old is not None and old["checksum"] == p["checksum"]:
                    evidence["evidenceOrigin"] = "reused-from-0.163.0-identical-lock-entry"
                elif key in union_external:
                    evidence["evidenceOrigin"] = "collected-for-0.167.2"
                    fresh_registry.append(key)
                    vcs = json.loads(files[".cargo_vcs_info.json"]) if ".cargo_vcs_info.json" in files else None
                    for member in sorted(files):
                        if g.candidate_role(member) is None:
                            continue
                        body = files[member]
                        body.decode("utf-8", errors="strict")
                        dest = f"{RESULTS}/lockfile-license-texts/{name}-{version}/{prefix}/{member}"
                        write_new(root, dest, body)
                        evidence["licenseTextFiles"].append({"archiveMember": f"{prefix}/{member}", "collectedPath": dest,
                                                             "sha256": g.digest(body), "size": len(body)})
                    evidence["vcsInfo"] = vcs
                    evidence["repository"] = manifest.get("repository")
                    if not any(g.candidate_role(f["archiveMember"]) == "license-text-candidate" for f in evidence["licenseTextFiles"]):
                        found = [c for c in upstream if (c["name"], c["version"]) == (name, version)]
                        g.need(len(found) <= 1, "ambiguous upstream candidate record")
                        if found:
                            c = found[0]
                            body = g.safe_file(root, c["collectedPath"]).read_bytes()
                            g.need(vcs is not None and c["sourceCommit"] == vcs["git"]["sha1"] and
                                   (g.digest(body), len(body)) == (c["sha256"], c["size"]) and
                                   hashlib.sha1(b"blob " + str(len(body)).encode() + b"\0" + body).hexdigest() == c["gitBlobSHA1"],
                                   "upstream candidate does not match the crate VCS commit or its Git blob")
                            evidence["upstreamCandidates"] = [{k: c[k] for k in ("sourcePath", "sourceURL", "sha256", "size", "collectedPath", "sourceCommit")}]
                        else:
                            evidence["upstreamCandidates"] = []
                            evidence["upstreamNote"] = "no upstream text collected (union-only component outside the app-server scope)"
                else:
                    evidence["evidenceOrigin"] = "not-in-release-union-not-collected"
                entry["licenseEvidence"] = evidence
            else:
                entry["licenseEvidence"] = {"status": "archive-not-downloaded-outside-platform-filter",
                                            "evidenceOrigin": "not-in-release-union-not-collected"}
            inventory.append(entry)
        else:
            entry = {"name": name, "version": version, "source": source, "category": "git", "checksum": None}
            parsed = urlsplit(source[4:])
            revision = parsed.fragment
            evidence = {"revision": revision, "source": source, "status": "not-in-release-union-not-collected"}
            if key in union_external:
                old = old_lock.get(key)
                if old is not None and key in old_union_external:
                    evidence = {**old["licenseEvidence"], "evidenceOrigin": "reused-from-0.163.0-identical-lock-entry"}
                else:
                    fresh_git.append(key)
                    repo = parsed.path.rstrip("/").removesuffix(".git")
                    checkout = _find_checkout(root, name, revision)
                    folder = f"{repo.strip('/').replace('/', '_')}-{revision[:12]}"
                    if (repo, revision) not in git_cache:
                        files = []
                        for relative in walk_license_files(checkout):
                            body = (checkout / relative).read_bytes()
                            body.decode("utf-8", errors="strict")
                            dest = f"{RESULTS}/git-license-texts/{folder}/{relative}"
                            write_new(root, dest, body)
                            files.append({"collectedPath": dest, "sha256": g.digest(body), "size": len(body), "sourcePath": relative})
                        git_cache[(repo, revision)] = files
                    files = git_cache[(repo, revision)]
                    manifests = []
                    for cargo in sorted(checkout.rglob("Cargo.toml")):
                        rel = cargo.relative_to(checkout)
                        if ".git" in rel.parts or cargo.is_symlink():
                            continue
                        try:
                            package = tomllib.loads(cargo.read_text("utf-8")).get("package", {})
                        except tomllib.TOMLDecodeError:
                            continue
                        if package.get("name") == name:
                            manifests.append({"path": rel.as_posix(), "version": package.get("version"),
                                              "licenseExpression": package.get("license"), "licenseFile": package.get("license-file")})
                    g.need(len(manifests) == 1, "git package manifest not unique")
                    evidence = {"revision": revision, "source": source, "manifestCandidates": manifests,
                                "repoLicenseTextFiles": files, "evidenceOrigin": "collected-for-0.167.2",
                                "status": "exact-pinned-git-checkout-license-candidates-collected"}
            entry["licenseEvidence"] = evidence
            inventory.append(entry)
    # --- path packages: manifest map + shared root license evidence
    shared_dir = f"{RESULTS}/path-workspace-license-texts"
    source_root = AUDIT + "/source-audit-ce21072c/checkout/codex-" + CODEX_COMMIT
    shared_files = []
    for name in ("LICENSE", "NOTICE"):
        body = g.safe_file(root, f"{source_root}/{name}").read_bytes()
        write_new(root, f"{shared_dir}/{name}", body)
        shared_files.append({"name": name, "sourcePath": f"repository-root/{name}", "collectedPath": f"{shared_dir}/{name}",
                             "sha256": g.digest(body), "size": len(body)})
    path_inventory, shared_packages = [], []
    for p in sorted(union_path, key=lambda p: p["name"]):
        manifest = Path(p["manifest_path"]).relative_to(Path(workspace_root)).as_posix()
        g.need(p["name"] in lock_path and p["name"] != "v8", "path package absent from the original lock")
        shared_packages.append({"name": p["name"], "lockVersion": "0.0.0", "manifest": manifest, "manifestVersion": p["version"],
                                "licenseExpression": p["license"], "versionMatchesManifest": p["version"] == "0.0.0",
                                "candidateReferences": [f["collectedPath"] for f in shared_files],
                                "status": "shared-root-candidates-collected; applicability-unreviewed"})
    for name in sorted(lock_path):
        path_inventory.append({"name": name, "version": "0.0.0", "source": LOCAL_PATH_SOURCE, "category": "path", "checksum": None,
                               "licenseEvidence": {"status": "manifest-name-match-version-mismatch" if name in {p["name"] for p in union_path}
                                                   else "not-in-release-union-not-collected",
                                                   "manifestCandidates": [{"manifest": s["manifest"], "currentManifestVersion": s["manifestVersion"],
                                                                           "licenseExpression": s["licenseExpression"], "licenseFile": None,
                                                                           "lockVersionMatchesManifest": False}
                                                                          for s in shared_packages if s["name"] == name]}})
    inventory.extend(path_inventory)
    inventory_doc = {
        "audit": {"commit": CODEX_COMMIT, "version": CODEX_VERSION,
                  "originalLockSHA256": g.digest(original_lock_bytes),
                  "boundedLockDiff": {"classification": "Only path package versions were synchronized by cargo (0.0.0 to 0.167.2); "
                                      "registry checksums/versions and pinned Git sources are unchanged. The v8 scratch override is a path/git identity swap only.",
                                      "pathVersionChanges": len(lock_path), "registryVersionSourceChecksumChanges": 0,
                                      "gitVersionRevisionChanges": 0}},
        "packages": sorted(inventory, key=lambda p: (p["name"], p["version"], p["source"])),
        "summary": {"packages": len(inventory), "registry": sum(p["category"] == "registry" for p in inventory),
                    "git": sum(p["category"] == "git" for p in inventory), "path": len(path_inventory),
                    "freshRegistryCollected": len(fresh_registry), "freshGitCollected": len(fresh_git),
                    "registryArchivesPresent": sum(p["category"] == "registry" and "archive" in p["licenseEvidence"] for p in inventory)}}
    shared_doc = {"sourceCommit": CODEX_COMMIT,
                  "scope": "Local path entries of the release union; shared source-root license candidates only, not package-specific applicability or binary inclusion claims.",
                  "candidates": shared_files, "packages": shared_packages}
    outputs = {str(followup / "metadata-aarch64.json"): dump(normalized_metadata),
               str(followup / "target-closure-inventory.json"): dump(closure),
               str(results / "cargo-lock-license-inventory.json"): dump(inventory_doc),
               str(results / "path-package-shared-license-evidence.json"): dump(shared_doc)}
    for relative, data in outputs.items():
        write_new(root, relative, data)
    return {"closure": closure["counts"], "validation": closure["validation"] | {"appUnreached": 0, "unionUnreached": 0},
            "inventory": inventory_doc["summary"], "freshRegistry": [list(k[:2]) for k in fresh_registry],
            "freshGit": [list(k[:2]) for k in fresh_git]}


def _find_checkout(root, name, revision):
    """The v8 path extract, or the single cargo git checkout whose HEAD is exactly the pinned revision."""
    if name == "v8":
        path = root / AUDIT / "git-sources/v8-350c5a85/src" / f"rusty_v8-{revision}"
        g.need(path.is_dir() and not path.is_symlink(), "v8 extract missing")
        return path
    base = root / AUDIT / "rust-toolchain-audit-1.95.0/cargo-home/git/checkouts"
    found = [Path(d) for d in glob.glob(str(base / "*" / revision[:7])) if Path(d).is_dir() and not Path(d).is_symlink()]
    found = [d for d in found if _read_git_head(d) == revision]
    g.need(len(found) == 1, "exact git checkout head not found")
    return found[0]


def _read_git_head(checkout):
    """HEAD commit of a cargo checkout (.git file or directory) without running git."""
    git = checkout / ".git"
    if git.is_file():
        text = git.read_text("utf-8").strip()
        if text.startswith("gitdir:"):
            git = (checkout / text.split(":", 1)[1].strip()).resolve()
    head = (git / "HEAD").read_text("utf-8").strip()
    if head.startswith("ref:"):
        ref = git / head.split(":", 1)[1].strip()
        if ".." in ref.relative_to(git).parts or ref.is_symlink() or not ref.is_file():
            return None
        head = ref.read_text("utf-8").strip()
    return head if GITHUB_COMMIT.fullmatch(head) else None


# ----------------------------------------------------------------------------------------------
# component loading
# ----------------------------------------------------------------------------------------------

def load_components(root, results=RESULTS, upstream_relative=None):
    """Components for the 0.167.2 release union, reusing verified 0.163.0 components for identical lock entries."""
    base = Path(results)
    refs = []

    def load(rel):
        path = str(base / rel)
        value = g.read_json(root, path)
        refs.append({"path": path, "sha256": sha256_file(root, path)})
        return value

    inventory = load("cargo-lock-license-inventory.json")
    metadata = load("target-closure-followup/metadata-aarch64.json")
    closure = load("target-closure-followup/target-closure-inventory.json")
    shared = load("path-package-shared-license-evidence.json")
    g.need(inventory["audit"]["commit"] == shared["sourceCommit"] == CODEX_COMMIT == closure["codexCommit"],
           "fixed source commit mismatch")
    diff = inventory["audit"]["boundedLockDiff"]
    g.need(diff["registryVersionSourceChecksumChanges"] == diff["gitVersionRevisionChanges"] == 0,
           "unexpected lock change classification")
    old_components, old_refs = g.load_components(root)
    old_by_lock = g.unique_index(old_components, lambda c: tuple(c["lockIdentity"]))
    old_inventory_ref = [r for r in old_refs if r["path"].endswith("/cargo-lock-license-inventory.json")]
    g.need(len(old_inventory_ref) == 1, "old inventory reference missing")
    old_lock = g.unique_index(g.read_json(root, old_inventory_ref[0]["path"])["packages"], g.key)
    for r in old_refs:
        if not r["path"].endswith(("/cargo-lock-license-inventory.json", "/target-closure-inventory.json")):
            refs.append({**r, "origin": "0.163.0-input-reused"})
    bylock = g.unique_index(inventory["packages"], g.key)
    byid = g.unique_index(metadata["packages"], lambda p: p["id"])
    ids = closure["closures"]["releaseUnion"]
    g.need(len(set(ids)) == len(ids) == closure["counts"]["releaseUnionPackages"], "duplicate/dropped closure IDs")
    pathmap = g.unique_index(shared["packages"], lambda p: (p["name"], p["manifestVersion"], p["manifest"]))
    workspace_root = Path(metadata["workspace_root"])
    components, reused = [], 0
    for id_ in sorted(ids):
        g.need(id_ in byid, "closure ID absent from metadata")
        p = byid[id_]
        name, version, source = p["name"], p["version"], p["source"]
        issues, evidence = [], []

        def add(f, url, role=None, role_auto=True):
            path = f.get("collectedPath", f.get("localPath"))
            g.need(path is not None, "missing collected path")
            public_path = f.get("sourcePath", f.get("archiveMember", Path(path).name))
            evidence.append({"path": path, "sha256": f["sha256"], "size": f.get("size"), "publicPath": public_path,
                             "sourceURL": g.public_url(url), "role": g.candidate_role(public_path) if role_auto else role})

        if source is None:
            manifest = Path(p["manifest_path"]).relative_to(workspace_root).as_posix()
            alias = pathmap.get((name, version, manifest))
            g.need(alias is not None, "missing exact normalized path mapping")
            lockkey = (name, alias["lockVersion"], LOCAL_PATH_SOURCE)
            g.need(lockkey in bylock and bylock[lockkey]["category"] == "path", "normalized path not present in original lock")
            url = f"https://github.com/openai/codex/blob/{CODEX_COMMIT}/codex-rs/{manifest}"
            for f in shared["candidates"]:
                add(f, f"https://raw.githubusercontent.com/openai/codex/{CODEX_COMMIT}/{f['name']}")
            g.need({f["name"] for f in shared["candidates"]} >= {"LICENSE", "NOTICE"}, "shared root NOTICE or LICENSE absent")
            issues.append("shared-root-applicability-unreviewed")
            normalization = {"originalLockVersion": alias["lockVersion"], "normalizedManifestVersion": version, "manifest": manifest}
            components.append({"identity": id_, "name": name, "version": version, "sourceURL": g.public_url(url),
                               "lockIdentity": list(lockkey), "normalization": normalization,
                               "spdxManifestRaw": p["license"], "issues": issues, "evidence": evidence})
            continue
        lockkey = (name, version, source)
        g.need(lockkey in bylock, "exact external name/version/source absent from lock")
        lp = bylock[lockkey]
        e = lp["licenseEvidence"]
        old = old_by_lock.get(lockkey)
        if e.get("evidenceOrigin") == "reused-from-0.163.0-identical-lock-entry":
            g.need(old is not None and old["identity"] == id_ and lockkey in old_lock and
                   old_lock[lockkey]["checksum"] == lp["checksum"] and old["spdxManifestRaw"] == p["license"],
                   "reused component differs from the verified 0.163.0 component")
            components.append(old)
            reused += 1
            continue
        g.need(e.get("evidenceOrigin") == "collected-for-0.167.2", "external component has no collected evidence")
        if source.startswith("registry+"):
            g.need(source == g.REGISTRY and lp["category"] == "registry", "unsupported registry")
            g.need(e["manifestPackageMatches"] and e["sha256"] == lp["checksum"] == e["lockChecksum"],
                   "registry checksum/manifest mismatch")
            url = f"https://static.crates.io/crates/{name}/{name}-{version}.crate"
            for f in e["licenseTextFiles"]:
                add(f, url + "#" + quote(f["archiveMember"], safe="/"))
            for f in e.get("upstreamCandidates", []):
                g.need(e["vcsInfo"]["git"]["sha1"] in f["sourceURL"] and f["sourceCommit"] == e["vcsInfo"]["git"]["sha1"],
                       "upstream candidate lacks exact VCS commit")
                add(f, f["sourceURL"])
                issues.append("upstream-candidate-applicability-unreviewed")
        elif source.startswith("git+"):
            g.need(lp["category"] == "git", "category mismatch")
            parsed = urlsplit(source[4:])
            revision = parsed.fragment
            g.need(GITHUB_COMMIT.fullmatch(revision) and e["revision"] == revision and e["source"] == source, "Git revision mismatch")
            g.need(parsed.hostname == "github.com" and not parsed.username and not parsed.password, "unsupported Git public origin")
            repo = parsed.path.rstrip("/").removesuffix(".git")
            url = f"https://github.com{repo}/tree/{revision}"
            for f in e["repoLicenseTextFiles"]:
                add(f, f"https://raw.githubusercontent.com{repo}/{revision}/{f['sourcePath']}")
            issues.append("repository-license-scope-unreviewed")
        else:
            raise g.AuditError("unsupported external source")
        components.append({"identity": id_, "name": name, "version": version, "sourceURL": g.public_url(url),
                           "lockIdentity": list(lockkey), "normalization": None, "spdxManifestRaw": p["license"],
                           "issues": issues, "evidence": evidence})
    g.need(len(components) == len(ids), "target component dropped")
    refs.append({"path": "reused-components", "count": reused})
    return components, refs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("command", choices=("prepare",))
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        print(json.dumps(prepare(root), indent=2, sort_keys=True))
        return 0
    except (g.AuditError, OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        reason = str(error) if isinstance(error, g.AuditError) else type(error).__name__
        print("ERROR: prepare failed: " + reason, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
