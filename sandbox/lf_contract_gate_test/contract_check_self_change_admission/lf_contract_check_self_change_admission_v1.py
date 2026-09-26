#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any, Mapping, Sequence

REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
BASE_BRANCH = "main"
PROTECTED_SURFACES = (
    ".github/workflows/lf-contract-check.yml",
    "scripts/lf_contract_check.py",
    "sandbox/lf_contract_gate_test/lf_contract.yml",
)
ANCHOR_SURFACES = (
    ".github/workflows/lf-contract-check.yml",
    "scripts/lf_contract_check.py",
)
GUARD_SURFACES = (
    ".github/workflows/lf-github-reconcile-v3.yml",
    "sandbox/lf_contract_gate_test/contract_check_self_change_admission/lf_contract_check_self_change_admission_v1.py",
    "sandbox/lf_contract_gate_test/contract_check_self_change_admission/lf_independent_change_admission_carrier_v1.py",
)
RECEIPT_PREFIX = "sandbox/lf_contract_gate_test/receipts/"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PASS_RECEIPT_RESULTS = {"PASS_CANDIDATE", "PASS_SANDBOX_CANDIDATE"}
PASS_ISSUERS = {"operation_judge", "contract_judge"}


class AdmissionError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str = "") -> None:
    raise AdmissionError(code, detail)


def _load_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _load_paths(path: str | Path) -> list[str]:
    return sorted({line.strip() for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()})


def _safe_repo_path(path: str) -> bool:
    if not path or path.startswith("/") or "\\" in path:
        return False
    p = PurePosixPath(path)
    return all(part not in {"", ".", ".."} for part in p.parts)


def is_receipt_path(path: str) -> bool:
    return path.startswith(RECEIPT_PREFIX) and path.endswith(".json") and _safe_repo_path(path)


def is_contract_check_lookalike(path: str) -> bool:
    if path in PROTECTED_SURFACES:
        return False
    return (
        path.startswith(".github/workflows/lf-contract-check.")
        or path.startswith(".github/workflows/lf-contract-check/")
        or path.startswith("scripts/lf_contract_check.")
        or path.startswith("scripts/lf_contract_check/")
        or path.startswith("sandbox/lf_contract_gate_test/lf_contract.")
        or path.startswith("sandbox/lf_contract_gate_test/lf_contract/")
    )


def classify_paths(changed_files: Sequence[str]) -> dict[str, Any]:
    changed = sorted(set(changed_files))
    if any(not _safe_repo_path(path) for path in changed):
        _fail("BLOCK_SELF_CHANGE_UNSAFE_PATH")
    protected = sorted(set(changed).intersection(PROTECTED_SURFACES))
    guard = sorted(set(changed).intersection(GUARD_SURFACES))
    lookalikes = sorted(path for path in changed if is_contract_check_lookalike(path))
    applicable = bool(protected or lookalikes)
    if applicable and guard:
        _fail("BLOCK_SELF_CHANGE_GUARD_COCHANGE", ",".join(guard))
    if lookalikes:
        _fail("BLOCK_SELF_CHANGE_LOOKALIKE_PATH", ",".join(lookalikes))
    return {
        "status": "SELF_CHANGE_REQUIRED" if protected else "PASS_NOT_APPLICABLE",
        "applicable": bool(protected),
        "protected_touched": protected,
        "guard_touched": guard,
        "changed_count": len(changed),
    }


def receipt_paths(changed_files: Sequence[str]) -> list[str]:
    return sorted(path for path in set(changed_files) if is_receipt_path(path))


def _require_hex40(value: Any, code: str) -> str:
    if not isinstance(value, str) or HEX40.fullmatch(value) is None:
        _fail(code, str(value))
    return value


def _require_hex64(value: Any, code: str) -> str:
    if not isinstance(value, str) or HEX64.fullmatch(value) is None:
        _fail(code, str(value))
    return value


