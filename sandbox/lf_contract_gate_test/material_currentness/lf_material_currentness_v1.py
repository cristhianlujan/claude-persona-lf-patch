#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")

class CurrentnessError(Exception):
    pass


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def run_git(repo: Path, *args: str, check: bool = True) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if check and cp.returncode != 0:
        raise CurrentnessError(f"GIT_FAILED:{' '.join(args)}:{cp.stderr.strip()}")
    return cp.stdout.strip()


def git_object_exists(repo: Path, rev: str) -> bool:
    cp = subprocess.run(["git", "-C", str(repo), "cat-file", "-e", f"{rev}^{{commit}}"], capture_output=True)
    return cp.returncode == 0


def git_is_ancestor(repo: Path, old: str, new: str) -> bool:
    cp = subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", old, new], capture_output=True)
    return cp.returncode == 0


def _matches(path: str, selectors: dict[str, Any]) -> bool:
    paths = selectors.get("paths") or []
    prefixes = selectors.get("prefixes") or []
    globs = selectors.get("globs") or []
    return path in paths or any(path.startswith(p) for p in prefixes) or any(fnmatch.fnmatch(path, g) for g in globs)


def git_tree_material(repo: Path, rev: str, selectors: dict[str, Any], required: bool) -> tuple[str, list[dict[str, str]]]:
    if not any(selectors.get(k) for k in ("paths", "prefixes", "globs")):
        raise CurrentnessError("GIT_TREE_SELECTOR_EMPTY")
    out = run_git(repo, "ls-tree", "-r", "--full-tree", rev)
    entries: list[dict[str, str]] = []
    for line in out.splitlines():
        if not line:
            continue
        meta, path = line.split("\t", 1)
        mode, obj_type, sha = meta.split(" ", 2)
        if obj_type != "blob" or not _matches(path, selectors):
            continue
        entries.append({"path": path, "mode": mode, "blob_sha1": sha})
    entries.sort(key=lambda x: x["path"])
    if required and not entries:
        raise CurrentnessError("GIT_TREE_REQUIRED_MATERIAL_EMPTY")
    return canonical_sha256(entries), entries


def topo_validate(materials: dict[str, dict[str, Any]]) -> None:
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(mid: str) -> None:
        if mid in visited:
            return
        if mid in visiting:
            raise CurrentnessError(f"DEPENDENCY_CYCLE:{mid}")
        visiting.add(mid)
        for dep in materials[mid].get("depends_on") or []:
            if dep not in materials:
                raise CurrentnessError(f"UNKNOWN_DEPENDENCY:{mid}:{dep}")
            visit(dep)
        visiting.remove(mid)
        visited.add(mid)

    for mid in sorted(materials):
        visit(mid)


def affected_closure(changed: set[str], materials: dict[str, dict[str, Any]]) -> list[str]:
    reverse: dict[str, set[str]] = {k: set() for k in materials}
    for mid, spec in materials.items():
        for dep in spec.get("depends_on") or []:
            reverse.setdefault(dep, set()).add(mid)
    out = set(changed)
    queue = list(changed)
    while queue:
        dep = queue.pop(0)
        for consumer in sorted(reverse.get(dep, set())):
            if consumer not in out:
                out.add(consumer)
                queue.append(consumer)
    return sorted(out)


