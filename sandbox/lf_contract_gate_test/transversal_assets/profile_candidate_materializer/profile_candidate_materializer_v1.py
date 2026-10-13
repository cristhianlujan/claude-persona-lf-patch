#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

SCHEMA = "PROFILE_EVOLUTION_CANDIDATE_OVERLAY_V1"
RECEIPT_SCHEMA = "PROFILE_CANDIDATE_MATERIALIZATION_RECEIPT_V1"
MODES = {"NO_CHANGE", "PATCH", "SPECIALIZE", "ADAPT", "REARCHITECT", "OPTIMIZE"}


def _sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha_file(path: Path) -> str:
    return _sha_bytes(path.read_bytes())


def _canonical_sha(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return _sha_bytes(raw)


def _safe_rel(raw: Any) -> Path:
    if not isinstance(raw, str) or not raw.strip() or raw.startswith(("/", "\\")):
        raise ValueError("CANDIDATE_PATH_INVALID")
    rel = Path(raw)
    if rel.is_absolute() or ".." in rel.parts or any(part in ("", ".") for part in rel.parts):
        raise ValueError("CANDIDATE_PATH_ESCAPE")
    return rel


def _assert_outside(repo_root: Path, output_root: Path) -> None:
    rr = repo_root.resolve()
    out = output_root.resolve()
    try:
        out.relative_to(rr)
    except ValueError:
        return
    raise ValueError("CANDIDATE_OUTPUT_INSIDE_AUTHORITY_REPOSITORY")


def _validate_top(candidate: dict[str, Any], expected_revision: str) -> tuple[str, str]:
    if candidate.get("schema") != SCHEMA:
        raise ValueError("CANDIDATE_SCHEMA_INVALID")
    slug = candidate.get("profile_slug")
    code = candidate.get("profile_code")
    if not isinstance(slug, str) or not slug or any(ch not in "abcdefghijklmnopqrstuvwxyz0123456789_" for ch in slug):
        raise ValueError("CANDIDATE_PROFILE_SLUG_INVALID")
    if not isinstance(code, str) or not code:
        raise ValueError("CANDIDATE_PROFILE_CODE_INVALID")
    revision = candidate.get("baseline_revision")
    if (
        revision != expected_revision
        or not isinstance(revision, str)
        or len(revision) != 40
        or any(ch not in "0123456789abcdef" for ch in revision)
    ):
        raise ValueError("CANDIDATE_BASELINE_REVISION_MISMATCH")
    if candidate.get("evolution_mode") not in MODES:
        raise ValueError("CANDIDATE_EVOLUTION_MODE_INVALID")
    if candidate.get("authority_state") != "NON_AUTHORITY_CANDIDATE":
        raise ValueError("CANDIDATE_AUTHORITY_STATE_INVALID")
    if candidate.get("reversible") is not True:
        raise ValueError("CANDIDATE_REVERSIBILITY_REQUIRED")
    if candidate.get("profile_source_write_authorized") is not False:
        raise ValueError("CANDIDATE_SOURCE_WRITE_AUTHORITY_FORBIDDEN")
    if candidate.get("runtime_activation") is not False or candidate.get("production_activation") is not False:
        raise ValueError("CANDIDATE_ACTIVATION_FORBIDDEN")
    if not isinstance(candidate.get("evidence_map"), list) or not candidate["evidence_map"]:
        raise ValueError("CANDIDATE_EVIDENCE_MAP_REQUIRED")
    if not isinstance(candidate.get("preservation_constraints"), list) or not candidate["preservation_constraints"]:
        raise ValueError("CANDIDATE_PRESERVATION_CONSTRAINTS_REQUIRED")
    if not isinstance(candidate.get("changes"), list):
        raise ValueError("CANDIDATE_CHANGES_INVALID")
    return slug, code


def materialize(candidate: dict[str, Any], repo_root: Path, output_root: Path, expected_revision: str) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    output_root = output_root.resolve()
    _assert_outside(repo_root, output_root)
    slug, _code = _validate_top(candidate, expected_revision)

    source = (repo_root / "profiles" / slug).resolve()
    profiles_root = (repo_root / "profiles").resolve()
    try:
        source.relative_to(profiles_root)
    except ValueError as exc:
        raise ValueError("CANDIDATE_PROFILE_SOURCE_ESCAPE") from exc
    if not source.is_dir():
        raise ValueError("CANDIDATE_PROFILE_SOURCE_MISSING")
    if source.is_symlink() or any(p.is_symlink() for p in source.rglob("*")):
        raise ValueError("CANDIDATE_SOURCE_SYMLINK_FORBIDDEN")

    destination = output_root / slug
    if destination.exists():
        raise ValueError("CANDIDATE_OUTPUT_ALREADY_EXISTS")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination)

    before_tree = {
        str(p.relative_to(source)): _sha_file(p)
        for p in sorted(source.rglob("*"))
        if p.is_file()
    }

    changed: list[str] = []
    deleted: list[str] = []
    seen: set[str] = set()

    for item in candidate["changes"]:
        if not isinstance(item, dict):
            raise ValueError("CANDIDATE_CHANGE_RECORD_INVALID")
        rel = _safe_rel(item.get("path"))
        key = rel.as_posix()
        if key in seen:
            raise ValueError("CANDIDATE_CHANGE_PATH_DUPLICATE")
        seen.add(key)
        operation = item.get("operation")
        if operation not in {"UPSERT", "DELETE"}:
            raise ValueError("CANDIDATE_CHANGE_OPERATION_INVALID")

        src = source / rel
        dst = destination / rel
        existed = src.is_file()
        before_sha = item.get("before_sha256")

        if existed:
            actual_before = _sha_file(src)
            if before_sha != actual_before:
                raise ValueError("CANDIDATE_BEFORE_SHA256_MISMATCH")
        elif before_sha is not None:
            raise ValueError("CANDIDATE_NEW_FILE_BEFORE_SHA256_MUST_BE_NULL")

        if operation == "DELETE":
            if not existed:
                raise ValueError("CANDIDATE_DELETE_TARGET_MISSING")
            if item.get("content") not in (None, ""):
                raise ValueError("CANDIDATE_DELETE_CONTENT_FORBIDDEN")
            dst.unlink()
            deleted.append(key)
        else:
            content = item.get("content")
            if not isinstance(content, str):
                raise ValueError("CANDIDATE_UPSERT_CONTENT_REQUIRED")
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(content, encoding="utf-8")
            changed.append(key)

    if candidate.get("evolution_mode") == "NO_CHANGE" and (changed or deleted):
        raise ValueError("CANDIDATE_NO_CHANGE_HAS_DELTA")
    if candidate.get("evolution_mode") != "NO_CHANGE" and not (changed or deleted):
        raise ValueError("CANDIDATE_CHANGE_MODE_WITHOUT_DELTA")

    # Verify materialization did not mutate authority source.
    after_source_tree = {
        str(p.relative_to(source)): _sha_file(p)
        for p in sorted(source.rglob("*"))
        if p.is_file()
    }
    if before_tree != after_source_tree:
        raise RuntimeError("CANDIDATE_SOURCE_MUTATED")

    file_sha256s = {
        str(p.relative_to(destination)): _sha_file(p)
        for p in sorted(destination.rglob("*"))
        if p.is_file()
    }
    candidate_sha = _canonical_sha(candidate)
    receipt = {
        "schema": RECEIPT_SCHEMA,
        "candidate_sha256": candidate_sha,
        "baseline_revision": expected_revision,
        "profile_slug": slug,
        "output_root": str(destination),
        "changed_paths": sorted(changed),
        "deleted_paths": sorted(deleted),
        "file_sha256s": file_sha256s,
        "source_unchanged": True,
        "authority_state": "NON_AUTHORITY_CANDIDATE",
        "profile_source_write_authorized": False,
        "runtime_activation": False,
        "production_activation": False,
    }
    receipt["receipt_sha256"] = _canonical_sha(receipt)
    return receipt


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("candidate")
    ap.add_argument("repo_root")
    ap.add_argument("output_root")
    ap.add_argument("expected_revision")
    args = ap.parse_args()
    candidate = json.loads(Path(args.candidate).read_text(encoding="utf-8"))
    if not isinstance(candidate, dict):
        raise SystemExit("CANDIDATE_ROOT_NOT_OBJECT")
    try:
        receipt = materialize(candidate, Path(args.repo_root), Path(args.output_root), args.expected_revision)
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "blocking_code": str(exc)}, sort_keys=True))
        return 3
    print(json.dumps({"status": "PASS", "receipt": receipt}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