def _anchor_map(rows: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        _fail("BLOCK_SELF_CHANGE_ANCHOR_SHAPE")
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, Mapping):
            _fail("BLOCK_SELF_CHANGE_ANCHOR_SHAPE")
        path = row.get("path")
        if path in out:
            _fail("BLOCK_SELF_CHANGE_ANCHOR_DUPLICATE", str(path))
        if isinstance(path, str):
            out[path] = dict(row)
    return out


def _step_map(rows: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        _fail("BLOCK_SELF_CHANGE_STEPS_SHAPE")
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, Mapping):
            _fail("BLOCK_SELF_CHANGE_STEPS_SHAPE")
        step_id = row.get("step_id")
        if isinstance(step_id, str):
            out[step_id] = dict(row)
    return out


def evaluate_admission(payload: Mapping[str, Any]) -> dict[str, Any]:
    changed = payload.get("changed_files")
    if not isinstance(changed, list) or any(not isinstance(v, str) for v in changed):
        _fail("BLOCK_SELF_CHANGE_CHANGED_FILES_SHAPE")
    classification = classify_paths(changed)
    if not classification["applicable"]:
        return classification

    repository = payload.get("repository")
    base_branch = payload.get("base_branch")
    event_base_sha = _require_hex40(payload.get("event_base_sha"), "BLOCK_SELF_CHANGE_BASE_SHA")
    current_main_sha = _require_hex40(payload.get("current_main_sha"), "BLOCK_SELF_CHANGE_CURRENT_MAIN_SHA")
    event_head_sha = _require_hex40(payload.get("event_head_sha"), "BLOCK_SELF_CHANGE_HEAD_SHA")
    observed_head_sha = _require_hex40(payload.get("observed_head_sha"), "BLOCK_SELF_CHANGE_OBSERVED_HEAD_SHA")
    if repository != REPOSITORY:
        _fail("BLOCK_SELF_CHANGE_REPOSITORY_IDENTITY", str(repository))
    if base_branch != BASE_BRANCH:
        _fail("BLOCK_SELF_CHANGE_BASE_BRANCH", str(base_branch))
    if event_base_sha != current_main_sha:
        _fail("BLOCK_SELF_CHANGE_STALE_BASE", f"event={event_base_sha} current={current_main_sha}")
    if event_head_sha != observed_head_sha:
        _fail("BLOCK_SELF_CHANGE_HEAD_MISMATCH", f"event={event_head_sha} observed={observed_head_sha}")

    receipts = receipt_paths(changed)
    receipt_path = payload.get("receipt_path")
    if len(receipts) != 1 or receipt_path != receipts[0]:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_CARDINALITY", json.dumps(receipts))
    receipt = payload.get("receipt")
    if not isinstance(receipt, Mapping):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_SHAPE")
    if receipt.get("receipt_type") != "LF_OPERATION_CANDIDATE_RECEIPT":
        _fail("BLOCK_SELF_CHANGE_RECEIPT_TYPE")
    if receipt.get("issued_by") not in PASS_ISSUERS:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_ISSUER")
    if receipt.get("result") not in PASS_RECEIPT_RESULTS:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_RESULT")
    if receipt.get("all_pre_merge_required_steps_pass") is not True:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_PREMERGE")
    if receipt.get("operation_code") != "GITHUB_CONTRACT_GATE_LF":
        _fail("BLOCK_SELF_CHANGE_RECEIPT_OPERATION", str(receipt.get("operation_code")))
    execution_id = receipt.get("execution_id")
    if not isinstance(execution_id, str) or not execution_id.strip():
        _fail("BLOCK_SELF_CHANGE_EXECUTION_ID")
    code_head = _require_hex40(receipt.get("candidate_code_head"), "BLOCK_SELF_CHANGE_CODE_HEAD")
    terminal_step = receipt.get("pre_merge_terminal_step")
    if not isinstance(terminal_step, str) or not terminal_step.strip():
        _fail("BLOCK_SELF_CHANGE_TERMINAL_STEP")
    if receipt.get("operation_status_at_issue") != "IN_PROGRESS":
        _fail("BLOCK_SELF_CHANGE_RECEIPT_FINALITY")
    if receipt.get("blocking_codes") not in ([], None):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_BLOCKERS")
    if not receipt.get("contract_sha") or not receipt.get("judge_sha"):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_WEAK_EVIDENCE")
    if not isinstance(receipt.get("source_sha_list"), list) or not receipt.get("source_sha_list"):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_WEAK_EVIDENCE")

    if payload.get("code_head_is_ancestor") is not True:
        _fail("BLOCK_SELF_CHANGE_CODE_HEAD_NOT_ANCESTOR")
    post_code_head = payload.get("post_code_head_files")
    if not isinstance(post_code_head, list) or not post_code_head or receipt_path not in post_code_head:
        _fail("BLOCK_SELF_CHANGE_RECEIPT_NOT_POST_CODE_HEAD")
    illegal_post = sorted(path for path in post_code_head if not is_receipt_path(path))
    if illegal_post:
        _fail("BLOCK_SELF_CHANGE_POST_HEAD_CONTAMINATION", ",".join(illegal_post))

    target_paths = receipt.get("target_paths")
    blob_map = receipt.get("target_blob_sha_by_path")
    if not isinstance(target_paths, list) or not isinstance(blob_map, Mapping):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_TARGET_SHAPE")
    protected = classification["protected_touched"]
    if any(path not in target_paths for path in protected):
        _fail("BLOCK_SELF_CHANGE_RECEIPT_TARGET_MISMATCH")
    observed_blobs = payload.get("candidate_blob_sha_by_path")
    if not isinstance(observed_blobs, Mapping):
        _fail("BLOCK_SELF_CHANGE_CANDIDATE_BLOB_MAP")
    for path in protected:
        expected = _require_hex40(blob_map.get(path), "BLOCK_SELF_CHANGE_RECEIPT_BLOB_MISSING")
        observed = _require_hex40(observed_blobs.get(path), "BLOCK_SELF_CHANGE_CANDIDATE_BLOB_MISSING")
        if expected != observed:
            _fail("BLOCK_SELF_CHANGE_RECEIPT_BLOB_MISMATCH", f"{path}:{expected}!={observed}")

    anchors = _anchor_map(payload.get("anchors"))
    base_observed = payload.get("base_observed_anchors")
    if not isinstance(base_observed, Mapping):
        _fail("BLOCK_SELF_CHANGE_BASE_ANCHOR_SHAPE")
    for path in ANCHOR_SURFACES:
        row = anchors.get(path)
        observed = base_observed.get(path)
        if row is None or not isinstance(observed, Mapping):
            _fail("BLOCK_SELF_CHANGE_ANCHOR_MISSING", path)
        expected_blob = _require_hex40(row.get("expected_git_blob"), "BLOCK_SELF_CHANGE_ANCHOR_BLOB")
        expected_sha = _require_hex64(row.get("expected_sha256"), "BLOCK_SELF_CHANGE_ANCHOR_SHA256")
        observed_blob = _require_hex40(observed.get("git_blob"), "BLOCK_SELF_CHANGE_BASE_BLOB")
        observed_sha = _require_hex64(observed.get("sha256"), "BLOCK_SELF_CHANGE_BASE_SHA256")
        if expected_blob != observed_blob or expected_sha != observed_sha:
            _fail("BLOCK_SELF_CHANGE_ANCHOR_MISMATCH", path)

    readback = payload.get("execution_readback")
    if not isinstance(readback, Mapping):
        _fail("BLOCK_SELF_CHANGE_EXECUTION_READBACK_SHAPE")
    execution = readback.get("execution")
    if not isinstance(execution, Mapping):
        _fail("BLOCK_SELF_CHANGE_EXECUTION_NOT_FOUND", execution_id)
    if execution.get("execution_id") != execution_id:
        _fail("BLOCK_SELF_CHANGE_EXECUTION_ID_MISMATCH")
    if execution.get("operation_code") != "GITHUB_CONTRACT_GATE_LF":
        _fail("BLOCK_SELF_CHANGE_EXECUTION_OPERATION")
    if execution.get("target_repo") != REPOSITORY:
        _fail("BLOCK_SELF_CHANGE_EXECUTION_REPOSITORY")
    if execution.get("status") != "IN_PROGRESS":
        _fail("BLOCK_SELF_CHANGE_EXECUTION_STATE", str(execution.get("status")))
    manifest = execution.get("manifest")
    if not isinstance(manifest, Mapping):
        _fail("BLOCK_SELF_CHANGE_EXECUTION_MANIFEST")
    pr_number = payload.get("pr_number")
    if not isinstance(pr_number, int) or pr_number < 1:
        _fail("BLOCK_SELF_CHANGE_PR_NUMBER")
    if manifest.get("pr_number") is not None and manifest.get("pr_number") != pr_number:
        _fail("BLOCK_SELF_CHANGE_EXECUTION_PR", str(manifest.get("pr_number")))
    if manifest.get("candidate_code_head") != code_head:
        _fail("BLOCK_SELF_CHANGE_EXECUTION_CODE_HEAD")
    blocker_count = readback.get("blocker_count")
    if blocker_count not in (0, None):
        _fail("BLOCK_SELF_CHANGE_CANONICAL_BLOCKER", str(blocker_count))
    steps = _step_map(readback.get("steps"))
    step = steps.get(terminal_step)
    if not step:
        _fail("BLOCK_SELF_CHANGE_TERMINAL_STEP_MISSING", terminal_step)
    status = str(step.get("status") or "")
    if not status.startswith("PASS"):
        _fail("BLOCK_SELF_CHANGE_TERMINAL_STEP_NOT_PASS", status)
    if not isinstance(step.get("evidence_ref"), str) or not step.get("evidence_ref"):
        _fail("BLOCK_SELF_CHANGE_TERMINAL_EVIDENCE_MISSING")

    return {
        "status": "PASS_SELF_CHANGE_ADMISSION",
        "applicable": True,
        "repository": repository,
        "pr_number": pr_number,
        "base_sha": event_base_sha,
        "head_sha": event_head_sha,
        "candidate_code_head": code_head,
        "protected_touched": protected,
        "receipt_path": receipt_path,
        "execution_id": execution_id,
        "terminal_step": terminal_step,
        "anchor_paths": list(ANCHOR_SURFACES),
    }


