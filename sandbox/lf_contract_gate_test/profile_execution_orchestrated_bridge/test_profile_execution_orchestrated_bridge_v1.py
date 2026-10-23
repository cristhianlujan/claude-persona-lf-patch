import copy
import hashlib
import json

from profile_execution_orchestrated_bridge_v1 import (
    build_pre_dispatch_plan,
    finalize_after_guard,
)


def canonical_digest(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def seed() -> dict:
    return {
        "task_id": "TASK-J02-001",
        "operation_code": "BUILD_INTEGRAL_STORY_CREATOR_LF",
        "execution_id": "EXEC-STORY-001",
        "step_id": "SCREEN_DECOMPOSITION",
        "worker_binding": {
            "resolution_mode": "ORCHESTRATOR_RESOLVED",
            "worker_ref": "PERFIL-SCREEN-DECOMPOSER-LF",
            "worker_kind": "PROFILE",
            "binding_authority_ref": "supabase://public/lf_activos+ACT-0001+CURRENTNESS_AUTHORITY",
            "binding_revision": "rev-1",
            "binding_digest": "b" * 64,
        },
    }


def pre(**updates):
    args = {
        "orchestrator_execution_id": "EXEC-SKILL-ORCH-001",
        "request_id": "11111111-2222-4333-8444-555555555555",
        "profile_code": "PERFIL-SCREEN-DECOMPOSER-LF",
        "profile_slug": "screen_decomposer_lf",
        "target_repo": "cristhianlujan/claude-persona-lf-patch",
        "profile_source_paths": ["skills/creating-integral-user-stories/perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md"],
        "profile_source_digest": "sha256:" + "e" * 64,
        "source_revision": "a" * 40,
        "task_packet_seed": seed(),
        "parent_plan_digest": "c" * 64,
        "expected_capability_manifest_sha256": "d" * 64,
    }
    args.update(updates)
    return build_pre_dispatch_plan(**args)


def receipt() -> dict:
    return {
        "ready": True,
        "decision": "DISPATCH_RECEIPT_ISSUED",
        "receipt_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        "receipt_sha256": "f" * 64,
        "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
    }


def guard() -> dict:
    return {
        "ready": True,
        "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
        "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "receipt_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        "orchestrator_execution_id": "EXEC-SKILL-ORCH-001",
        "consumer_execution_id": "EXEC-PROFILE-RUNTIME-11111111-2222-4333-8444-555555555555",
        "capability_code": "PROFILE_EXECUTION_RUNTIME",
        "plan_digest": "c" * 64,
    }


def main() -> None:
    checks = 0

    plan = pre()
    assert plan["status"] == "PRE_DISPATCH_READY"
    assert plan["decision"] == "PROFILE_CHILD_RESERVATION_READY"
    assert plan["consumer_execution_id"] == "EXEC-PROFILE-RUNTIME-11111111-2222-4333-8444-555555555555"
    assert plan["task_packet_work_digest"] == canonical_digest(seed())
    assert [a["action"] for a in plan["ordered_actions"]] == [
        "BEGIN_CHILD_EXECUTION",
        "ISSUE_DISPATCH_RECEIPT",
        "BIND_CAPABILITY_ENTRY_GUARD",
    ]
    checks += 5

    begin = plan["ordered_actions"][0]
    assert begin["rpc"] == "public.lf_profile_execution_begin_v1"
    assert begin["args"]["manifest"]["orchestrator_execution_id"] == "EXEC-SKILL-ORCH-001"
    assert begin["args"]["manifest"]["plan_digest"] == "c" * 64
    assert begin["args"]["manifest"]["capability_code"] == "PROFILE_EXECUTION_RUNTIME"
    assert begin["args"]["manifest"]["task_packet_work_digest"] == plan["task_packet_work_digest"]
    assert begin["args"]["request_sha256"] == plan["child_request_sha256"]
    assert begin["args"]["idempotency_key"].startswith("profile-runtime-orchestrated:")
    checks += 7

    issue = plan["ordered_actions"][1]
    assert issue["rpc"] == "public.fn_lf_orchestrator_dispatch_receipt_v1"
    assert issue["args"]["consumer_execution_id"] == plan["consumer_execution_id"]
    assert issue["args"]["dispatch_scope"]["task_packet_work_digest"] == plan["task_packet_work_digest"]
    checks += 3

    seed_with_fake_authority = seed()
    seed_with_fake_authority["worker_binding"]["entry_guard_decision"] = "ORCHESTRATOR_ENTRY_ACCEPTED"
    blocked = pre(task_packet_seed=seed_with_fake_authority)
    assert blocked["decision"] == "BLOCK_PREMATURE_EXECUTION_AUTHORITY_IN_SEED"
    assert "entry_guard_decision" in blocked["detail"]["forbidden_keys"]
    checks += 2

    seed_with_fake_receipt = seed()
    seed_with_fake_receipt["worker_binding"]["dispatch_receipt_ref"] = "fake://receipt"
    assert pre(task_packet_seed=seed_with_fake_receipt)["decision"] == "BLOCK_PREMATURE_EXECUTION_AUTHORITY_IN_SEED"
    checks += 1

    finalized = finalize_after_guard(plan, dispatch_receipt_readback=receipt(), entry_guard_readback=guard())
    assert finalized["status"] == "READY_TO_ENQUEUE"
    assert finalized["decision"] == "PROFILE_EXECUTION_AUTHORITY_FINALIZED"
    wb = finalized["final_task_packet"]["worker_binding"]
    assert wb["orchestrator_execution_id"] == "EXEC-SKILL-ORCH-001"
    assert wb["entry_guard_code"] == "ORCHESTRATOR_EXECUTION_GUARD_V1"
    assert wb["entry_guard_decision"] == "ORCHESTRATOR_ENTRY_ACCEPTED"
    assert wb["dispatch_receipt_ref"].endswith("@sha256:" + "f" * 64)
    assert finalized["runtime_request_envelope"]["attach_existing_child_execution"] is True
    assert finalized["runtime_request_envelope"]["task_packet_work_digest"] == plan["task_packet_work_digest"]
    assert finalized["enqueue_action"]["consumer_execution_id"] == plan["consumer_execution_id"]
    checks += 9

    projection = copy.deepcopy(finalized["final_task_packet"])
    for key in (
        "orchestrator_execution_id",
        "dispatch_receipt_ref",
        "entry_guard_code",
        "entry_guard_decision",
    ):
        projection["worker_binding"].pop(key)
    assert canonical_digest(projection) == plan["task_packet_work_digest"]
    checks += 1

    bad_guard = guard()
    bad_guard["receipt_id"] = "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"
    assert finalize_after_guard(plan, dispatch_receipt_readback=receipt(), entry_guard_readback=bad_guard)["decision"] == "BLOCK_ENTRY_GUARD_RECEIPT_MISMATCH"
    checks += 1

    bad_guard = guard()
    bad_guard["consumer_execution_id"] = "EXEC-OTHER"
    assert finalize_after_guard(plan, dispatch_receipt_readback=receipt(), entry_guard_readback=bad_guard)["decision"] == "BLOCK_ENTRY_GUARD_CONSUMER_MISMATCH"
    checks += 1

    bad_guard = guard()
    bad_guard["plan_digest"] = "9" * 64
    assert finalize_after_guard(plan, dispatch_receipt_readback=receipt(), entry_guard_readback=bad_guard)["decision"] == "BLOCK_ENTRY_GUARD_PLAN_MISMATCH"
    checks += 1

    bad_receipt = receipt()
    bad_receipt["ready"] = False
    assert finalize_after_guard(plan, dispatch_receipt_readback=bad_receipt, entry_guard_readback=guard())["decision"] == "BLOCK_DISPATCH_RECEIPT_NOT_READY"
    checks += 1

    bad_guard = guard()
    bad_guard["decision"] = "BLOCK"
    assert finalize_after_guard(plan, dispatch_receipt_readback=receipt(), entry_guard_readback=bad_guard)["decision"] == "BLOCK_ENTRY_GUARD_DECISION_INVALID"
    checks += 1

    repeated = pre()
    assert repeated["task_packet_work_digest"] == plan["task_packet_work_digest"]
    assert repeated["child_request_sha256"] == plan["child_request_sha256"]
    assert repeated["pre_dispatch_plan_digest"] == plan["pre_dispatch_plan_digest"]
    checks += 3

    assert pre(request_id="bad")["decision"] == "BLOCK_PROFILE_RUNTIME_REQUEST_ID_INVALID"
    assert pre(source_revision="x")["decision"] == "BLOCK_SOURCE_REVISION_INVALID"
    assert pre(parent_plan_digest="x")["decision"] == "BLOCK_PARENT_PLAN_DIGEST_INVALID"
    checks += 3

    assert checks == 38
    print("PASS_PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V2 checks=38")


if __name__ == "__main__":
    main()
