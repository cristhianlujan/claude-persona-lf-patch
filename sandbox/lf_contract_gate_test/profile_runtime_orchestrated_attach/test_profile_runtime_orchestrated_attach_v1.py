import copy
import hashlib
import json

from profile_runtime_orchestrated_attach_v1 import validate_attach


def digest(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


REQUEST_ID = "11111111-2222-4333-8444-555555555555"
ORCH = "EXEC-SKILL-ORCH-001"
CHILD = f"EXEC-PROFILE-RUNTIME-{REQUEST_ID}"
PLAN = "a" * 64
RECEIPT_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
RECEIPT_SHA = "b" * 64
SOURCE_REV = "c" * 40
PROFILE_DIGEST = "sha256:" + "d" * 64


def seed_packet() -> dict:
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
            "binding_digest": "e" * 64,
        },
    }


def final_packet() -> tuple[dict, str]:
    seed = seed_packet()
    work_digest = digest(seed)
    packet = copy.deepcopy(seed)
    packet["worker_binding"].update(
        {
            "orchestrator_execution_id": ORCH,
            "dispatch_receipt_ref": f"supabase://private.lf_orchestrator_dispatch_receipts_v1/{RECEIPT_ID}@sha256:{RECEIPT_SHA}",
            "entry_guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
            "entry_guard_decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
        }
    )
    return packet, work_digest


def binding_resolution() -> dict:
    binding = {
        "step_id": "SCREEN_DECOMPOSITION",
        "worker_role": "SCREEN_DECOMPOSER",
        "profile_code": "PERFIL-SCREEN-DECOMPOSER-LF",
        "profile_slug": "screen_decomposer_lf",
        "source_mode": "EMBEDDED_SKILL_PROFILE",
        "source_root": "skills/creating-integral-user-stories",
        "source_revision": SOURCE_REV,
        "source_refs": [
            {
                "path": "skills/creating-integral-user-stories/perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md",
                "sha256": "1" * 64,
            }
        ],
        "runtime_schema": {
            "ref": "skills/creating-integral-user-stories/schemas/screen-decomposition.schema.json",
            "sha256": "2" * 64,
            "selection_mode": "EXACT_REF",
        },
        "deterministic_validator": {
            "ref": "skills/creating-integral-user-stories/scripts/validate_screen_decomposition_visual.py",
            "sha256": "3" * 64,
            "invocation": "CLI",
        },
        "judge_binding": {
            "judge_code": "J02_SCREEN_DECOMPOSITION",
            "ref": "skills/creating-integral-user-stories/judges/screen-decomposition.yaml",
            "sha256": "4" * 64,
            "worker_must_not_execute_own_judge": True,
        },
        "model_context": {"source_refs": [], "max_chars": 32000},
        "authority_refs": [{"ref": "asset://PERFIL-SCREEN-DECOMPOSER-LF", "revision": "1", "digest": "5" * 64}],
        "worker_binding_digest": "e" * 64,
    }
    return {
        "schema_version": "LF_PROFILE_TASK_RUNTIME_BINDING_V1",
        "status": "RESOLVED",
        "decision": "TASK_RUNTIME_BINDING_RESOLVED",
        "binding": binding,
        "binding_digest": digest(binding),
    }