def _base_fixture() -> dict[str, Any]:
    base = "a" * 40
    head = "b" * 40
    code = "c" * 40
    wf_blob = "1" * 40
    val_blob = "2" * 40
    wf_sha = "3" * 64
    val_sha = "4" * 64
    receipt_path = f"{RECEIPT_PREFIX}self-change.json"
    changed = [PROTECTED_SURFACES[1], receipt_path]
    return {
        "repository": REPOSITORY,
        "base_branch": BASE_BRANCH,
        "event_base_sha": base,
        "current_main_sha": base,
        "event_head_sha": head,
        "observed_head_sha": head,
        "pr_number": 1200,
        "changed_files": changed,
        "receipt_path": receipt_path,
        "receipt": {
            "receipt_type": "LF_OPERATION_CANDIDATE_RECEIPT",
            "receipt_version": "v1",
            "issued_by": "operation_judge",
            "operation_code": "GITHUB_CONTRACT_GATE_LF",
            "execution_id": "EXEC-SELF-CHANGE-001",
            "result": "PASS_CANDIDATE",
            "all_pre_merge_required_steps_pass": True,
            "pre_merge_terminal_step": "contract_judge",
            "contract_sha": "contract-sha",
            "judge_sha": "judge-sha",
            "source_sha_list": ["source-sha"],
            "target_paths": [PROTECTED_SURFACES[1]],
            "target_blob_sha_by_path": {PROTECTED_SURFACES[1]: "5" * 40},
            "blocking_codes": [],
            "issued_at": "2026-09-26T00:00:00Z",
            "candidate_code_head": code,
            "operation_status_at_issue": "IN_PROGRESS",
            "next_gate": "MERGE_AUTHORIZATION_REQUIRED",
        },
        "code_head_is_ancestor": True,
        "post_code_head_files": [receipt_path],
        "candidate_blob_sha_by_path": {PROTECTED_SURFACES[1]: "5" * 40},
        "anchors": [
            {"path": ANCHOR_SURFACES[0], "expected_git_blob": wf_blob, "expected_sha256": wf_sha, "control_kind": "SOURCE_WORKFLOW"},
            {"path": ANCHOR_SURFACES[1], "expected_git_blob": val_blob, "expected_sha256": val_sha, "control_kind": "VALIDATOR"},
        ],
        "base_observed_anchors": {
            ANCHOR_SURFACES[0]: {"git_blob": wf_blob, "sha256": wf_sha},
            ANCHOR_SURFACES[1]: {"git_blob": val_blob, "sha256": val_sha},
        },
        "execution_readback": {
            "execution": {
                "execution_id": "EXEC-SELF-CHANGE-001",
                "operation_code": "GITHUB_CONTRACT_GATE_LF",
                "target_repo": REPOSITORY,
                "status": "IN_PROGRESS",
                "manifest": {"pr_number": 1200, "candidate_code_head": code},
            },
            "steps": [{"step_id": "contract_judge", "status": "PASS_CLEAN", "evidence_ref": "supabase://judge/1"}],
            "blocker_count": 0,
        },
    }


