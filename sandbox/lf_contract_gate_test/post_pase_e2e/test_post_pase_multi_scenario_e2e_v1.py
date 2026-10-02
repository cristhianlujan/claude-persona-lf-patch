from __future__ import annotations

import hashlib
import uuid

from sandbox.lf_contract_gate_test.capability_execution_contract.capability_execution_contract_v1 import (
    build_receipt,
    digest as execution_digest,
)
from sandbox.lf_contract_gate_test.closure_gate.closure_gate_v1 import (
    build_closure_verdict,
    closure_request_digest,
)
from sandbox.lf_contract_gate_test.post_pase_final_evidence.final_evidence_v1 import (
    build_final_evidence_manifest,
    controls_digest,
    outcome_binding_digest,
)
from sandbox.lf_contract_gate_test.post_pase_orchestrator.post_pase_orchestrator_v1 import (
    PostPaseOrchestratorBlocked,
    execute_post_pase_plan,
)
from sandbox.lf_contract_gate_test.post_pase_router.post_pase_router_v1 import (
    PostPaseRouterBlocked,
    build_post_pase_plan,
    verify_post_pase_plan,
)

MERGE_SHA = "b" * 40
DOMAIN_CONTROLS = (
    "GITHUB_RECONCILIATION",
    "AUTHORITY_READBACK",
    "RUNTIME_DEPLOY_VERIFICATION",
)
TERMINAL_CONTROLS = ("FINAL_EVIDENCE", "CLOSURE_GATE")
CHECKS = 0