def evaluate(binding: dict[str, Any], repo: Path) -> dict[str, Any]:
    if binding.get("schema_version") != "LF_MATERIAL_CURRENTNESS_BINDING_V1":
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "BINDING_SCHEMA_UNSUPPORTED"}
    authority = binding.get("authority") or {}
    bound = authority.get("bound_revision")
    current = authority.get("current_revision")
    authority_ref = authority.get("ref")
    evidence = binding.get("evidence_revision")
    if not authority_ref or not isinstance(authority_ref, str):
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "AUTHORITY_REF_MISSING"}
    if not isinstance(bound, str) or not HEX40.fullmatch(bound) or not isinstance(current, str) or not HEX40.fullmatch(current):
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "REVISION_FORMAT_INVALID"}
    if evidence != bound:
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "EVIDENCE_REVISION_MUST_EQUAL_BOUND_REVISION"}
    if binding.get("dependency_completeness") != "COMPLETE":
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "DEPENDENCY_COMPLETENESS_NOT_COMPLETE", "bound_revision": bound, "current_revision": current}
    if not git_object_exists(repo, bound) or not git_object_exists(repo, current):
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "REVISION_NOT_AVAILABLE_LOCALLY", "bound_revision": bound, "current_revision": current}
    if binding.get("require_ancestor", True) and not git_is_ancestor(repo, bound, current):
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "AUTHORITY_DIVERGED", "bound_revision": bound, "current_revision": current}

    raw_materials = binding.get("materials")
    if not isinstance(raw_materials, list) or not raw_materials:
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "MATERIALS_MISSING"}
    materials: dict[str, dict[str, Any]] = {}
    for spec in raw_materials:
        mid = spec.get("material_id") if isinstance(spec, dict) else None
        if not mid or mid in materials:
            return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "MATERIAL_ID_INVALID_OR_DUPLICATE"}
        materials[mid] = spec
    try:
        topo_validate(materials)
    except CurrentnessError as exc:
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": str(exc)}

    fingerprints: dict[str, dict[str, Any]] = {}
    changed: set[str] = set()
    try:
        for mid in sorted(materials):
            spec = materials[mid]
            kind = spec.get("kind")
            if kind == "GIT_TREE":
                selectors = spec.get("selectors") or {}
                required = bool(spec.get("required", True))
                old_fp, old_entries = git_tree_material(repo, bound, selectors, required)
                new_fp, new_entries = git_tree_material(repo, current, selectors, required)
                fingerprints[mid] = {
                    "kind": kind,
                    "bound_fingerprint": old_fp,
                    "current_fingerprint": new_fp,
                    "bound_entry_count": len(old_entries),
                    "current_entry_count": len(new_entries),
                }
            elif kind == "DIGEST":
                old_fp = spec.get("bound_digest")
                new_fp = spec.get("current_digest")
                if not isinstance(old_fp, str) or not HEX64.fullmatch(old_fp) or not isinstance(new_fp, str) or not HEX64.fullmatch(new_fp):
                    raise CurrentnessError(f"DIGEST_INVALID:{mid}")
                fingerprints[mid] = {"kind": kind, "bound_fingerprint": old_fp, "current_fingerprint": new_fp}
            else:
                raise CurrentnessError(f"MATERIAL_KIND_UNSUPPORTED:{mid}:{kind}")
            if fingerprints[mid]["bound_fingerprint"] != fingerprints[mid]["current_fingerprint"]:
                changed.add(mid)
    except CurrentnessError as exc:
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": str(exc), "bound_revision": bound, "current_revision": current}

    affected = affected_closure(changed, materials)
    root_ids = binding.get("root_material_ids") or sorted(materials)
    if not isinstance(root_ids, list) or any(r not in materials for r in root_ids):
        return {"decision": "UNKNOWN_FAIL_CLOSED", "ready": False, "reason": "ROOT_MATERIAL_INVALID"}
    affected_roots = sorted(set(root_ids).intersection(affected))
    old_agg = canonical_sha256({mid: fingerprints[mid]["bound_fingerprint"] for mid in sorted(materials)})
    new_agg = canonical_sha256({mid: fingerprints[mid]["current_fingerprint"] for mid in sorted(materials)})

    if affected_roots:
        decision = "STALE_AFFECTED"
        ready = False
        rebind_allowed = False
    elif bound != current:
        decision = "CURRENT_REBOUND"
        ready = True
        rebind_allowed = True
    else:
        decision = "CURRENT"
        ready = True
        rebind_allowed = False

    receipt = {
        "schema_version": "LF_MATERIAL_CURRENTNESS_RECEIPT_V1",
        "engine_version": "1.0.0-candidate",
        "decision": decision,
        "ready": ready,
        "rebind_allowed": rebind_allowed,
        "authority_ref": authority_ref,
        "evidence_revision": evidence,
        "bound_revision": bound,
        "current_revision": current,
        "dependency_completeness": "COMPLETE",
        "changed_material_ids": sorted(changed),
        "affected_material_ids": affected,
        "affected_root_material_ids": affected_roots,
        "bound_material_fingerprint": old_agg,
        "current_material_fingerprint": new_agg,
        "materials": fingerprints,
    }
    receipt["receipt_sha256"] = canonical_sha256(receipt)
    return receipt


def main() -> int:
    ap = argparse.ArgumentParser(description="LF material-aware currentness evaluator; performs no network I/O.")
    ap.add_argument("--binding", type=Path, required=True)
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--output", type=Path)
    ap.add_argument("--current-revision", help="Override authority.current_revision with a locally available exact commit SHA.")
    ns = ap.parse_args()
    binding = json.loads(ns.binding.read_text(encoding="utf-8"))
    if ns.current_revision:
        binding.setdefault("authority", {})["current_revision"] = ns.current_revision
    result = evaluate(binding, ns.repo)
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if result.get("ready") else 2

if __name__ == "__main__":
    raise SystemExit(main())
