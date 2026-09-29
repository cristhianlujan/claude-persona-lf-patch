#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

OLD_SHA = "6950b3f67b68db090de1de9fb421a61f6a823057"
NEW_SHA = "34b57b4ba1101b866822091aba1f36c9ab709a1a"
REL = "sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_v1.py"
NEW_PATH = Path(__file__).resolve().parents[2] / "pase_merge_gate" / "pase_merge_gate_v1.py"
HEAD = "a" * 40
PLAN_DIGEST = "d" * 64
ROUTE_REV = "b" * 64
VALIDATOR_REV = "c" * 64


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL_REPLAY_LOAD:{name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_old():
    source = subprocess.check_output(["git", "show", f"{OLD_SHA}:{REL}"], text=True)
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(source)
        path = Path(fh.name)
    return load_module("pase_merge_gate_old", path)


def plan(required, *, coverage=True):
    return {
        "schema_version": "lf-ci-execution-plan/v2",
        "coverage_complete": coverage,
        "required_controls": sorted(required),
        "plan_sha256": PLAN_DIGEST,
    }


def route(mode, required, candidate_id=None):
    return {
        "schema_version": "lf-pase-merge-route/v1",
        "authority": "CHANGESET_GOVERNANCE_LF_V1",
        "mode": mode,
        "head_sha": HEAD,
        "source_revision": ROUTE_REV,
        "required_control_ids": sorted(required),
        "candidate_id": candidate_id,
    }


def control_result(cid, verdict="PASS"):
    return {
        "control_id": cid,
        "head_sha": HEAD,
        "verdict": verdict,
        "authority": f"{cid}_OWNER",
        "evidence_sha256": "e" * 64,
    }


def qualification_result(*, head_sha=HEAD):
    return {
        "schema_version": "lf-pase-control-qualification-result/v1",
        "candidate_id": "PASE_ORCHESTRATOR_V1",
        "base_sha": "8bb18f9521702b958193d92640a08d04a53b1b85",
        "head_sha": head_sha,
        "declared_owner": "LF_GOVERNANCE",
        "checks": [{"id": f"Q{i:02d}", "status": "PASS", "evidence": [f"e{i}@{head_sha}"]} for i in range(1, 12)],
        "external_findings": [],
        "coverage_complete": True,
        "verdict": "CANDIDATE_QUALIFIED",
        "qualified_only": True,
        "activation_authorized": False,
        "cutover_authorized": False,
        "rebind_authorized": False,
        "legacy_retirement_authorized": False,
    }


def qualification_envelope(*, result=None):
    result = qualification_result() if result is None else result
    return {
        "schema_version": "lf-pase-qualified-evidence/v1",
        "authority": "PASE_CONTROL_QUALIFICATION_V1",
        "independent": True,
        "validated": True,
        "validator_revision": VALIDATOR_REV,
        "result_sha256": digest(result),
        "result": result,
    }


def enforcement(required, blocking):
    required = sorted(required)
    blocking = sorted(blocking)
    observe = sorted(set(required) - set(blocking))
    value = {
        "schema_version": "lf-pase-control-enforcement/v1",
        "authority": "CHANGESET_GOVERNANCE_LF_V1",
        "policy_id": "PASE_CONTROL_REPAIR_QUARANTINE_V1",
        "source_plan_sha256": PLAN_DIGEST,
        "required_controls": required,
        "blocking_controls": blocking,
        "observe_only_controls": observe,
        "repair_window_active": True,
        "manual_diagnostic_execution_allowed": True,
        "observe_only_results_cannot_block_merge": True,
        "no_applicability_reclassification": True,
        "structural_governance_fail_closed": True,
        "silent_reactivation_forbidden": True,
    }
    value["result_sha256"] = digest(value)
    return value


def old_exec(required, verdicts=None, *, coverage=True):
    verdicts = verdicts or {}
    return {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": HEAD,
        "route": route("EXECUTION_PLAN", required),
        "plan": plan(required, coverage=coverage),
        "qualification": None,
        "control_results": [control_result(cid, verdicts.get(cid, "PASS")) for cid in sorted(required)],
    }


def new_exec(required, blocking, verdicts=None, diagnostics=None, *, coverage=True):
    verdicts = verdicts or {}
    diagnostics = diagnostics or {}
    observe = sorted(set(required) - set(blocking))
    return {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": HEAD,
        "route": route("EXECUTION_PLAN", blocking),
        "plan": plan(required, coverage=coverage),
        "enforcement": enforcement(required, blocking),
        "qualification": None,
        "control_results": [control_result(cid, verdicts.get(cid, "PASS")) for cid in sorted(blocking)],
        "diagnostic_results": [
            {"control_id": cid, "head_sha": HEAD, "verdict": diagnostics.get(cid, "PASS")}
            for cid in observe
        ],
    }


def old_qualification(*, qual_head=HEAD):
    required = ["E16_GOVERNANCE", "PROFILE_RUNTIME_V3"]
    result = qualification_result(head_sha=qual_head)
    return {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": HEAD,
        "route": route("CONTROL_SYSTEM_QUALIFICATION", [], "PASE_ORCHESTRATOR_V1"),
        "plan": plan(required),
        "qualification": qualification_envelope(result=result),
        "control_results": [],
    }


def new_qualification(*, qual_head=HEAD):
    required = ["E16_GOVERNANCE", "PROFILE_RUNTIME_V3"]
    result = qualification_result(head_sha=qual_head)
    return {
        "schema_version": "lf-pase-merge-gate-input/v1",
        "head_sha": HEAD,
        "route": route("CONTROL_SYSTEM_QUALIFICATION", [], "PASE_ORCHESTRATOR_V1"),
        "plan": plan(required),
        "enforcement": enforcement(required, []),
        "qualification": qualification_envelope(result=result),
        "control_results": [],
        "diagnostic_results": [
            {"control_id": cid, "head_sha": HEAD, "verdict": "FAIL"} for cid in required
        ],
    }


def outcome(module, packet):
    try:
        result = module.evaluate_merge_gate(packet)
        return {"class": "PASS", "detail": result.get("verdict")}
    except module.PaseMergeGateError as exc:
        return {"class": "BLOCK", "detail": str(exc)}


def assert_equivalent(name, old_mod, new_mod, old_packet, new_packet):
    old = outcome(old_mod, old_packet)
    new = outcome(new_mod, new_packet)
    assert old["class"] == new["class"], (name, old, new)
    print(canonical({"scenario": name, "classification": "EQUIVALENT", "old": old, "new": new}))


def main():
    old = load_old()
    new = load_module("pase_merge_gate_new", NEW_PATH)

    assert_equivalent(
        "all_active_blockers_pass",
        old,
        new,
        old_exec(["CONTROL_A", "CONTROL_B"]),
        new_exec(["CONTROL_A", "CONTROL_B"], ["CONTROL_A", "CONTROL_B"]),
    )
    assert_equivalent(
        "active_blocker_fail",
        old,
        new,
        old_exec(["CONTROL_A", "CONTROL_B"], {"CONTROL_A": "FAIL"}),
        new_exec(["CONTROL_A", "CONTROL_B"], ["CONTROL_A", "CONTROL_B"], {"CONTROL_A": "FAIL"}),
    )
    assert_equivalent(
        "control_system_qualification_pass",
        old,
        new,
        old_qualification(),
        new_qualification(),
    )
    assert_equivalent(
        "plan_coverage_fail_closed",
        old,
        new,
        old_exec(["CONTROL_A"], coverage=False),
        new_exec(["CONTROL_A"], ["CONTROL_A"], coverage=False),
    )
    assert_equivalent(
        "qualification_head_drift_fail_closed",
        old,
        new,
        old_qualification(qual_head="1" * 40),
        new_qualification(qual_head="1" * 40),
    )

    old_delta = outcome(old, old_exec(["CONTROL_A", "CONTROL_B"], {"CONTROL_B": "FAIL"}))
    new_delta = outcome(
        new,
        new_exec(
            ["CONTROL_A", "CONTROL_B"],
            ["CONTROL_A"],
            {"CONTROL_A": "PASS"},
            {"CONTROL_B": "FAIL"},
        ),
    )
    assert old_delta["class"] == "BLOCK", old_delta
    assert new_delta["class"] == "PASS", new_delta
    print(canonical({
        "scenario": "observe_only_legacy_failure",
        "classification": "INTENTIONAL_DELTA_REPAIR_QUARANTINE",
        "old": old_delta,
        "new": new_delta,
    }))

    print(
        "PASS_PASE_MERGE_GATE_REPAIR_ENFORCEMENT_REPLAY_V1 "
        f"old={OLD_SHA} new={NEW_SHA} equivalent=5 intentional_delta=1"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
