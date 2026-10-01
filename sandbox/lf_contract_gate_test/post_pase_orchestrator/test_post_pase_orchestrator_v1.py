from __future__ import annotations

import copy
import hashlib
import json
import uuid
from pathlib import Path

from post_pase_orchestrator_v1 import PostPaseOrchestratorBlocked, digest, execute_post_pase_plan, load_contract

HERE = Path(__file__).resolve().parent
CHECKS = 0


def check(condition: bool, name: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(name)


def sha(seed: str) -> str:
    return hashlib.sha256(seed.encode()).hexdigest()


def plan() -> dict:
    controls = [
        {"capability_code": "GITHUB_RECONCILIATION", "disposition": "REQUIRED", "scope": {"schema_version": "A", "plan_digest": sha("plan")}, "scope_digest": sha("s1")},
        {"capability_code": "AUTHORITY_READBACK", "disposition": "NOT_APPLICABLE", "scope": None, "scope_digest": None},
        {"capability_code": "RUNTIME_DEPLOY_VERIFICATION", "disposition": "NOT_APPLICABLE", "scope": None, "scope_digest": None},
        {"capability_code": "FINAL_EVIDENCE", "disposition": "REQUIRED", "scope": {"schema_version": "B", "plan_digest": sha("plan")}, "scope_digest": sha("s2")},
        {"capability_code": "CLOSURE_GATE", "disposition": "REQUIRED", "scope": {"schema_version": "C", "plan_digest": sha("plan")}, "scope_digest": sha("s3")},
    ]
    return {
        "schema_version": "LF_POST_PASE_PLAN_V1",
        "router_code": "POST_PASE_ROUTER_V1",
        "immutable": True,
        "control_execution_performed": False,
        "control_logic_embedded": False,
        "owner_recalculation_performed": False,
        "evidence_collection_performed": False,
        "plan_digest": sha("plan"),
        "merge_sha": "a" * 40,
        "controls": controls,
    }


def refs() -> dict:
    return {key: {"ref": key, "revision": "v1", "digest": sha(key)} for key in (
        "governance_admin", "owner_runner_carrier", "entry_guard", "evidence_ledger"
    )}


def harness(fail_on: str | None = None):
    calls = {"verify": 0, "bind": [], "exec": [], "sink": [], "validate": [], "build": []}

    def verifier(value):
        calls["verify"] += 1
        return value.get("immutable") is True

    def binding_provider(query):
        code = query["capability_code"]
        calls["bind"].append(code)
        rid = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{query['plan_digest']}:{code}"))
        return {
            "ready": True,
            "capability_code": code,
            "orchestrator_execution_id": query["orchestrator_execution_id"],
            "plan_digest": query["plan_digest"],
            "super_admin": "LF_GOVERNANCE",
            "state": "RESOLVED_CURRENT_CARRIER",
            "runner_ref": f"runner://{code}",
            "carrier": "GITHUB_ACTIONS",
            "source_revision": "v1",
            "dispatch_receipt_id": rid,
            "binding_digest": sha(f"binding:{code}"),
            "authority_refs": refs(),
            "entry_guard_readback": {
                "ready": True,
                "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
                "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
                "orchestrator_execution_id": query["orchestrator_execution_id"],
                "receipt_id": rid,
            },
        }

    def request_builder(**kwargs):
        calls["build"].append(kwargs["capability_code"])
        request = {"schema_version": "LF_CAPABILITY_EXECUTION_REQUEST_V1", **kwargs}
        request["request_digest"] = digest(request)
        return request

    def executor(binding, request):
        code = request["capability_code"]
        calls["exec"].append(code)
        if code == fail_on:
            raise PostPaseOrchestratorBlocked("BLOCK_FAKE_CAPABILITY")
        receipt = {
            "schema_version": "LF_CAPABILITY_EXECUTION_RECEIPT_V1",
            "orchestrator_execution_id": request["orchestrator_execution_id"],
            "consumer_execution_id": request["consumer_execution_id"],
            "capability_code": code,
            "plan_digest": request["plan_digest"],
            "dispatch_receipt_id": request["dispatch_receipt_id"],
            "consumed_request_digest": request["request_digest"],
            "authority_refs": request["authority_refs"],
            "input_digest": request["input_digest"],
            "output_ref": f"output://{code}",
            "output_digest": sha(f"output:{code}"),
            "evidence_refs": [{"ref": f"evidence://{code}", "digest": sha(f"evidence:{code}")}],
            "source_revision": request["source_revision"],
            "self_authorized": False,
            "downstream_authorized": False,
        }
        receipt["receipt_digest"] = digest(receipt)
        return receipt

    def validator(request, receipt):
        calls["validate"].append(receipt["capability_code"])
        if receipt["consumed_request_digest"] != request["request_digest"]:
            raise PostPaseOrchestratorBlocked("BLOCK_FAKE_RECEIPT")

    def sink(record):
        calls["sink"].append(record)
        return True

    return calls, verifier, binding_provider, request_builder, executor, validator, sink


def blocked(mutator, expected_prefix: str) -> None:
    p = plan()
    mutator(p)
    calls, verifier, binding, builder, executor, validator, sink = harness()
    try:
        execute_post_pase_plan(
            p,
            orchestrator_execution_id="orch-1",
            consumer_execution_id="post-1",
            binding_provider=binding,
            capability_executor=executor,
            receipt_sink=sink,
            plan_verifier=verifier,
            request_builder=builder,
            receipt_validator=validator,
        )
    except PostPaseOrchestratorBlocked as exc:
        check(str(exc).startswith(expected_prefix), f"expected {expected_prefix}, got {exc}")
        return
    raise AssertionError(f"expected block {expected_prefix}")


def main() -> None:
    contract = load_contract()
    check(contract["owner"] == "LF_GOVERNANCE", "owner")
    check(contract["dispatch_policy"]["parallel_dispatch"] is False, "no parallel")
    check(contract["dispatch_policy"]["applicability_rediscovery"] is False, "no rediscovery")
    check(contract["persistence_policy"]["new_store_created"] is False, "no new store")

    p = plan()
    calls, verifier, binding, builder, executor, validator, sink = harness()
    result = execute_post_pase_plan(
        p,
        orchestrator_execution_id="orch-1",
        consumer_execution_id="post-1",
        binding_provider=binding,
        capability_executor=executor,
        receipt_sink=sink,
        plan_verifier=verifier,
        request_builder=builder,
        receipt_validator=validator,
    )
    expected = ["GITHUB_RECONCILIATION", "FINAL_EVIDENCE", "CLOSURE_GATE"]
    check(calls["verify"] == 1, "verify once")
    check(calls["bind"] == expected, "binding exact required set")
    check(calls["build"] == expected, "build exact required set")
    check(calls["exec"] == expected, "execute exact required set")
    check(calls["validate"] == expected, "validate exact required set")
    check([x["capability_code"] for x in calls["sink"]] == expected, "persist exact required set")
    check(result["required_capability_count"] == 3, "required count")
    check(result["persisted_receipt_count"] == 3, "receipt count")
    check(result["skipped_not_applicable"] == ["AUTHORITY_READBACK", "RUNTIME_DEPLOY_VERIFICATION"], "skip N/A")
    check(result["applicability_rediscovered"] is False, "no applicability rediscovery result")
    check(result["owner_runner_carrier_recalculated"] is False, "no owner recalculation")
    check(result["control_logic_embedded"] is False, "no control logic")
    check(result["parallel_dispatch_performed"] is False, "no parallel result")
    check(result["self_authorized"] is False, "no self authorization")
    check(len(result["orchestration_receipt_digest"]) == 64, "result digest")
    check(calls["sink"][1]["receipt"]["capability_code"] == "FINAL_EVIDENCE", "evidence stays receipt")
    check(calls["sink"][2]["receipt"]["capability_code"] == "CLOSURE_GATE", "closure stays capability")
    check(calls["sink"][1]["request_digest"] == calls["sink"][1]["receipt"]["consumed_request_digest"], "request crossbind")

    first_input = calls["sink"][0]["receipt"]["input_digest"]
    second_input = calls["sink"][1]["receipt"]["input_digest"]
    check(first_input != second_input, "receipt chain changes next input")

    blocked(lambda x: x.update({"immutable": False}), "BLOCK_PLAN_NOT_IMMUTABLE")
    blocked(lambda x: x.update({"plan_digest": "bad"}), "BLOCK_PLAN_DIGEST")
    blocked(lambda x: x["controls"].append({"capability_code": "X", "disposition": "MAYBE", "scope": None, "scope_digest": None}), "BLOCK_CONTROL_DISPOSITION")
    blocked(lambda x: x["controls"][1].update({"scope": {"x": 1}}), "BLOCK_NOT_APPLICABLE_SCOPE")

    p2 = plan()
    calls2, verifier2, binding2, builder2, executor2, validator2, sink2 = harness(fail_on="FINAL_EVIDENCE")
    try:
        execute_post_pase_plan(
            p2,
            orchestrator_execution_id="orch-2",
            consumer_execution_id="post-2",
            binding_provider=binding2,
            capability_executor=executor2,
            receipt_sink=sink2,
            plan_verifier=verifier2,
            request_builder=builder2,
            receipt_validator=validator2,
        )
    except PostPaseOrchestratorBlocked as exc:
        check(str(exc) == "BLOCK_FAKE_CAPABILITY", "fail closed reason")
    else:
        raise AssertionError("expected capability failure")
    check(calls2["exec"] == ["GITHUB_RECONCILIATION", "FINAL_EVIDENCE"], "stop on first failure")
    check(len(calls2["sink"]) == 1, "do not persist failed receipt")
    check("CLOSURE_GATE" not in calls2["bind"], "no downstream bind after failure")

    p3 = plan()
    calls3, verifier3, binding3, builder3, executor3, validator3, sink3 = harness()
    def bad_binding(query):
        row = binding3(query)
        row["state"] = "BLOCK_NOT_CUTOVER"
        return row
    try:
        execute_post_pase_plan(
            p3,
            orchestrator_execution_id="orch-3",
            consumer_execution_id="post-3",
            binding_provider=bad_binding,
            capability_executor=executor3,
            receipt_sink=sink3,
            plan_verifier=verifier3,
            request_builder=builder3,
            receipt_validator=validator3,
        )
    except PostPaseOrchestratorBlocked as exc:
        check(str(exc) == "BLOCK_BINDING_STATE", "unresolved binding blocks")
    else:
        raise AssertionError("expected binding block")
    check(calls3["exec"] == [], "no execution on binding block")

    print(f"PASS_POST_PASE_ORCHESTRATOR_V1 checks={CHECKS}")


if __name__ == "__main__":
    main()
