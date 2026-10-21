#!/usr/bin/env python3
"""Trusted offline packet builder for the future PASE qualification issuer.

This file has no database or network writer. --dry-run validates candidate-as-data
snapshots, independent review evidence and the canonical qualification contract,
then emits the exact packet/result that a separately approved DB wrapper would
persist.

It intentionally refuses self-governance/protected-path candidates.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
QUAL_PATH = HERE / "pase_control_qualification_v1.py"
REVIEW_PATH = HERE / "validate_independent_review_v1.py"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")

AUTO_QS = ("Q01", "Q02", "Q03", "Q04", "Q07", "Q08", "Q11")
REVIEW_QS = ("Q05", "Q06", "Q09", "Q10")
ALL_QS = tuple(f"Q{i:02d}" for i in range(1, 12))

PROTECTED_EXACT = {
    ".github/workflows/lf-migration-merge-train.yml",
    ".github/workflows/pase-merge-gate.yml",
    ".github/workflows/pase-control-qualification-issuer.yml",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_pase_control_system_route_registry_v1.json",
}
PROTECTED_PREFIXES = (
    "sandbox/lf_contract_gate_test/pase_control_qualification/",
    "sandbox/lf_contract_gate_test/pase_merge_gate/",
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_pase_merge_route",
    "sandbox/lf_contract_gate_test/db_write_transport/",
)


class IssuerError(ValueError):
    pass


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise IssuerError(f"BLOCK_QUALIFICATION_TRUSTED_MODULE_LOAD:{path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


QUAL = _load(QUAL_PATH, "pase_control_qualification_v1_issuer")
REVIEW = _load(REVIEW_PATH, "validate_independent_review_v1_issuer")


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_obj(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise IssuerError(code)
    return value.strip()


def _sha40(value: Any, code: str) -> str:
    if not isinstance(value, str) or HEX40.fullmatch(value) is None:
        raise IssuerError(code)
    return value


def _sha64(value: Any, code: str) -> str:
    if not isinstance(value, str) or HEX64.fullmatch(value) is None:
        raise IssuerError(code)
    return value


def is_protected_path(path: str) -> bool:
    return path in PROTECTED_EXACT or any(path.startswith(prefix) for prefix in PROTECTED_PREFIXES)


def material_records(snapshot: Mapping[str, Any]) -> list[dict[str, str]]:
    rows = snapshot.get("changed_files")
    if not isinstance(rows, list) or not rows:
        raise IssuerError("BLOCK_QUALIFICATION_CHANGED_FILES")
    out: list[dict[str, str]] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, Mapping):
            raise IssuerError("BLOCK_QUALIFICATION_CHANGED_FILE_SHAPE")
        path = _text(row.get("path"), "BLOCK_QUALIFICATION_CHANGED_FILE_PATH")
        if path in seen:
            raise IssuerError("BLOCK_QUALIFICATION_CHANGED_FILE_DUPLICATE")
        seen.add(path)
        status = _text(row.get("status"), "BLOCK_QUALIFICATION_CHANGED_FILE_STATUS")
        blob_sha = _text(row.get("blob_sha"), "BLOCK_QUALIFICATION_CHANGED_FILE_BLOB")
        if not re.fullmatch(r"[0-9a-f]{40}", blob_sha):
            raise IssuerError("BLOCK_QUALIFICATION_CHANGED_FILE_BLOB")
        if row.get("review_material") is True:
            out.append({"path": path, "status": status, "blob_sha": blob_sha})
    if not out:
        raise IssuerError("BLOCK_QUALIFICATION_REVIEW_MATERIAL_EMPTY")
    return sorted(out, key=lambda x: x["path"])


def material_sha256(snapshot: Mapping[str, Any]) -> str:
    return sha256_obj(material_records(snapshot))


def _auto_evidence(snapshot: Mapping[str, Any], qid: str) -> list[str]:
    auto = snapshot.get("auto_evidence")
    if not isinstance(auto, Mapping):
        raise IssuerError("BLOCK_QUALIFICATION_AUTO_EVIDENCE")
    rows = auto.get(qid)
    if not isinstance(rows, list) or not rows or any(not isinstance(x, str) or not x.strip() for x in rows):
        raise IssuerError(f"BLOCK_QUALIFICATION_AUTO_EVIDENCE:{qid}")
    return list(rows)


def _validate_snapshot(snapshot: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(snapshot, Mapping) or snapshot.get("schema_version") != "lf-pase-control-qualification-issuer-input/v1":
        raise IssuerError("BLOCK_QUALIFICATION_ISSUER_INPUT_SCHEMA")
    repository = _text(snapshot.get("repository"), "BLOCK_QUALIFICATION_REPOSITORY")
    pr_number = snapshot.get("pr_number")
    if not isinstance(pr_number, int) or pr_number <= 0:
        raise IssuerError("BLOCK_QUALIFICATION_PR_NUMBER")
    base_sha = _sha40(snapshot.get("base_sha"), "BLOCK_QUALIFICATION_BASE_SHA")
    head_sha = _sha40(snapshot.get("head_sha"), "BLOCK_QUALIFICATION_HEAD_SHA")
    observed_main_sha = _sha40(snapshot.get("observed_main_sha"), "BLOCK_QUALIFICATION_OBSERVED_MAIN_SHA")
    if base_sha != observed_main_sha or base_sha == head_sha:
        raise IssuerError("BLOCK_QUALIFICATION_EXACT_HEAD_RANGE")
    candidate_id = _text(snapshot.get("candidate_id"), "BLOCK_QUALIFICATION_CANDIDATE_ID")
    declared_owner = _text(snapshot.get("declared_owner"), "BLOCK_QUALIFICATION_DECLARED_OWNER")
    builder_session_id = _text(snapshot.get("builder_session_id"), "BLOCK_QUALIFICATION_BUILDER_SESSION_ID")
    builder_session_ref = _text(snapshot.get("builder_session_ref"), "BLOCK_QUALIFICATION_BUILDER_SESSION_REF")
    qualification_type = _text(snapshot.get("qualification_type"), "BLOCK_QUALIFICATION_TYPE")

    route = snapshot.get("route")
    if not isinstance(route, Mapping) or route.get("mode") != "CONTROL_SYSTEM_QUALIFICATION" or route.get("candidate_id") != candidate_id:
        raise IssuerError("BLOCK_QUALIFICATION_ROUTE")
    manifest_sha = _sha64(snapshot.get("changeset_manifest_sha256"), "BLOCK_QUALIFICATION_CHANGESET_MANIFEST_SHA")

    changed = snapshot.get("changed_files")
    protected = [row["path"] for row in changed if isinstance(row, Mapping) and isinstance(row.get("path"), str) and is_protected_path(row["path"])]
    if protected:
        raise IssuerError("ESCALATE_CONTROL_SYSTEM_SELF_CHANGE:" + ",".join(sorted(protected)))

    for key in ("scope_paths", "owner_local_tests", "boundary_invariants", "expected_coverage"):
        value = snapshot.get(key)
        if not isinstance(value, list) or not value or any(not isinstance(x, str) or not x.strip() for x in value):
            raise IssuerError(f"BLOCK_QUALIFICATION_{key.upper()}")

    for qid in AUTO_QS:
        _auto_evidence(snapshot, qid)

    return {
        "repository": repository,
        "pr_number": pr_number,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "candidate_id": candidate_id,
        "declared_owner": declared_owner,
        "builder_session_id": builder_session_id,
        "builder_session_ref": builder_session_ref,
        "qualification_type": qualification_type,
        "changeset_manifest_sha256": manifest_sha,
    }


def build(snapshot: Mapping[str, Any], review: Mapping[str, Any] | None) -> dict[str, Any]:
    ident = _validate_snapshot(snapshot)
    material_hash = material_sha256(snapshot)
    if review is None:
        raise IssuerError("BLOCK_QUALIFICATION_REVIEW_MISSING")

    try:
        normalized_review = REVIEW.validate_review(
            review,
            repository=ident["repository"],
            pr_number=ident["pr_number"],
            candidate_id=ident["candidate_id"],
            candidate_material_sha256=material_hash,
            builder_session_id=ident["builder_session_id"],
            builder_session_ref=ident["builder_session_ref"],
            qualification_type=ident["qualification_type"],
        )
    except REVIEW.ReviewError as exc:
        raise IssuerError(str(exc)) from exc

    packet = {
        "schema_version": "lf-pase-control-qualification/v1",
        "qualification_type": ident["qualification_type"],
        "repository": ident["repository"],
        "base_sha": ident["base_sha"],
        "head_sha": ident["head_sha"],
        "observed_main_sha": ident["base_sha"],
        "candidate_id": ident["candidate_id"],
        "declared_owner": ident["declared_owner"],
        "scope_paths": list(snapshot["scope_paths"]),
        "owner_local_tests": list(snapshot["owner_local_tests"]),
        "boundary_invariants": list(snapshot["boundary_invariants"]),
        "expected_coverage": list(snapshot["expected_coverage"]),
        "replacement": snapshot.get("replacement"),
    }

    checks: list[dict[str, Any]] = []
    for qid in ALL_QS:
        if qid in AUTO_QS:
            checks.append({"id": qid, "status": "PASS", "evidence": _auto_evidence(snapshot, qid)})
        else:
            row = normalized_review["checks"][qid]
            checks.append({"id": qid, "status": row["status"], "evidence": row["evidence"]})

    statuses = {row["status"] for row in checks}
    verdict = "FAIL" if "FAIL" in statuses else ("BLOCKED" if "BLOCKED" in statuses else "CANDIDATE_QUALIFIED")
    result = {
        "schema_version": "lf-pase-control-qualification-result/v1",
        "candidate_id": ident["candidate_id"],
        "base_sha": ident["base_sha"],
        "head_sha": ident["head_sha"],
        "declared_owner": ident["declared_owner"],
        "checks": checks,
        "external_findings": [],
        "coverage_complete": verdict == "CANDIDATE_QUALIFIED",
        "verdict": verdict,
        "qualified_only": True,
        "activation_authorized": False,
        "cutover_authorized": False,
        "rebind_authorized": False,
        "legacy_retirement_authorized": False,
    }
    try:
        contract_verdict = QUAL.validate_result(packet, result)
    except QUAL.QualificationError as exc:
        raise IssuerError(f"BLOCK_QUALIFICATION_CONTRACT:{exc}") from exc
    if contract_verdict != verdict:
        raise IssuerError("BLOCK_QUALIFICATION_CONTRACT_VERDICT_DRIFT")

    review_digest = sha256_obj(review)
    request_material = {
        "repository": ident["repository"],
        "pr_number": ident["pr_number"],
        "candidate_id": ident["candidate_id"],
        "base_sha": ident["base_sha"],
        "head_sha": ident["head_sha"],
        "candidate_material_sha256": material_hash,
        "changeset_manifest_sha256": ident["changeset_manifest_sha256"],
        "review_sha256": review_digest,
        "qualification_input": packet,
        "qualification_result": result,
    }
    request_sha = sha256_obj(request_material)
    source_execution_id = f"EXEC-PASE-CONTROL-QUAL-PR{ident['pr_number']}-{ident['head_sha'][:12]}"
    idempotency_key = f"pase-control-qual:{ident['repository']}:{ident['candidate_id']}:{ident['head_sha']}"

    return {
        "schema_version": "lf-pase-control-qualification-issuer-dry-run/v1",
        "status": "READY_TO_RECORD" if verdict == "CANDIDATE_QUALIFIED" else verdict,
        "recordable": verdict == "CANDIDATE_QUALIFIED",
        "repository": ident["repository"],
        "pr_number": ident["pr_number"],
        "candidate_id": ident["candidate_id"],
        "base_sha": ident["base_sha"],
        "head_sha": ident["head_sha"],
        "candidate_material_sha256": material_hash,
        "changeset_manifest_sha256": ident["changeset_manifest_sha256"],
        "review_sha256": review_digest,
        "reviewer_session_id": normalized_review["reviewer_session_id"],
        "reviewer_session_ref": normalized_review["reviewer_session_ref"],
        "source_execution_id": source_execution_id,
        "idempotency_key": idempotency_key,
        "request_sha256": request_sha,
        "qualification_input": packet,
        "qualification_result": result,
    }


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", required=True)
    ap.add_argument("--input", type=Path, required=True)
    ap.add_argument("--review", type=Path)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    try:
        snapshot = read_json(args.input)
        review = read_json(args.review) if args.review else None
        out = build(snapshot, review)
    except (OSError, UnicodeError, json.JSONDecodeError, IssuerError) as exc:
        print(json.dumps({"status": "BLOCK", "error": str(exc)}, sort_keys=True))
        return 2
    text = json.dumps(out, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if out["recordable"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
