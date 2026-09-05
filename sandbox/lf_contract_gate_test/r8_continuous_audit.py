#!/usr/bin/env python3
"""Versioned dispatcher for the read-only A01-A62 continuous audit.

Preserves the historical auditor byte-for-byte in r8_continuous_audit_legacy_v01.py
and resolves J11 runtime validation from the candidate manifest instead of
hardcoding validate_package.py v1.2.

Strategy 28 timing hardening keeps the historical static-audit result exact while
removing one `git hash-object` subprocess per audited artifact. A single cached
`git ls-files -s` read proves the in-process Git blob SHA-1 fast path against the
index. If a worktree/index mismatch is observed, the historical per-file
`git hash-object` path is used fail-safe for that artifact.
"""
from __future__ import annotations
from pathlib import Path
import sys
import yaml
import r8_continuous_audit_legacy_v01 as legacy

_orig_suite = legacy.suite
_orig_static = legacy.static
_index_blob_cache: dict[Path, dict[str, str]] = {}
_blob_fastpath_hits = 0
_blob_fallbacks = 0


def suite(root: Path, tmp: Path):
    results = _orig_suite(root, tmp)
    manifest = yaml.safe_load((root / "manifest.yaml").read_text(encoding="utf-8")) or {}
    configured = (
        manifest.get("maturity_extension", {})
        .get("package_gate_candidate", {})
        .get("validator")
    )
    relative = str(configured or "scripts/validate_package.py")
    if not relative.startswith("scripts/"):
        raise SystemExit(f"FAIL_J11_VALIDATOR_PATH_OUTSIDE_SKILL_SCRIPTS: {relative}")
    validator = root / relative
    if not validator.is_file():
        raise SystemExit(f"FAIL_J11_VALIDATOR_MISSING: {relative}")
    env = {"LF_JUDGE_VERSION": "v0.6", "LF_EXECUTOR_IDENTITY": legacy.EXEC}
    results["j11"] = [
        legacy.run(
            "j11_selftest",
            [sys.executable, str(validator), "--self-test"],
            root,
            (0,),
            env,
        ),
        legacy.run(
            "j11_package",
            [sys.executable, str(validator), str(root), "--evidence-ref", "continuous"],
            root,
            (0,),
            env,
        ),
    ]
    results["all"] = [item for key, group in results.items() if key != "all" for item in group]
    return results


def _indexed_blobs(root: Path) -> dict[str, str]:
    resolved = root.resolve()
    cached = _index_blob_cache.get(resolved)
    if cached is not None:
        return cached
    completed = legacy.subprocess.run(
        ["git", "ls-files", "-s", "-z", "--"],
        cwd=resolved,
        capture_output=True,
        check=True,
    )
    mapping: dict[str, str] = {}
    for record in completed.stdout.split(b"\0"):
        if not record:
            continue
        metadata, sep, raw_path = record.partition(b"\t")
        if not sep:
            continue
        fields = metadata.split()
        if len(fields) < 2:
            continue
        mapping[raw_path.decode("utf-8", "strict")] = fields[1].decode("ascii", "strict")
    _index_blob_cache[resolved] = mapping
    return mapping


def _git_blob_sha1(rel: str, root: Path, payload: bytes) -> str:
    global _blob_fastpath_hits, _blob_fallbacks
    direct = legacy.hashlib.sha1(
        f"blob {len(payload)}\0".encode("ascii") + payload
    ).hexdigest()
    indexed = _indexed_blobs(root).get(rel)
    if indexed == direct:
        _blob_fastpath_hits += 1
        return direct
    _blob_fallbacks += 1
    return legacy.subprocess.run(
        ["git", "hash-object", str(root / rel)],
        cwd=root,
        text=True,
        capture_output=True,
    ).stdout.strip()


def static(rel, root, inv):
    p = root / rel
    f = []
    if not p.is_file():
        return {"passed": False, "findings": ["missing"]}
    b = p.read_bytes()
    t = b.decode("utf-8")
    if b.startswith(b"\xef\xbb\xbf"):
        f += ["bom"]
    if b"\r\n" in b:
        f += ["crlf"]
    if not b.endswith(b"\n"):
        f += ["final_newline"]
    if rel not in inv:
        f += ["not_in_manifest"]
    try:
        if p.suffix == ".json":
            legacy.json.loads(t)
        elif p.suffix in (".yaml", ".yml"):
            legacy.yaml.safe_load(t)
        elif p.suffix == ".py":
            legacy.ast.parse(t)
    except Exception as exc:
        f += [f"parse:{type(exc).__name__}"]
    if rel not in {"manifest.yaml", "scripts/validate_package.py"} and legacy.FBD.search(t):
        f += ["forbidden_status"]
    refs = sorted(set(legacy.REF.findall(t)) - {rel})
    broken = [item for item in refs if item not in inv]
    if broken:
        f += ["broken_refs:" + ",".join(broken[:8])]
    if not rel.startswith("templates/") and rel != "scripts/validate_package.py":
        hits = sorted(set(legacy.PH.findall(legacy.re.sub(r"`[^`\n]+`", "", t))))
        if hits:
            f += ["placeholders:" + ",".join(hits)]
    if p.suffix == ".md" and (
        not legacy.re.search(r"(?m)^#\s+\S", t)
        or len(legacy.re.findall(r"(?m)^##\s+", t)) < 2
    ):
        f += ["markdown_structure"]
    if rel.startswith("judges/"):
        data = legacy.yaml.safe_load(t)
        for key in (
            "scope",
            "required_inputs",
            "preflight",
            "pass_if",
            "block_if",
            "output",
            "prohibitions",
        ):
            if not data.get(key):
                f += [f"judge_missing:{key}"]
        if not (data.get("judge_code") or data.get("code")):
            f += ["judge_code"]
        if not (data.get("version") or data.get("judge_version")):
            f += ["judge_version"]
    if rel.startswith("schemas/"):
        data = legacy.json.loads(t)
        for key in ("$schema", "title", "type"):
            if key not in data:
                f += [f"schema_missing:{key}"]
    return {
        "passed": not f,
        "findings": f,
        "bytes": len(b),
        "sha256": legacy.hashlib.sha256(b).hexdigest(),
        "git_blob_sha1": _git_blob_sha1(rel, root, b),
        "broken_refs": broken,
    }


legacy.suite = suite
legacy.static = static

if __name__ == "__main__":
    rc = legacy.main()
    print(
        f"PASS_R8_GIT_BLOB_FASTPATH={_blob_fastpath_hits}/{_blob_fastpath_hits + _blob_fallbacks} "
        f"fallbacks={_blob_fallbacks}"
    )
    raise SystemExit(rc)
