#!/usr/bin/env python3
"""Base-anchored carrier for PASE_MERGE_GATE_V1.

The carrier runs only trusted base-branch code. Candidate Git objects are read as
data for diff/applicability; candidate Python/workflow code is never imported or
executed. For control-system changes, independent qualification is read from the
canonical LF operation ledger and revalidated with trusted-base
PASE_CONTROL_QUALIFICATION_V1 code before the merge policy sees it.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
S28 = HERE.parent / "s28_ci_lane_router"
QUAL_DIR = HERE.parent / "pase_control_qualification"
ROUTE_PATH = S28 / "lf_pase_merge_route_v1.py"
GATE_PATH = HERE / "pase_merge_gate_v1.py"
EMITTER_PATH = S28 / "emit_ci_execution_plan_v2.py"
QUAL_PATH = QUAL_DIR / "pase_control_qualification_v1.py"
HEX40 = __import__("re").compile(r"^[0-9a-f]{40}$")
RESULT_SCHEMA = "lf-pase-merge-gate-carrier-result/v1"
QUAL_EXECUTION_OPERATION = "GITHUB_CONTRACT_GATE_LF"
QUAL_EXECUTION_TARGET_TYPE = "PASE_CONTROL_QUALIFICATION"
QUAL_AUTHORITY = "PASE_CONTROL_QUALIFICATION_V1"
PROJECT_ID = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"


class CarrierError(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _fail(code: str, detail: str = "") -> None:
    raise CarrierError(code, detail)


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        _fail("BLOCK_PASE_MERGE_GATE_TRUSTED_MODULE_LOAD", str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ROUTE = _load(ROUTE_PATH, "lf_pase_merge_route_v1_carrier")
GATE = _load(GATE_PATH, "pase_merge_gate_v1_carrier")
QUAL = _load(QUAL_PATH, "pase_control_qualification_v1_carrier")


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _sha40(value: str, code: str) -> str:
    if not isinstance(value, str) or HEX40.fullmatch(value) is None:
        _fail(code, str(value))
    return value


def validate_identity(*, repository: str, head_repository: str, base_sha: str, head_sha: str, current_main_sha: str, trusted_checkout_sha: str) -> None:
    if not repository or head_repository != repository:
        _fail("BLOCK_PASE_MERGE_GATE_HEAD_REPOSITORY", f"repository={repository} head_repository={head_repository}")
    base_sha = _sha40(base_sha, "BLOCK_PASE_MERGE_GATE_BASE_SHA")
    head_sha = _sha40(head_sha, "BLOCK_PASE_MERGE_GATE_HEAD_SHA")
    current_main_sha = _sha40(current_main_sha, "BLOCK_PASE_MERGE_GATE_CURRENT_MAIN_SHA")
    trusted_checkout_sha = _sha40(trusted_checkout_sha, "BLOCK_PASE_MERGE_GATE_TRUSTED_CHECKOUT_SHA")
    if base_sha != current_main_sha:
        _fail("BLOCK_PASE_MERGE_GATE_STALE_BASE", f"base={base_sha} current_main={current_main_sha}")
    if trusted_checkout_sha != base_sha:
        _fail("BLOCK_PASE_MERGE_GATE_UNTRUSTED_CHECKOUT", f"checkout={trusted_checkout_sha} base={base_sha}")
    if head_sha == base_sha:
        _fail("BLOCK_PASE_MERGE_GATE_EMPTY_RANGE")


def _pg_env() -> dict[str, str]:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    if not password:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_DB_PASSWORD_MISSING")
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": os.environ.get("SUPABASE_POOLER_HOST", POOLER_HOST),
            "PGPORT": "5432",
            "PGUSER": f"postgres.{os.environ.get('SUPABASE_PROJECT_ID', PROJECT_ID)}",
            "PGPASSWORD": password,
            "PGDATABASE": "postgres",
            "PGSSLMODE": "require",
        }
    )
    return env


def _psql_json(sql: str, *, variables: Mapping[str, str]) -> Any:
    cmd = [
        "docker",
        "run",
        "--rm",
        "-i",
        "-e",
        "PGHOST",
        "-e",
        "PGPORT",
        "-e",
        "PGUSER",
        "-e",
        "PGPASSWORD",
        "-e",
        "PGDATABASE",
        "-e",
        "PGSSLMODE",
        "postgres:17.6",
        "psql",
        "-X",
        "-A",
        "-t",
        "-q",
        "-v",
        "ON_ERROR_STOP=1",
    ]
    for key, value in variables.items():
        cmd.extend(["-v", f"{key}={value}"])
    completed = subprocess.run(
        cmd,
        input=sql,
        text=True,
        capture_output=True,
        env=_pg_env(),
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().replace("\n", " | ")[:700]
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_DB_READBACK", detail)
    raw = completed.stdout.strip()
    if not raw:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_DB_EMPTY")
    try:
        return json.loads(raw.splitlines()[-1])
    except json.JSONDecodeError:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_DB_JSON", raw[-500:])


def _qualification_record_from_db(*, repository: str, candidate_id: str, head_sha: str) -> dict[str, Any]:
    sql = r"""