def check(condition: bool, name: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(name)


def sha(seed: str) -> str:
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


def currentness(*, stale: bool = False) -> dict:
    revision = "c" * 40 if stale else MERGE_SHA
    return {
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": "STALE" if stale else "CURRENT",
        "ready": not stale,
        "reason": "STALE_EVIDENCE" if stale else None,
        "evidence_revision": revision,
        "bound_revision": MERGE_SHA,
        "current_revision": revision,
        "receipt_sha256": sha("currentness-stale" if stale else "currentness-current"),
    }


def authority_scope() -> list[dict]:
    return [
        {
            "check_id": "AUTH-DB-001",
            "adapter_code": "CONTROL_SYSTEM_QUALIFICATION",
            "subject_ref": "supabase://control-system/qualification",
            "authority_ref": "supabase://authority/control-system",
            "expected_source_revision": MERGE_SHA,
            "currentness_required": True,
        }
    ]


def runtime_scope() -> dict:
    return {
        "effect_operation_code": "REFRESCO_RUNTIME_PERFIL_LF",
        "deployment_execution_id": "DEPLOY-EXEC-L6-024",
        "target_code": "PROFILE_RUNTIME",
        "source_sha": MERGE_SHA,
        "release_ref": "release://profile-runtime/l6-024",
        "required_files": [
            {"path": "runtime/app.py", "sha256": sha("runtime-app")},
            {"path": "runtime/config.json", "sha256": sha("runtime-config")},
        ],
    }


def router_request(
    scenario: str,
    *,
    with_authority: bool,
    with_runtime: bool,
    stale: bool = False,
) -> dict:
    declared = {
        "DOCS_ONLY": [{"path": "docs/post-pase.md", "kind": "CHANGED"}],
        "DB": [{"path": "supabase/migrations/20261001000000_e2e.sql", "kind": "CHANGED"}],
        "PROFILE_RUNTIME": [{"path": "runtime/profile.py", "kind": "CHANGED"}],
        "MIXED": [
            {"path": "runtime/profile.py", "kind": "CHANGED"},
            {"path": "supabase/migrations/20261001000000_e2e.sql", "kind": "CHANGED"},
        ],
        "FAILURE": [
            {"path": "runtime/profile.py", "kind": "CHANGED"},
            {"path": "supabase/migrations/20261001000000_e2e.sql", "kind": "CHANGED"},
        ],
        "STALE_EVIDENCE": [{"path": "docs/stale-evidence.md", "kind": "CHANGED"}],
        "WAIVER": [{"path": "supabase/migrations/20261001000000_waiver.sql", "kind": "CHANGED"}],
    }[scenario]
    orch = f"PASE-ORCH-L6-024-{scenario}"
    return {
        "target_set_event_id": 19549,
        "post_pase_execution_id": f"POST-PASE-L6-024-{scenario}",
        "pase_orchestrator_execution_id": orch,
        "source_pase_execution_id": f"PASE-L6-024-{scenario}",
        "repository": "cristhianlujan/claude-persona-lf-patch",
        "target_branch": "main",
        "merge_sha": MERGE_SHA,
        "orchestrator_entry": {
            "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
            "orchestrator_execution_id": orch,
            "capability_code": "POST_PASE_ROUTER",
        },
        "currentness_receipt": currentness(stale=stale),
        "declared_paths": declared,
        "repository_invariants": ["MAIN_HEAD_EXACT", "MERGE_PR_EXACT"],
        "authority_scopes": authority_scope() if with_authority else [],
        "runtime_deploy_scope": runtime_scope() if with_runtime else None,
    }


def authority_refs(scenario: str) -> dict:
    return {
        key: {
            "ref": f"authority://{key}",
            "revision": "v1",
            "digest": sha(f"{scenario}:{key}"),
        }
        for key in ("governance_admin", "owner_runner_carrier", "entry_guard", "evidence_ledger")
    }


def binding_provider(scenario: str):
    def provider(query: dict) -> dict:
        code = query["capability_code"]
        rid = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{scenario}:{query['plan_digest']}:{code}"))
        return {
            "ready": True,
            "capability_code": code,
            "orchestrator_execution_id": query["orchestrator_execution_id"],
            "plan_digest": query["plan_digest"],
            "super_admin": "LF_GOVERNANCE",
            "state": "RESOLVED_CURRENT_CARRIER",
            "runner_ref": f"runner://post-pase-e2e/{code}",
            "carrier": "DETERMINISTIC_PYTHON_E2E",
            "source_revision": MERGE_SHA,
            "dispatch_receipt_id": rid,
            "binding_digest": sha(f"binding:{scenario}:{code}"),
            "authority_refs": authority_refs(scenario),
            "entry_guard_readback": {
                "ready": True,
                "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
                "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
                "orchestrator_execution_id": query["orchestrator_execution_id"],
                "receipt_id": rid,
            },
        }

    return provider


def domain_plan_controls(plan: dict) -> list[dict]:
    return [
        {"control_code": row["capability_code"], "disposition": row["disposition"]}
        for row in plan["controls"]
        if row["capability_code"] in DOMAIN_CONTROLS
    ]


def typed_receipt(receipt_id: str, receipt_sha256: str, outcome: str) -> dict:
    return {
        "schema_version": "LF_TYPED_CONTROL_TERMINAL_RECEIPT_V1",
        "validation_decision": "TYPED_RECEIPT_VALIDATED",
        "receipt_id": receipt_id,
        "receipt_sha256": receipt_sha256,
        "terminal_outcome": outcome,
        "outcome_binding_sha256": outcome_binding_digest(receipt_id, receipt_sha256, outcome),
    }


def run_scenario(
    scenario: str,
    *,
    with_authority: bool,
    with_runtime: bool,
    expected_required: list[str],
    domain_outcomes: dict[str, str] | None = None,
    fail_on: str | None = None,
    waiver_control: str | None = None,
) -> dict:
    req = router_request(
        scenario,
        with_authority=with_authority,
        with_runtime=with_runtime,
    )
    plan = build_post_pase_plan(req)
    check(verify_post_pase_plan(plan) is True, f"{scenario}: plan verifies")
    required = [row["capability_code"] for row in plan["controls"] if row["disposition"] == "REQUIRED"]
    check(required == expected_required, f"{scenario}: minimal required set")
    check(len(required) == len(set(required)), f"{scenario}: no duplicate planned controls")

    state: dict = {
        "domain_receipts": {},
        "final_manifest": None,
        "closure_verdict": None,
        "exec_order": [],
        "sink": [],
    }
    outcomes = domain_outcomes or {}
    plan_controls = domain_plan_controls(plan)
    plan_id = f"POST-PASE-PLAN-L6-024-{scenario}"
    orch_id = f"POST-PASE-ORCH-L6-024-{scenario}"
    consumer_id = f"POST-PASE-CONSUMER-L6-024-{scenario}"

    def executor(_binding: dict, request: dict) -> dict:
        code = request["capability_code"]
        state["exec_order"].append(code)
        if code == fail_on:
            raise PostPaseOrchestratorBlocked(f"BLOCK_E2E_INJECTED_FAILURE:{code}")

        if code in DOMAIN_CONTROLS:
            outcome = outcomes.get(code, "PASS")
            rid = str(uuid.uuid5(uuid.NAMESPACE_URL, f"domain:{scenario}:{code}"))
            receipt_sha = sha(f"domain-receipt:{scenario}:{code}:{outcome}")
            state["domain_receipts"][code] = {
                "control_code": code,
                "receipt_id": rid,
                "receipt_sha256": receipt_sha,
                "execution_id": f"CTRL-L6-024-{scenario}-{code}",
                "capability_code": code,
                "gate_code": code,
                "source_head_sha": MERGE_SHA,
                "subject_ref": f"e2e://{scenario}/{code.lower()}",
                "subject_sha256": sha(f"subject:{scenario}:{code}"),
                "authority_ref": f"authority://{code.lower()}",
                "resolver_id": "TRUSTED_RESOLVER_V1",
                "verification_state": "VERIFIED",
                "plan_digest": plan["plan_digest"],
                "typed_receipt": typed_receipt(rid, receipt_sha, outcome),
            }
            output = {
                "schema_version": "LF_POST_PASE_E2E_DOMAIN_OUTPUT_V1",
                "control_code": code,
                "terminal_outcome": outcome,
                "receipt_sha256": receipt_sha,
            }
        elif code == "FINAL_EVIDENCE":
            final_request = {
                "post_pase_execution_id": plan["post_pase_execution_id"],
                "orchestrator_execution_id": orch_id,
                "plan_id": plan_id,
                "plan_digest": plan["plan_digest"],
                "merge_sha": MERGE_SHA,
                "orchestrator_entry": {
                    "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
                    "orchestrator_execution_id": orch_id,
                    "plan_digest": plan["plan_digest"],
                    "capability_code": "FINAL_EVIDENCE",
                },
                "controls": plan_controls,
                "plan_authority_receipt": {
                    "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
                    "decision": "AUTHORIZED_DELTA",
                    "plan_id": plan_id,
                    "plan_digest": plan["plan_digest"],
                    "controls_digest": controls_digest(plan_controls),
                },
                "receipts": [
                    state["domain_receipts"][row["control_code"]]
                    for row in plan_controls
                    if row["disposition"] == "REQUIRED"
                ],
            }
            state["final_manifest"] = build_final_evidence_manifest(final_request)
            output = state["final_manifest"]
        elif code == "CLOSURE_GATE":
            closure_request = {
                "post_pase_execution_id": plan["post_pase_execution_id"],
                "orchestrator_execution_id": orch_id,
                "plan_id": plan_id,
                "plan_digest": plan["plan_digest"],
                "merge_sha": MERGE_SHA,
                "orchestrator_entry": {
                    "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
                    "orchestrator_execution_id": orch_id,
                    "plan_digest": plan["plan_digest"],
                    "capability_code": "CLOSURE_GATE",
                },
                "plan_controls": plan_controls,
                "plan_authority_receipt": {
                    "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
                    "decision": "AUTHORIZED_DELTA",
                    "plan_id": plan_id,
                    "plan_digest": plan["plan_digest"],
                    "controls_digest": controls_digest(plan_controls),
                },
                "final_evidence_manifest": state["final_manifest"],
                "waiver_receipts": [],
            }
            if waiver_control:
                request_digest = closure_request_digest(closure_request, state["final_manifest"])
                closure_request["waiver_receipts"] = [
                    {
                        "schema_version": "LF_WAIVER_AUTHORITY_RECEIPT_V1",
                        "decision": "WAIVER_AUTHORIZED",
                        "post_pase_execution_id": plan["post_pase_execution_id"],
                        "control_id": waiver_control,
                        "plan_digest": plan["plan_digest"],
                        "merge_sha": MERGE_SHA,
                        "consumer_request_digest": request_digest,
                        "grant_sha256": sha(f"waiver-grant:{scenario}:{waiver_control}"),
                        "consumption_readback_digest": sha(f"waiver-consume:{scenario}:{waiver_control}"),
                    }
                ]
            state["closure_verdict"] = build_closure_verdict(closure_request)
            output = state["closure_verdict"]
        else:
            raise AssertionError(f"unexpected capability: {code}")

        return build_receipt(
            request,
            output_ref=f"e2e://{scenario}/output/{code}",
            output_digest=execution_digest(output),
            evidence_refs=[
                {
                    "ref": f"e2e://{scenario}/evidence/{code}",
                    "digest": sha(f"evidence:{scenario}:{code}"),
                }
            ],
        )

    def sink(record: dict) -> bool:
        state["sink"].append(record)
        return True

    try:
        result = execute_post_pase_plan(
            plan,
            orchestrator_execution_id=orch_id,
            consumer_execution_id=consumer_id,
            binding_provider=binding_provider(scenario),
            capability_executor=executor,
            receipt_sink=sink,
        )
    except PostPaseOrchestratorBlocked:
        if fail_on is None:
            raise
        check(state["exec_order"][-1] == fail_on, f"{scenario}: failed on injected control")
        check(fail_on not in [row["capability_code"] for row in state["sink"]], f"{scenario}: failed receipt not persisted")
        check("FINAL_EVIDENCE" not in state["exec_order"], f"{scenario}: no downstream final evidence")
        check("CLOSURE_GATE" not in state["exec_order"], f"{scenario}: no downstream closure")
        return state

    check(state["exec_order"] == expected_required, f"{scenario}: exact execution order")
    check(len(state["exec_order"]) == len(set(state["exec_order"])), f"{scenario}: zero duplicate executions")
    check(result["required_capability_count"] == len(expected_required), f"{scenario}: required count")
    check(result["persisted_receipt_count"] == len(expected_required), f"{scenario}: receipt count")
    check([row["capability_code"] for row in state["sink"]] == expected_required, f"{scenario}: sink exact set")
    for row in state["sink"]:
        receipt = row["receipt"]
        check(receipt["orchestrator_execution_id"] == orch_id, f"{scenario}: orchestrator lineage")
        check(receipt["consumer_execution_id"] == consumer_id, f"{scenario}: consumer lineage")
        check(receipt["plan_digest"] == plan["plan_digest"], f"{scenario}: plan crossbind")
        check(row["request_digest"] == receipt["consumed_request_digest"], f"{scenario}: request crossbind")
    check(state["final_manifest"] is not None, f"{scenario}: final evidence materialized")
    check(state["closure_verdict"] is not None, f"{scenario}: closure evaluated")
    return state


def main() -> None:
    run_scenario(
        "DOCS_ONLY",
        with_authority=False,
        with_runtime=False,
        expected_required=["GITHUB_RECONCILIATION", "FINAL_EVIDENCE", "CLOSURE_GATE"],
    )
    run_scenario(
        "DB",
        with_authority=True,
        with_runtime=False,
        expected_required=["GITHUB_RECONCILIATION", "AUTHORITY_READBACK", "FINAL_EVIDENCE", "CLOSURE_GATE"],
    )
    run_scenario(
        "PROFILE_RUNTIME",
        with_authority=False,
        with_runtime=True,
        expected_required=["GITHUB_RECONCILIATION", "RUNTIME_DEPLOY_VERIFICATION", "FINAL_EVIDENCE", "CLOSURE_GATE"],
    )
    mixed = run_scenario(
        "MIXED",
        with_authority=True,
        with_runtime=True,
        expected_required=[
            "GITHUB_RECONCILIATION",
            "AUTHORITY_READBACK",
            "RUNTIME_DEPLOY_VERIFICATION",
            "FINAL_EVIDENCE",
            "CLOSURE_GATE",
        ],
    )
    check(mixed["closure_verdict"]["verdict"] == "PASS", "MIXED: terminal closure")

    failure = run_scenario(
        "FAILURE",
        with_authority=True,
        with_runtime=True,
        expected_required=[
            "GITHUB_RECONCILIATION",
            "AUTHORITY_READBACK",
            "RUNTIME_DEPLOY_VERIFICATION",
            "FINAL_EVIDENCE",
            "CLOSURE_GATE",
        ],
        fail_on="AUTHORITY_READBACK",
    )
    check(failure["exec_order"] == ["GITHUB_RECONCILIATION", "AUTHORITY_READBACK"], "FAILURE: stops immediately")
    check(len(failure["sink"]) == 1, "FAILURE: only prior receipt persisted")

    stale_req = router_request(
        "STALE_EVIDENCE",
        with_authority=False,
        with_runtime=False,
        stale=True,
    )
    try:
        build_post_pase_plan(stale_req)
    except PostPaseRouterBlocked as exc:
        check(str(exc) == "CURRENTNESS_NOT_READY", "STALE_EVIDENCE: router fails closed")
    else:
        raise AssertionError("STALE_EVIDENCE: expected router block")

    waiver = run_scenario(
        "WAIVER",
        with_authority=True,
        with_runtime=False,
        expected_required=["GITHUB_RECONCILIATION", "AUTHORITY_READBACK", "FINAL_EVIDENCE", "CLOSURE_GATE"],
        domain_outcomes={"AUTHORITY_READBACK": "FAIL"},
        waiver_control="AUTHORITY_READBACK",
    )
    check(waiver["closure_verdict"]["verdict"] == "WAIVED", "WAIVER: governed waiver verdict")
    check(waiver["closure_verdict"]["terminal_status"] == "CLOSED", "WAIVER: closure allowed")
    check(waiver["closure_verdict"]["waived_controls"] == ["AUTHORITY_READBACK"], "WAIVER: exact control only")

    print(f"PASS_POST_PASE_MULTI_SCENARIO_E2E_V1 scenarios=7 checks={CHECKS}")


if __name__ == "__main__":
    main()
