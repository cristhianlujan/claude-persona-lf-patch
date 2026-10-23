from __future__ import annotations

from dataclasses import replace

from skill_orchestration_runner_v1 import (
    OrchestrationBlocked,
    OrchestrationPorts,
    SkillOrchestrationRunnerV1,
)


ORCH = "EXEC-SKILL-ORCH-001"
PARENT = "EXEC-SKILL-001"
CHILD = "EXEC-PROFILE-RUNTIME-11111111-2222-4333-8444-555555555555"
REV = "a" * 40
WORK = "b" * 64
PLAN = "c" * 64
FINAL = "d" * 64
OUTPUT = "e" * 64
RECEIPT = "11111111-2222-4333-8444-555555555555"
RECEIPT_SHA = "f" * 64


def build_ports(calls: list[str]) -> OrchestrationPorts:
    def call(name, value):
        calls.append(name)
        return value

    return OrchestrationPorts(
        read_parent=lambda execution_id: call("read_parent", {
            "execution_id": execution_id,
            "operation_code": "EJECUCION_SKILL_LF",
            "status": "IN_PROGRESS",
            "skill_code": "SKILL-CREATING-INTEGRAL-USER-STORIES",
            "source_revision": REV,
        }),
        read_step=lambda request: call("read_step", {
            "step_id": request["step_id"],
            "worker_role": "SCREEN_DECOMPOSER",
            "allowed_worker_kinds": ["PROFILE", "AGENT"],
            "judge_code": "J02_SCREEN_DECOMPOSITION",
            "source_revision": REV,
        }),
        resolve_worker=lambda step: call("resolve_worker", {
            "status": "RESOLVED",
            "decision": "WORKER_RESOLVED",
            "resolution_digest": "1" * 64,
            "binding_seed": {
                "worker_ref": "PERFIL-SCREEN-DECOMPOSER-LF",
                "worker_kind": "PROFILE",
                "binding_authority_ref": "supabase://public/lf_activos",
                "binding_revision": "rev-1",
                "binding_digest": "2" * 64,
                "source_revision": REV,
            },
        }),
        resolve_task_binding=lambda step, worker: call("resolve_task_binding", {
            "status": "RESOLVED",
            "decision": "TASK_RUNTIME_BINDING_RESOLVED",
            "binding_digest": "3" * 64,
            "binding": {"profile_code": "PERFIL-SCREEN-DECOMPOSER-LF"},
        }),
        build_pre_dispatch=lambda step, worker, binding: call("build_pre_dispatch", {
            "status": "PRE_DISPATCH_READY",
            "decision": "PROFILE_CHILD_RESERVATION_READY",
            "consumer_execution_id": CHILD,
            "task_packet_work_digest": WORK,
            "parent_plan_digest": PLAN,
            "child_request_sha256": "4" * 64,
        }),
        reserve_child=lambda pre: call("reserve_child", {
            "execution_id": CHILD,
            "operation_code": "EJECUCION_PERFIL_LF",
            "status": "IN_PROGRESS",
            "manifest": {
                "orchestrator_execution_id": ORCH,
                "plan_digest": PLAN,
                "task_packet_work_digest": WORK,
            },
        }),
        issue_receipt=lambda pre, child: call("issue_receipt", {
            "ready": True,
            "decision": "DISPATCH_RECEIPT_ISSUED",
            "receipt_id": RECEIPT,
            "receipt_sha256": RECEIPT_SHA,
        }),
        read_entry_guard=lambda pre, child, receipt: call("read_entry_guard", {
            "ready": True,
            "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
            "receipt_id": RECEIPT,
        }),
        finalize_task_packet=lambda pre, receipt, guard: call("finalize_task_packet", {
            "status": "READY_TO_ENQUEUE",
            "decision": "PROFILE_EXECUTION_AUTHORITY_FINALIZED",
            "task_packet_work_digest": WORK,
            "final_task_packet_digest": FINAL,
            "enqueue_action": {"target": "private.lf_profile_runtime_queue_v1"},
        }),
        dispatch_worker=lambda final: call("dispatch_worker", {
            "worker_dispatch_ref": "queue://profile-runtime/request",
            "child_execution_id": CHILD,
            "worker_kind": "PROFILE",
        }),
        collect_worker_result=lambda dispatch: call("collect_worker_result", {
            "worker_result_ref": "runtime://profile/result",
            "child_execution_id": CHILD,
            "output_digest": OUTPUT,
            "runtime_completion": "PASS",
            "profile_contract_valid": "PASS",
        }),
        execute_step_judge=lambda step, result: call("execute_step_judge", {
            "judge_code": "J02_SCREEN_DECOMPOSITION",
            "judge_result": "PASS_WITH_EVIDENCE",
            "judge_execution_ref": "judge://j02/run",
            "executor_identity": "JUDGE-J02-INDEPENDENT",
            "worker_identity": "PERFIL-SCREEN-DECOMPOSER-LF",
        }),
        checkpoint=lambda payload: call("checkpoint", {
            "status": "RECORDED",
            "checkpoint_ref": "checkpoint://skill-orchestration/j02",
            "no_runtime_activation": True,
            "no_production_activation": True,
        }),
    )