def self_test() -> dict[str, Any]:
    checks = 0
    result = evaluate_admission({"changed_files": ["docs/x.md"]})
    assert result["status"] == "PASS_NOT_APPLICABLE"
    checks += 1
    fixture = _base_fixture()
    assert evaluate_admission(fixture)["status"] == "PASS_SELF_CHANGE_ADMISSION"
    checks += 1

    def blocked(code: str, mutator) -> None:
        nonlocal checks
        payload = json.loads(json.dumps(_base_fixture()))
        mutator(payload)
        try:
            evaluate_admission(payload)
        except AdmissionError as exc:
            assert exc.code == code, (exc.code, code)
            checks += 1
            return
        raise AssertionError(f"expected {code}")

    blocked("BLOCK_SELF_CHANGE_HEAD_MISMATCH", lambda p: p.__setitem__("observed_head_sha", "d" * 40))
    blocked("BLOCK_SELF_CHANGE_LOOKALIKE_PATH", lambda p: p["changed_files"].append(".github/workflows/lf-contract-check.yaml"))
    blocked("BLOCK_SELF_CHANGE_RECEIPT_BLOB_MISMATCH", lambda p: p["candidate_blob_sha_by_path"].__setitem__(PROTECTED_SURFACES[1], "6" * 40))
    blocked("BLOCK_SELF_CHANGE_EXECUTION_NOT_FOUND", lambda p: p["execution_readback"].__setitem__("execution", None))
    blocked("BLOCK_SELF_CHANGE_EXECUTION_CODE_HEAD", lambda p: p["execution_readback"]["execution"]["manifest"].__setitem__("candidate_code_head", "d" * 40))
    blocked("BLOCK_SELF_CHANGE_GUARD_COCHANGE", lambda p: p["changed_files"].append(GUARD_SURFACES[0]))
    blocked("BLOCK_SELF_CHANGE_GUARD_COCHANGE", lambda p: p["changed_files"].append(GUARD_SURFACES[2]))
    blocked("BLOCK_SELF_CHANGE_ANCHOR_MISMATCH", lambda p: p["base_observed_anchors"][ANCHOR_SURFACES[0]].__setitem__("sha256", "6" * 64))
    return {"status": "PASS_SELF_TEST", "checks": checks}


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_classify = sub.add_parser("classify")
    p_classify.add_argument("--changed-files", required=True)
    p_validate = sub.add_parser("validate")
    p_validate.add_argument("--input", required=True)
    sub.add_parser("self-test")
    args = parser.parse_args()
    try:
        if args.cmd == "classify":
            result = classify_paths(_load_paths(args.changed_files))
        elif args.cmd == "validate":
            result = evaluate_admission(_load_json(args.input))
        else:
            result = self_test()
        print(json.dumps(result, sort_keys=True))
    except AdmissionError as exc:
        print(json.dumps({"status": "BLOCK", "blocking_code": exc.code, "detail": exc.detail}, sort_keys=True))
        raise SystemExit(2)


if __name__ == "__main__":
    main()