with matches as (
  select e.*
  from public.lf_operation_execution e
  where e.operation_code = 'GITHUB_CONTRACT_GATE_LF'
    and e.target_type = 'PASE_CONTROL_QUALIFICATION'
    and e.target_code = :'candidate_id'
    and e.target_repo = :'repository'
    and e.manifest->>'candidate_head' = :'head_sha'
  order by e.created_at desc
  limit 2
), latest as (
  select execution_id from matches order by created_at desc limit 1
)
select jsonb_build_object(
  'matches', coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from matches m), '[]'::jsonb),
  'steps', coalesce((select jsonb_agg(to_jsonb(s) order by s.step_order) from public.lf_operation_execution_steps s where s.execution_id = (select execution_id from latest)), '[]'::jsonb),
  'blocker_count', (select max(j.blocked_count) from public.v_lf_operation_execution_judge j where j.execution_id = (select execution_id from latest))
)::text;
"""
    value = _psql_json(
        sql,
        variables={
            "repository": repository,
            "candidate_id": candidate_id,
            "head_sha": head_sha,
        },
    )
    if not isinstance(value, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_READBACK_SHAPE")
    return dict(value)


def _qualification_envelope_from_record(
    record: Mapping[str, Any],
    *,
    repository: str,
    base_sha: str,
    head_sha: str,
    candidate_id: str,
) -> dict[str, Any]:
    matches = record.get("matches")
    if not isinstance(matches, list) or len(matches) != 1 or not isinstance(matches[0], Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_CARDINALITY", str(len(matches) if isinstance(matches, list) else "invalid"))
    execution = matches[0]
    if execution.get("operation_code") != QUAL_EXECUTION_OPERATION:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_OPERATION")
    if execution.get("target_type") != QUAL_EXECUTION_TARGET_TYPE:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_TARGET_TYPE")
    if execution.get("target_code") != candidate_id:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_CANDIDATE")
    if execution.get("target_repo") != repository:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_REPOSITORY")
    if execution.get("status") != "COMPLETED":
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_EXECUTION_STATE", str(execution.get("status")))

    manifest = execution.get("manifest")
    if not isinstance(manifest, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_MANIFEST")
    if manifest.get("qualification_authority") != QUAL_AUTHORITY:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_AUTHORITY")
    if manifest.get("independent_qualifier") is not True:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_INDEPENDENCE")
    if manifest.get("candidate_head") != head_sha or manifest.get("base_sha") != base_sha:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_HEAD_BASE_DRIFT")

    packet = manifest.get("qualification_input")
    result = manifest.get("qualification_result")
    if not isinstance(packet, Mapping) or not isinstance(result, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_PAYLOAD")
    if packet.get("repository") != repository:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_INPUT_REPOSITORY")
    if packet.get("candidate_id") != candidate_id:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_INPUT_CANDIDATE")
    if packet.get("base_sha") != base_sha or packet.get("observed_main_sha") != base_sha:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_INPUT_BASE")
    if packet.get("head_sha") != head_sha:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_INPUT_HEAD")
    try:
        verdict = QUAL.validate_result(packet, result)
    except QUAL.QualificationError as exc:
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_VALIDATOR", str(exc))
    if verdict != "CANDIDATE_QUALIFIED":
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_NOT_QUALIFIED", verdict)

    steps = record.get("steps")
    if not isinstance(steps, list):
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_STEPS")
    by_id = {row.get("step_id"): row for row in steps if isinstance(row, Mapping) and isinstance(row.get("step_id"), str)}
    for required_step in ("contract_judge", "report_output"):
        row = by_id.get(required_step)
        if not isinstance(row, Mapping) or not str(row.get("status") or "").startswith("PASS") or not row.get("evidence_ref"):
            _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_TERMINAL_STEP", required_step)
    if record.get("blocker_count") not in (0, None):
        _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_CANONICAL_BLOCKER", str(record.get("blocker_count")))

    result_dict = dict(result)
    return {
        "schema_version": "lf-pase-qualified-evidence/v1",
        "authority": QUAL_AUTHORITY,
        "independent": True,
        "validated": True,
        "execution_id": execution.get("execution_id"),
        "validator_revision": hashlib.sha256(QUAL_PATH.read_bytes()).hexdigest(),
        "result_sha256": _sha256(result_dict),
        "result": result_dict,
    }


def load_live_qualification(*, repository: str, base_sha: str, head_sha: str, candidate_id: str) -> dict[str, Any]:
    record = _qualification_record_from_db(repository=repository, candidate_id=candidate_id, head_sha=head_sha)
    return _qualification_envelope_from_record(
        record,
        repository=repository,
        base_sha=base_sha,
        head_sha=head_sha,
        candidate_id=candidate_id,
    )


def evaluate_plan(*, plan: Mapping[str, Any], head_sha: str, qualification: Mapping[str, Any] | None = None) -> dict[str, Any]:
    if not isinstance(plan, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_PLAN_SHAPE")
    if plan.get("head_sha") not in (None, head_sha):
        _fail("BLOCK_PASE_MERGE_GATE_PLAN_HEAD_DRIFT", f"plan={plan.get('head_sha')} expected={head_sha}")
    changed_paths = plan.get("changed_paths")
    enforcement = plan.get("pase_control_enforcement")
    if not isinstance(changed_paths, list) or not changed_paths:
        _fail("BLOCK_PASE_MERGE_GATE_CHANGED_PATHS")
    if not isinstance(enforcement, Mapping):
        _fail("BLOCK_PASE_MERGE_GATE_ENFORCEMENT_MISSING")

    route = ROUTE.build_merge_route(
        plan=plan,
        enforcement=enforcement,
        head_sha=head_sha,
        changed_paths=changed_paths,
    )
    packet = {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": head_sha,
        "route": route,
        "plan": plan,
        "enforcement": enforcement,
        "qualification": dict(qualification) if qualification is not None else None,
        "control_results": [],
        "diagnostic_results": [],
    }
    try:
        gate_result = GATE.evaluate_merge_gate(packet)
    except GATE.PaseMergeGateError as exc:
        _fail("BLOCK_PASE_MERGE_GATE_POLICY", str(exc))
    return {
        "schema_version": RESULT_SCHEMA,
        "carrier": "PASE_MERGE_GATE_CARRIER_V1",
        "status": "PASS",
        "head_sha": head_sha,
        "mode": route["mode"],
        "candidate_id": route.get("candidate_id"),
        "required_control_ids": route["required_control_ids"],
        "qualification_execution_id": qualification.get("execution_id") if isinstance(qualification, Mapping) else None,
        "gate_result": gate_result,
        "candidate_code_executed": False,
        "external_enforcement_active": False,
    }


def build_live_plan(*, repo_root: Path, base_sha: str, head_sha: str, current_main_sha: str) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="lf-pase-merge-gate-") as td:
        out = Path(td) / "plan.json"
        cmd = [
            sys.executable,
            str(EMITTER_PATH),
            "--repo-root", str(repo_root),
            "--base", base_sha,
            "--head", head_sha,
            "--authority-current-revision", current_main_sha,
            "--event-name", "pull_request",
            "--ref-name", "main",
            "--output-json", str(out),
        ]
        completed = subprocess.run(cmd, cwd=repo_root, text=True, capture_output=True, check=False)
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip().replace("\n", " | ")[:700]
            _fail("BLOCK_PASE_MERGE_GATE_PLAN_EMIT", detail)
        try:
            plan = json.loads(out.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            _fail("BLOCK_PASE_MERGE_GATE_PLAN_READ", type(exc).__name__)
        if not isinstance(plan, Mapping):
            _fail("BLOCK_PASE_MERGE_GATE_PLAN_SHAPE")
        return dict(plan)


def _fixture_qualification(*, base: str, head: str, candidate_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
    packet = {
        "schema_version": "lf-pase-control-qualification/v1",
        "qualification_type": "CONTROL_REFACTOR",
        "repository": "r/x",
        "base_sha": base,
        "head_sha": head,
        "observed_main_sha": base,
        "candidate_id": candidate_id,
        "declared_owner": "LF_GOVERNANCE",
        "scope_paths": [".github/workflows/pase-merge-gate.yml"],
        "owner_local_tests": ["python3 trusted-test.py"],
        "boundary_invariants": ["TRUSTED_BASE_ONLY"],
        "expected_coverage": ["QUALIFICATION_READBACK"],
        "replacement": None,
    }
    checks = []
    for i in range(1, 12):
        status = "NA" if i == 9 else "PASS"
        checks.append({"id": f"Q{i:02d}", "status": status, "evidence": [] if status == "NA" else [f"fixture-q{i:02d}@{head}"]})
    result = {
        "schema_version": "lf-pase-control-qualification-result/v1",
        "candidate_id": candidate_id,
        "base_sha": base,
        "head_sha": head,
        "declared_owner": "LF_GOVERNANCE",
        "checks": checks,
        "external_findings": [],
        "coverage_complete": True,
        "verdict": "CANDIDATE_QUALIFIED",
        "qualified_only": True,
        "activation_authorized": False,
        "cutover_authorized": False,
        "rebind_authorized": False,
        "legacy_retirement_authorized": False,
    }
    return packet, result


def self_test() -> dict[str, Any]:
    checks = 0
    head = "b" * 40
    base = "a" * 40
    validate_identity(repository="r/x", head_repository="r/x", base_sha=base, head_sha=head, current_main_sha=base, trusted_checkout_sha=base)
    checks += 1

    def enforcement(required: list[str], blocking: list[str]) -> dict[str, Any]:
        observe = sorted(set(required) - set(blocking))
        value = {
            "schema_version": "lf-pase-control-enforcement/v1",
            "authority": "CHANGESET_GOVERNANCE_LF_V1",
            "policy_id": "PASE_CONTROL_REPAIR_QUARANTINE_V1",
            "source_plan_sha256": "c" * 64,
            "required_controls": sorted(required),
            "blocking_controls": sorted(blocking),
            "observe_only_controls": observe,
            "repair_window_active": True,
            "manual_diagnostic_execution_allowed": True,
            "observe_only_results_cannot_block_merge": True,
            "no_applicability_reclassification": True,
            "structural_governance_fail_closed": True,
            "silent_reactivation_forbidden": True,
        }
        value["result_sha256"] = ROUTE._sha256(value)
        return value

    normal = {
        "schema_version": "lf-ci-execution-plan/v2",
        "coverage_complete": True,
        "required_controls": ["OBSERVE_ONLY"],
        "plan_sha256": "c" * 64,
        "head_sha": head,
        "changed_paths": ["docs/pase-shadow-probe.md"],
    }
    normal["pase_control_enforcement"] = enforcement(normal["required_controls"], [])
    got = evaluate_plan(plan=normal, head_sha=head)
    assert got["status"] == "PASS" and got["mode"] == "EXECUTION_PLAN" and got["candidate_code_executed"] is False
    checks += 1

    control_change = dict(normal)
    control_change["changed_paths"] = [".github/workflows/pase-merge-gate.yml"]
    try:
        evaluate_plan(plan=control_change, head_sha=head)
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_POLICY" and "QUALIFICATION_MISSING" in exc.detail
        checks += 1
    else:
        raise AssertionError("control-system change must fail closed without independent qualification")

    packet, q_result = _fixture_qualification(base=base, head=head, candidate_id="PASE_MERGE_GATE_V1")
    q_record = {
        "matches": [{
            "execution_id": "EXEC-QUAL-FIXTURE",
            "operation_code": QUAL_EXECUTION_OPERATION,
            "target_type": QUAL_EXECUTION_TARGET_TYPE,
            "target_code": "PASE_MERGE_GATE_V1",
            "target_repo": "r/x",
            "status": "COMPLETED",
            "manifest": {
                "qualification_authority": QUAL_AUTHORITY,
                "independent_qualifier": True,
                "candidate_head": head,
                "base_sha": base,
                "qualification_input": packet,
                "qualification_result": q_result,
            },
        }],
        "steps": [
            {"step_id": "contract_judge", "status": "PASS_CLEAN", "evidence_ref": "fixture://contract-judge"},
            {"step_id": "report_output", "status": "PASS_CLEAN", "evidence_ref": "fixture://report-output"},
        ],
        "blocker_count": 0,
    }
    envelope = _qualification_envelope_from_record(q_record, repository="r/x", base_sha=base, head_sha=head, candidate_id="PASE_MERGE_GATE_V1")
    got = evaluate_plan(plan=control_change, head_sha=head, qualification=envelope)
    assert got["status"] == "PASS" and got["mode"] == "CONTROL_SYSTEM_QUALIFICATION" and got["qualification_execution_id"] == "EXEC-QUAL-FIXTURE"
    checks += 1

    bad_record = json.loads(json.dumps(q_record))
    bad_record["matches"][0]["manifest"]["candidate_head"] = "d" * 40
    try:
        _qualification_envelope_from_record(bad_record, repository="r/x", base_sha=base, head_sha=head, candidate_id="PASE_MERGE_GATE_V1")
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_QUALIFICATION_HEAD_BASE_DRIFT"
        checks += 1
    else:
        raise AssertionError("qualification head drift must block")

    blocker = dict(normal)
    blocker["required_controls"] = ["ACTIVE_BLOCKER"]
    blocker["pase_control_enforcement"] = enforcement(blocker["required_controls"], blocker["required_controls"])
    try:
        evaluate_plan(plan=blocker, head_sha=head)
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_POLICY" and "CONTROL_RESULT_COVERAGE" in exc.detail
        checks += 1
    else:
        raise AssertionError("active blocker must fail closed without canonical PASS evidence")

    try:
        validate_identity(repository="r/x", head_repository="r/x", base_sha=base, head_sha=head, current_main_sha="d" * 40, trusted_checkout_sha=base)
    except CarrierError as exc:
        assert exc.code == "BLOCK_PASE_MERGE_GATE_STALE_BASE"
        checks += 1
    else:
        raise AssertionError("stale base must block")

    return {"status": "PASS_PASE_MERGE_GATE_CARRIER_V1", "checks": checks}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("self-test")
    ev = sub.add_parser("evaluate")
    ev.add_argument("--repo-root", type=Path, default=Path("."))
    ev.add_argument("--repository", required=True)
    ev.add_argument("--head-repository", required=True)
    ev.add_argument("--base-sha", required=True)
    ev.add_argument("--head-sha", required=True)
    ev.add_argument("--current-main-sha", required=True)
    ev.add_argument("--output-json", required=True, type=Path)
    ns = ap.parse_args()
    try:
        if ns.command == "self-test":
            result = self_test()
        else:
            root = ns.repo_root.resolve()
            trusted = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
            validate_identity(
                repository=ns.repository,
                head_repository=ns.head_repository,
                base_sha=ns.base_sha,
                head_sha=ns.head_sha,
                current_main_sha=ns.current_main_sha,
                trusted_checkout_sha=trusted,
            )
            plan = build_live_plan(repo_root=root, base_sha=ns.base_sha, head_sha=ns.head_sha, current_main_sha=ns.current_main_sha)
            route = ROUTE.build_merge_route(
                plan=plan,
                enforcement=plan.get("pase_control_enforcement"),
                head_sha=ns.head_sha,
                changed_paths=plan.get("changed_paths"),
            )
            qualification = None
            if route.get("mode") == "CONTROL_SYSTEM_QUALIFICATION":
                candidate_id = route.get("candidate_id")
                if not isinstance(candidate_id, str) or not candidate_id:
                    _fail("BLOCK_PASE_MERGE_GATE_QUALIFICATION_CANDIDATE")
                qualification = load_live_qualification(
                    repository=ns.repository,
                    base_sha=ns.base_sha,
                    head_sha=ns.head_sha,
                    candidate_id=candidate_id,
                )
            result = evaluate_plan(plan=plan, head_sha=ns.head_sha, qualification=qualification)
            result.update({"repository": ns.repository, "base_sha": ns.base_sha, "trusted_checkout_sha": trusted, "current_main_sha": ns.current_main_sha})
            ns.output_json.parent.mkdir(parents=True, exist_ok=True)
            ns.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
        return 0
    except CarrierError as exc:
        result = {"schema_version": RESULT_SCHEMA, "carrier": "PASE_MERGE_GATE_CARRIER_V1", "status": "BLOCK", "blocking_code": exc.code, "detail": exc.detail, "candidate_code_executed": False, "external_enforcement_active": False}
        if ns.command == "evaluate":
            ns.output_json.parent.mkdir(parents=True, exist_ok=True)
            ns.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