def run(ports: OrchestrationPorts):
    return SkillOrchestrationRunnerV1(ports).run_step(
        orchestration_execution_id=ORCH,
        parent_execution_id=PARENT,
        requested_step_id="SCREEN_DECOMPOSITION",
    )


def main() -> None:
    checks = 0
    calls: list[str] = []
    result = run(build_ports(calls))
    assert result["status"] == "PASS"
    assert result["operation_code"] == "ORQUESTACION_SKILL_LF"
    assert result["parent_execution_id"] == PARENT
    assert result["step_id"] == "SCREEN_DECOMPOSITION"
    assert result["worker_ref"] == "PERFIL-SCREEN-DECOMPOSER-LF"
    assert result["child_execution_id"] == CHILD
    assert result["task_packet_work_digest"] == WORK
    assert result["final_task_packet_digest"] == FINAL
    assert result["output_digest"] == OUTPUT
    assert result["judge_result"] == "PASS_WITH_EVIDENCE"
    assert result["checkpoint_ref"] == "checkpoint://skill-orchestration/j02"
    checks += 11

    expected_calls = [
        "read_parent",
        "read_step",
        "resolve_worker",
        "resolve_task_binding",
        "build_pre_dispatch",
        "reserve_child",
        "issue_receipt",
        "read_entry_guard",
        "finalize_task_packet",
        "dispatch_worker",
        "collect_worker_result",
        "execute_step_judge",
        "checkpoint",
    ]
    assert calls == expected_calls
    assert [item["step"] for item in result["trace"]] == [
        "bind_parent_skill_execution",
        "load_next_step_contract",
        "resolve_worker",
        "resolve_task_runtime_binding",
        "build_task_packet_seed",
        "reserve_child_execution",
        "issue_dispatch_receipt",
        "entry_guard_readback",
        "finalize_task_packet",
        "dispatch_worker",
        "collect_worker_result",
        "step_judge_handoff",
    ]
    checks += 2

    calls = []
    ports = build_ports(calls)
    ports = replace(ports, issue_receipt=lambda pre, child: (calls.append("issue_receipt") or {"ready": False, "decision": "BLOCK_UNKNOWN_OR_INACTIVE_CAPABILITY"}))
    try:
        run(ports)
    except OrchestrationBlocked as exc:
        assert exc.code == "BLOCK_DISPATCH_RECEIPT_NOT_READY"
    else:
        raise AssertionError("receipt failure did not block")
    assert calls == expected_calls[:7]
    checks += 2

    calls = []
    ports = build_ports(calls)
    ports = replace(ports, read_entry_guard=lambda pre, child, receipt: (calls.append("read_entry_guard") or {"ready": True, "decision": "BLOCKED", "receipt_id": RECEIPT}))
    try:
        run(ports)
    except OrchestrationBlocked as exc:
        assert exc.code == "BLOCK_ENTRY_GUARD_NOT_ACCEPTED"
    else:
        raise AssertionError("guard failure did not block")
    assert calls == expected_calls[:8]
    checks += 2

    calls = []
    ports = build_ports(calls)
    ports = replace(ports, collect_worker_result=lambda dispatch: (calls.append("collect_worker_result") or {
        "worker_result_ref": "runtime://profile/result",
        "child_execution_id": CHILD,
        "output_digest": OUTPUT,
        "runtime_completion": "PASS",
        "profile_contract_valid": "FAIL",
    }))
    try:
        run(ports)
    except OrchestrationBlocked as exc:
        assert exc.code == "BLOCK_WORKER_RUNTIME_OR_CONTRACT_NOT_PASS"
    else:
        raise AssertionError("contract failure did not block")
    assert calls == expected_calls[:11]
    checks += 2

    calls = []
    ports = build_ports(calls)
    ports = replace(ports, execute_step_judge=lambda step, result: (calls.append("execute_step_judge") or {
        "judge_code": "J02_SCREEN_DECOMPOSITION",
        "judge_result": "PASS_WITH_EVIDENCE",
        "judge_execution_ref": "judge://j02/run",
        "executor_identity": "PERFIL-SCREEN-DECOMPOSER-LF",
        "worker_identity": "PERFIL-SCREEN-DECOMPOSER-LF",
    }))
    try:
        run(ports)
    except OrchestrationBlocked as exc:
        assert exc.code == "BLOCK_STEP_JUDGE_INDEPENDENCE_OR_IDENTITY_MISMATCH"
    else:
        raise AssertionError("self judge did not block")
    assert calls == expected_calls[:12]
    checks += 2

    assert checks == 21
    print("PASS_SKILL_ORCHESTRATION_RUNNER_V1 checks=21")


if __name__ == "__main__":
    main()