def fixture() -> dict:
    packet, work_digest = final_packet()
    packet_digest = digest(packet)
    guard = {
        "ready": True,
        "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
        "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "receipt_id": RECEIPT_ID,
        "orchestrator_execution_id": ORCH,
        "consumer_execution_id": CHILD,
        "capability_code": "PROFILE_EXECUTION_RUNTIME",
        "plan_digest": PLAN,
    }
    queue = {
        "request_id": REQUEST_ID,
        "profile_code": "PERFIL-SCREEN-DECOMPOSER-LF",
        "profile_slug": "screen_decomposer_lf",
        "profile_source_paths": ["skills/creating-integral-user-stories/perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md"],
        "input_literal": json.dumps(packet, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        "runtime_request_envelope": {
            "schema_version": "LF_PROFILE_RUNTIME_ORCHESTRATED_REQUEST_V2",
            "orchestrator_execution_id": ORCH,
            "consumer_execution_id": CHILD,
            "capability_code": "PROFILE_EXECUTION_RUNTIME",
            "plan_digest": PLAN,
            "task_packet_work_digest": work_digest,
            "final_task_packet_digest": packet_digest,
            "dispatch_receipt_id": RECEIPT_ID,
            "dispatch_receipt_sha256": RECEIPT_SHA,
            "entry_guard": guard,
            "profile_source_digest": PROFILE_DIGEST,
            "source_revision": SOURCE_REV,
            "attach_existing_child_execution": True,
        },
    }
    child = {
        "execution_id": CHILD,
        "operation_code": "EJECUCION_PERFIL_LF",
        "status": "IN_PROGRESS",
        "manifest": {
            "orchestrator_execution_id": ORCH,
            "plan_digest": PLAN,
            "capability_code": "PROFILE_EXECUTION_RUNTIME",
            "task_packet_work_digest": work_digest,
            "profile_source_digest": PROFILE_DIGEST,
            "source_revision": SOURCE_REV,
        },
    }
    receipt = {
        "receipt_id": RECEIPT_ID,
        "receipt_sha256": RECEIPT_SHA,
        "consumer_execution_id": CHILD,
        "orchestrator_execution_id": ORCH,
        "capability_code": "PROFILE_EXECUTION_RUNTIME",
        "plan_digest": PLAN,
    }
    return {
        "queue_row": queue,
        "child_execution": child,
        "receipt_readback": receipt,
        "task_runtime_binding_resolution": binding_resolution(),
        "runtime_source_revision": SOURCE_REV,
    }


def main() -> None:
    checks = 0
    base = fixture()
    result = validate_attach(**copy.deepcopy(base))
    assert result["status"] == "READY"
    assert result["decision"] == "ATTACH_EXISTING_CHILD_ACCEPTED"
    assert result["consumer_execution_id"] == CHILD
    assert result["profile_source_mode"] == "EMBEDDED_SKILL_PROFILE"
    assert result["second_begin_allowed"] is False
    checks += 5

    repeated = validate_attach(**copy.deepcopy(base))
    assert repeated["result_digest"] == result["result_digest"]
    checks += 1

    cases = []

    bad = copy.deepcopy(base); bad["queue_row"]["runtime_request_envelope"]["attach_existing_child_execution"] = False
    cases.append((bad, "BLOCK_EXISTING_CHILD_ATTACH_NOT_REQUESTED"))
    bad = copy.deepcopy(base); bad["child_execution"]["status"] = "COMPLETED"
    cases.append((bad, "BLOCK_EXISTING_CHILD_NOT_IN_PROGRESS"))
    bad = copy.deepcopy(base); bad["child_execution"]["manifest"]["plan_digest"] = "9" * 64
    cases.append((bad, "BLOCK_EXISTING_CHILD_MANIFEST_CROSSBIND_MISMATCH"))
    bad = copy.deepcopy(base); bad["receipt_readback"]["consumer_execution_id"] = "EXEC-OTHER"
    cases.append((bad, "BLOCK_DISPATCH_RECEIPT_CROSSBIND_MISMATCH"))
    bad = copy.deepcopy(base); bad["queue_row"]["runtime_request_envelope"]["entry_guard"]["decision"] = "BLOCKED"
    cases.append((bad, "BLOCK_ENTRY_GUARD_CROSSBIND_MISMATCH"))
    bad = copy.deepcopy(base); bad["runtime_source_revision"] = "f" * 40
    cases.append((bad, "BLOCK_RUNTIME_SOURCE_REVISION_MISMATCH"))
    bad = copy.deepcopy(base); bad["task_runtime_binding_resolution"] = None
    cases.append((bad, "BLOCK_EMBEDDED_PROFILE_TASK_BINDING_MISSING"))
    bad = copy.deepcopy(base); bad["task_runtime_binding_resolution"]["binding"]["profile_code"] = "PERFIL-OTHER"
    bad["task_runtime_binding_resolution"]["binding_digest"] = digest(bad["task_runtime_binding_resolution"]["binding"])
    cases.append((bad, "BLOCK_EMBEDDED_PROFILE_IDENTITY_MISMATCH"))
    bad = copy.deepcopy(base); bad["queue_row"]["runtime_request_envelope"]["final_task_packet_digest"] = "0" * 64
    cases.append((bad, "BLOCK_FINAL_TASK_PACKET_DIGEST_MISMATCH"))

    for payload, expected in cases:
        observed = validate_attach(**payload)
        assert observed["decision"] == expected, (expected, observed)
        checks += 1

    drift = copy.deepcopy(base)
    packet = json.loads(drift["queue_row"]["input_literal"])
    packet["task_id"] = "TASK-J02-DRIFT"
    drift["queue_row"]["input_literal"] = json.dumps(packet, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    drift["queue_row"]["runtime_request_envelope"]["final_task_packet_digest"] = digest(packet)
    observed = validate_attach(**drift)
    assert observed["decision"] == "BLOCK_FINAL_TASK_PACKET_STATIC_PROJECTION_DRIFT"
    checks += 1

    standalone = copy.deepcopy(base)
    standalone["queue_row"]["profile_source_paths"] = ["profiles/quality_pack/SKILL.md"]
    standalone["queue_row"]["profile_code"] = "PERFIL-QUALITY-PACK"
    standalone["queue_row"]["profile_slug"] = "quality_pack"
    standalone["task_runtime_binding_resolution"] = None
    observed = validate_attach(**standalone)
    assert observed["decision"] == "ATTACH_EXISTING_CHILD_ACCEPTED"
    assert observed["profile_source_mode"] == "STANDALONE_PROFILE"
    checks += 2

    assert checks == 18
    print("PASS_PROFILE_RUNTIME_ORCHESTRATED_ATTACH_V1 checks=18")


if __name__ == "__main__":
    main()
