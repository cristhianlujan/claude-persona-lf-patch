from __future__ import annotations

import copy
import inspect
import json

from sandbox.lf_contract_gate_test.post_pase_router.post_pase_router_v1 import (
    CAPABILITY_ORDER,
    PostPaseRouterBlocked,
    build_post_pase_plan,
    verify_post_pase_plan,
)
import sandbox.lf_contract_gate_test.post_pase_router.post_pase_router_v1 as router_source

MERGE = "b" * 40


def currentness(decision="CURRENT", ready=True, revision=MERGE):
    return {
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": decision,
        "ready": ready,
        "reason": None,
        "evidence_revision": revision,
        "bound_revision": revision,
        "current_revision": revision,
        "receipt_sha256": "a" * 64,
    }


def request(with_authority=True, with_runtime=True):
    authority = []
    if with_authority:
        authority = [
            {
                "check_id": "AUTH-001",
                "adapter_code": "CONTROL_SYSTEM_QUALIFICATION",
                "subject_ref": "supabase://control-system/qualification",
                "authority_ref": "supabase://authority/control-system",
                "expected_source_revision": MERGE,
                "currentness_required": True,
            }
        ]
    runtime = None
    if with_runtime:
        runtime = {
            "effect_operation_code": "REFRESCO_RUNTIME_PERFIL_LF",
            "deployment_execution_id": "DEPLOY-EXEC-001",
            "target_code": "PROFILE_RUNTIME",
            "source_sha": MERGE,
            "release_ref": "release://profile-runtime/001",
            "required_files": [
                {"path": "runtime/app.py", "sha256": "1" * 64},
                {"path": "runtime/config.json", "sha256": "2" * 64},
            ],
        }
    return {
        "target_set_event_id": 19549,
        "post_pase_execution_id": "POST-PASE-EXEC-001",
        "pase_orchestrator_execution_id": "PASE-ORCH-EXEC-001",
        "source_pase_execution_id": "PASE-EXEC-001",
        "repository": "cristhianlujan/claude-persona-lf-patch",
        "target_branch": "main",
        "merge_sha": MERGE,
        "orchestrator_entry": {
            "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
            "orchestrator_execution_id": "PASE-ORCH-EXEC-001",
            "capability_code": "POST_PASE_ROUTER",
        },
        "currentness_receipt": currentness(),
        "declared_paths": [
            {"path": "a/file.py", "kind": "CHANGED"},
            {"path": "docs/anchor.md", "kind": "ANCHOR"},
        ],
        "repository_invariants": ["MAIN_HEAD_EXACT", "MERGE_PR_EXACT"],
        "authority_scopes": authority,
        "runtime_deploy_scope": runtime,
    }


def blocked(mutator, expected):
    req = request()
    mutator(req)
    try:
        build_post_pase_plan(req)
    except PostPaseRouterBlocked as exc:
        assert str(exc) == expected, (str(exc), expected)
        return
    raise AssertionError(f"expected block {expected}")


