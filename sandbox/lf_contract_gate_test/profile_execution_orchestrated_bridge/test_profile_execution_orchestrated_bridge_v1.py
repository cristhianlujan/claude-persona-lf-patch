import hashlib
import json

from profile_execution_orchestrated_bridge_v1 import build_plan


def canonical_sha(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def packet() -> dict:
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
            "orchestrator_execution_id": "EXEC-SKILL-ORCH-001",
            "dispatch_receipt_ref": "PENDING_ORCHESTRATOR_BIND",
            "entry_guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
            "entry_guard_decision": "ORCHESTRATOR_ENTRY_ACCEPTED"
        }
    }


def build(**updates):
    args = {
        "orchestrator_execution_id": "EXEC-SKILL-ORCH-001",
        "request_id": "11111111-2222-4333-8444-555555555555",
        "profile_code": "PERFIL-SCREEN-DECOMPOSER-LF",
        "profile_slug": "screen_decomposer_lf",
        "target_repo": "cristhianlujan/claude-persona-lf-patch",
        "profile_source_paths": ["profiles/screen_decomposer_lf/SKILL.md"],
        "profile_source_digest": "sha256:" + "e" * 64,
        "source_revision": "a" * 40,
        "task_packet": packet(),
        "plan_digest": "c" * 64,
        "expected_capability_manifest_sha256": "d" * 64,
    }
    args.update(updates)
    return build_plan(**args)


def main() -> None:
    checks = 0

    result = build()
    assert result["status"] == "PLANNED"
    assert result["decision"] == "PROFILE_EXECUTION_ORCHESTRATED_PLAN_READY"
    assert result["capability_code"] == "PROFILE_EXECUTION_RUNTIME"
    assert result["consumer_execution_id"] == "EXEC-PROFILE-RUNTIME-11111111-2222-4333-8444-555555555555"
    assert [a["action"] for a in result["ordered_actions"]] == [
        "BEGIN_CHILD_EXECUTION",
        "ISSUE_DISPATCH_RECEIPT",
        "BIND_CAPABILITY_ENTRY_GUARD",
        "ENQUEUE_EXISTING_PROFILE_RUNTIME",
    ]
    checks += 5

    task_json = json.dumps(packet(), ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    expected_request_sha = canonical_sha(
        {
            "input_sha256": hashlib.sha256(task_json.encode("utf-8")).hexdigest(),
            "profile_code": "PERFIL-SCREEN-DECOMPOSER-LF",
            "profile_slug": "screen_decomposer_lf",
            "profile_source_digest": "sha256:" + "e" * 64,
            "profile_source_revision": "a" * 40,
            "profile_source_paths": ["profiles/screen_decomposer_lf/SKILL.md"],
        }
    )
    assert result["runtime_compatible_request_sha256"] == expected_request_sha
    checks += 1

    begin = result["ordered_actions"][0]
    assert begin["rpc"] == "public.lf_profile_execution_begin_v1"
    assert begin["args"]["request_sha256"] == expected_request_sha
    assert begin["args"]["target_path"] == "profiles/screen_decomposer_lf/SKILL.md"
    assert begin["args"]["manifest"]["orchestrator_execution_id"] == "EXEC-SKILL-ORCH-001"
    assert begin["args"]["manifest"]["plan_digest"] == "c" * 64
    assert begin["args"]["manifest"]["capability_code"] == "PROFILE_EXECUTION_RUNTIME"
    assert begin["args"]["manifest"]["profile_source_digest"] == "sha256:" + "e" * 64
    checks += 7

    receipt = result["ordered_actions"][1]
    assert receipt["rpc"] == "public.fn_lf_orchestrator_dispatch_receipt_v1"
    assert receipt["args"]["consumer_execution_id"] == result["consumer_execution_id"]
    assert receipt["args"]["capability_code"] == "PROFILE_EXECUTION_RUNTIME"
    assert receipt["args"]["dispatch_scope"]["profile_source_digest"] == "sha256:" + "e" * 64
    checks += 4

    guard = result["ordered_actions"][2]
    assert guard["rpc"] == "public.fn_lf_capability_bind_from_orchestrator_v1"
    assert guard["args"]["expected_manifest_sha256"] == "d" * 64
    checks += 2

    enqueue = result["ordered_actions"][3]
    assert enqueue["target"] == "private.lf_profile_runtime_queue_v1"
    assert enqueue["request_id"] == result["request_id"]
    assert enqueue["consumer_execution_id"] == result["consumer_execution_id"]
    assert enqueue["profile_slug"] == "screen_decomposer_lf"
    assert enqueue["profile_source_paths"] == ["profiles/screen_decomposer_lf/SKILL.md"]
    assert enqueue["runtime_request_envelope"]["entry_guard_required"] is True
    checks += 6

    repeated = build()
    assert repeated["plan_digest"] == result["plan_digest"]
    assert repeated["task_packet_digest"] == result["task_packet_digest"]
    assert repeated["runtime_compatible_request_sha256"] == expected_request_sha
    checks += 3

    bad_packet = packet()
    bad_packet["worker_binding"]["worker_kind"] = "AGENT"
    assert build(task_packet=bad_packet)["decision"] == "BLOCK_PROFILE_BRIDGE_WORKER_KIND_MISMATCH"
    checks += 1

    bad_packet = packet()
    bad_packet["worker_binding"]["worker_ref"] = "PERFIL-OTHER-LF"
    assert build(task_packet=bad_packet)["decision"] == "BLOCK_PROFILE_BRIDGE_WORKER_REF_MISMATCH"
    checks += 1

    bad_packet = packet()
    bad_packet["worker_binding"]["orchestrator_execution_id"] = "EXEC-OTHER"
    assert build(task_packet=bad_packet)["decision"] == "BLOCK_PROFILE_BRIDGE_ORCHESTRATOR_MISMATCH"
    checks += 1

    assert build(request_id="not-a-uuid")["decision"] == "BLOCK_PROFILE_RUNTIME_REQUEST_ID_INVALID"
    assert build(source_revision="x")["decision"] == "BLOCK_SOURCE_REVISION_INVALID"
    assert build(plan_digest="x")["decision"] == "BLOCK_PARENT_PLAN_DIGEST_INVALID"
    assert build(profile_source_digest="x")["decision"] == "BLOCK_PROFILE_SOURCE_DIGEST_INVALID"
    assert build(profile_source_paths=[])["decision"] == "BLOCK_PROFILE_SOURCE_PATHS_MISSING"
    checks += 5

    assert checks == 36
    print("PASS_PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1 checks=36")


if __name__ == "__main__":
    main()