def main():
    checks = 0

    plan = build_post_pase_plan(request())
    assert verify_post_pase_plan(plan)
    assert tuple(c["capability_code"] for c in plan["controls"]) == CAPABILITY_ORDER
    assert all(c["disposition"] == "REQUIRED" for c in plan["controls"])
    assert plan["control_execution_performed"] is False
    assert plan["control_logic_embedded"] is False
    assert plan["owner_recalculation_performed"] is False
    assert plan["evidence_collection_performed"] is False
    checks += 7

    reduced = build_post_pase_plan(request(with_authority=False, with_runtime=False))
    by_code = {c["capability_code"]: c for c in reduced["controls"]}
    assert by_code["AUTHORITY_READBACK"]["disposition"] == "NOT_APPLICABLE"
    assert by_code["AUTHORITY_READBACK"]["scope"] is None
    assert by_code["RUNTIME_DEPLOY_VERIFICATION"]["disposition"] == "NOT_APPLICABLE"
    assert by_code["RUNTIME_DEPLOY_VERIFICATION"]["scope"] is None
    assert by_code["GITHUB_RECONCILIATION"]["disposition"] == "REQUIRED"
    assert by_code["FINAL_EVIDENCE"]["disposition"] == "REQUIRED"
    assert by_code["CLOSURE_GATE"]["disposition"] == "REQUIRED"
    checks += 7

    one = build_post_pase_plan(request())
    two = build_post_pase_plan(copy.deepcopy(request()))
    assert one["plan_digest"] == two["plan_digest"]
    assert json.dumps(one, sort_keys=True) == json.dumps(two, sort_keys=True)
    checks += 2

    blocked(lambda r: r.update(target_set_event_id=1), "TARGET_SET_EVENT_MISMATCH"); checks += 1
    blocked(lambda r: r.update(orchestrator_entry={}), "ORCHESTRATOR_ENTRY_REQUIRED"); checks += 1
    blocked(lambda r: r["currentness_receipt"].update(ready=False), "CURRENTNESS_NOT_READY"); checks += 1
    blocked(lambda r: r["currentness_receipt"].update(current_revision="c" * 40), "CURRENTNESS_REVISION_MISMATCH"); checks += 1
    blocked(lambda r: r["declared_paths"].append({"path":"a/file.py","kind":"CHANGED"}), "DECLARED_PATH_DUPLICATE"); checks += 1
    blocked(lambda r: r["declared_paths"].append({"path":"src/*.py","kind":"CHANGED"}), "DECLARED_PATH_INVALID"); checks += 1
    blocked(lambda r: r["authority_scopes"].append(copy.deepcopy(r["authority_scopes"][0])), "AUTHORITY_SCOPE_ID_INVALID_OR_DUPLICATE"); checks += 1
    blocked(lambda r: r["runtime_deploy_scope"].update(source_sha="c" * 40), "RUNTIME_SCOPE_SOURCE_SHA_MISMATCH"); checks += 1
    blocked(lambda r: r["runtime_deploy_scope"]["required_files"].append({"path":"runtime/app.py","sha256":"3"*64}), "RUNTIME_REQUIRED_FILE_DUPLICATE"); checks += 1
    blocked(lambda r: r.update(owner="X"), "ROUTER_RESPONSIBILITY_CONTAMINATION"); checks += 1
    blocked(lambda r: r.update(control_execution_request={}), "ROUTER_RESPONSIBILITY_CONTAMINATION"); checks += 1
    blocked(lambda r: r.update(raw_evidence={}), "ROUTER_RESPONSIBILITY_CONTAMINATION"); checks += 1

    tampered = build_post_pase_plan(request())
    tampered["controls"][0]["scope"]["declared_paths"][0]["path"] = "tampered.py"
    try:
        verify_post_pase_plan(tampered)
    except PostPaseRouterBlocked as exc:
        assert str(exc) in {"PLAN_SCOPE_DIGEST_MISMATCH", "PLAN_DIGEST_MISMATCH"}
    else:
        raise AssertionError("expected scope tamper block")
    checks += 1

    tampered = build_post_pase_plan(request())
    tampered["plan_digest"] = "f" * 64
    try:
        verify_post_pase_plan(tampered)
    except PostPaseRouterBlocked as exc:
        assert str(exc) in {"PLAN_SCOPE_DIGEST_CROSSBIND", "PLAN_DIGEST_MISMATCH"}
    else:
        raise AssertionError("expected plan digest tamper block")
    checks += 1

    text = json.dumps(plan, sort_keys=True).lower()
    assert '"owner"' not in text and '"runner"' not in text and '"carrier"' not in text
    source = inspect.getsource(router_source)
    for forbidden_call in ("build_closure_verdict", "build_final_evidence_manifest", "evaluate_authority_readback", "verify_runtime_deploy"):
        assert forbidden_call not in source
    checks += 2

    print(f"PASS_POST_PASE_ROUTER_V1 checks={checks}")


if __name__ == "__main__":
    main()
