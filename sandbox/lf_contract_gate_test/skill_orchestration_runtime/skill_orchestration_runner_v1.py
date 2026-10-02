from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any, Callable, Dict


class OrchestrationBlocked(RuntimeError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}:{detail}" if detail else code)


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _object(value: Any, code: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise OrchestrationBlocked(code)
    return value


def _required(value: dict[str, Any], keys: tuple[str, ...], code: str) -> None:
    missing = [key for key in keys if value.get(key) in (None, "", [], {})]
    if missing:
        raise OrchestrationBlocked(code, ",".join(missing))


@dataclass(frozen=True)
class OrchestrationPorts:
    read_parent: Callable[[str], dict[str, Any]]
    read_step: Callable[[dict[str, Any]], dict[str, Any]]
    resolve_worker: Callable[[dict[str, Any]], dict[str, Any]]
    resolve_task_binding: Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]]
    build_pre_dispatch: Callable[[dict[str, Any], dict[str, Any], dict[str, Any]], dict[str, Any]]
    reserve_child: Callable[[dict[str, Any]], dict[str, Any]]
    issue_receipt: Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]]
    read_entry_guard: Callable[[dict[str, Any], dict[str, Any], dict[str, Any]], dict[str, Any]]
    finalize_task_packet: Callable[[dict[str, Any], dict[str, Any], dict[str, Any]], dict[str, Any]]
    dispatch_worker: Callable[[dict[str, Any]], dict[str, Any]]
    collect_worker_result: Callable[[dict[str, Any]], dict[str, Any]]
    execute_step_judge: Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]]
    checkpoint: Callable[[dict[str, Any]], dict[str, Any]]


class SkillOrchestrationRunnerV1:
    """Fail-closed orchestration state machine.

    All effects are delegated to explicit ports. The runner owns ordering and cross-binding,
    not Router/currentness/Profile Runtime/DB/model execution.
    """

    OPERATION_CODE = "ORQUESTACION_SKILL_LF"
    PARENT_OPERATION = "EJECUCION_SKILL_LF"

    def __init__(self, ports: OrchestrationPorts) -> None:
        self.ports = ports

    def run_step(
        self,
        *,
        orchestration_execution_id: str,
        parent_execution_id: str,
        requested_step_id: str,
    ) -> dict[str, Any]:
        if not orchestration_execution_id.strip() or not parent_execution_id.strip() or not requested_step_id.strip():
            raise OrchestrationBlocked("BLOCK_ORCHESTRATION_IDENTITY_INVALID")

        trace: list[dict[str, Any]] = []

        parent = _object(self.ports.read_parent(parent_execution_id), "BLOCK_PARENT_READ_INVALID")
        _required(parent, ("execution_id", "operation_code", "status", "skill_code", "source_revision"), "BLOCK_PARENT_EVIDENCE_MISSING")
        if parent["execution_id"] != parent_execution_id or parent["operation_code"] != self.PARENT_OPERATION or parent["status"] != "IN_PROGRESS":
            raise OrchestrationBlocked("BLOCK_PARENT_SKILL_EXECUTION_NOT_ACTIVE")
        trace.append({"step": "bind_parent_skill_execution", "digest": _digest(parent)})

        step = _object(
            self.ports.read_step(
                {
                    "skill_code": parent["skill_code"],
                    "source_revision": parent["source_revision"],
                    "step_id": requested_step_id,
                }
            ),
            "BLOCK_STEP_CONTRACT_INVALID",
        )
        _required(step, ("step_id", "worker_role", "allowed_worker_kinds", "judge_code", "source_revision"), "BLOCK_STEP_CONTRACT_INCOMPLETE")
        if step["step_id"] != requested_step_id or step["source_revision"] != parent["source_revision"]:
            raise OrchestrationBlocked("BLOCK_STEP_CONTRACT_CURRENTNESS_MISMATCH")
        if not isinstance(step["allowed_worker_kinds"], list) or not step["allowed_worker_kinds"]:
            raise OrchestrationBlocked("BLOCK_STEP_ALLOWED_WORKER_KINDS_INVALID")
        step_digest = _digest(step)
        trace.append({"step": "load_next_step_contract", "digest": step_digest})

        worker = _object(self.ports.resolve_worker(step), "BLOCK_WORKER_RESOLUTION_INVALID")
        if worker.get("status") != "RESOLVED" or worker.get("decision") != "WORKER_RESOLVED":
            raise OrchestrationBlocked("BLOCK_WORKER_UNRESOLVED", str(worker.get("decision")))
        binding_seed = _object(worker.get("binding_seed"), "BLOCK_WORKER_BINDING_SEED_MISSING")
        _required(binding_seed, ("worker_ref", "worker_kind", "binding_authority_ref", "binding_revision", "binding_digest", "source_revision"), "BLOCK_WORKER_BINDING_SEED_INCOMPLETE")
        if binding_seed["worker_kind"] not in step["allowed_worker_kinds"] or binding_seed["source_revision"] != parent["source_revision"]:
            raise OrchestrationBlocked("BLOCK_WORKER_BINDING_MISMATCH")
        trace.append({"step": "resolve_worker", "digest": worker.get("resolution_digest") or _digest(worker)})

        task_binding = _object(self.ports.resolve_task_binding(step, worker), "BLOCK_TASK_BINDING_RESULT_INVALID")
        if binding_seed["worker_kind"] == "PROFILE":
            if task_binding.get("status") != "RESOLVED" or task_binding.get("decision") != "TASK_RUNTIME_BINDING_RESOLVED":
                raise OrchestrationBlocked("BLOCK_TASK_RUNTIME_BINDING_UNRESOLVED", str(task_binding.get("decision")))
            task_binding_digest = task_binding.get("binding_digest")
        else:
            if task_binding.get("status") != "NOT_APPLICABLE":
                raise OrchestrationBlocked("BLOCK_TASK_BINDING_APPLICABILITY_INVALID")
            task_binding_digest = task_binding.get("binding_digest") or _digest(task_binding)
        trace.append({"step": "resolve_task_runtime_binding", "digest": task_binding_digest})

        pre = _object(self.ports.build_pre_dispatch(step, worker, task_binding), "BLOCK_PRE_DISPATCH_PLAN_INVALID")
        if pre.get("status") != "PRE_DISPATCH_READY" or pre.get("decision") != "PROFILE_CHILD_RESERVATION_READY":
            raise OrchestrationBlocked("BLOCK_PRE_DISPATCH_PLAN_NOT_READY", str(pre.get("decision")))
        _required(pre, ("consumer_execution_id", "task_packet_work_digest", "parent_plan_digest", "child_request_sha256"), "BLOCK_PRE_DISPATCH_EVIDENCE_MISSING")
        trace.append({"step": "build_task_packet_seed", "digest": pre["task_packet_work_digest"]})

        child = _object(self.ports.reserve_child(pre), "BLOCK_CHILD_RESERVATION_INVALID")
        _required(child, ("execution_id", "operation_code", "status", "manifest"), "BLOCK_CHILD_RESERVATION_EVIDENCE_MISSING")
        if child["execution_id"] != pre["consumer_execution_id"] or child["status"] != "IN_PROGRESS":
            raise OrchestrationBlocked("BLOCK_CHILD_RESERVATION_CROSSBIND_MISMATCH")
        manifest = _object(child["manifest"], "BLOCK_CHILD_MANIFEST_INVALID")
        expected_child = {
            "orchestrator_execution_id": orchestration_execution_id,
            "plan_digest": pre["parent_plan_digest"],
            "task_packet_work_digest": pre["task_packet_work_digest"],
        }
        mismatches = [key for key, value in expected_child.items() if manifest.get(key) != value]
        if mismatches:
            raise OrchestrationBlocked("BLOCK_CHILD_MANIFEST_CROSSBIND_MISMATCH", ",".join(mismatches))
        trace.append({"step": "reserve_child_execution", "digest": _digest(child)})

        receipt = _object(self.ports.issue_receipt(pre, child), "BLOCK_DISPATCH_RECEIPT_INVALID")
        if receipt.get("ready") is not True or receipt.get("decision") not in {"DISPATCH_RECEIPT_ISSUED", "DISPATCH_RECEIPT_REPLAY"}:
            raise OrchestrationBlocked("BLOCK_DISPATCH_RECEIPT_NOT_READY", str(receipt.get("decision")))
        _required(receipt, ("receipt_id", "receipt_sha256"), "BLOCK_DISPATCH_RECEIPT_EVIDENCE_MISSING")
        trace.append({"step": "issue_dispatch_receipt", "digest": receipt["receipt_sha256"]})

        guard = _object(self.ports.read_entry_guard(pre, child, receipt), "BLOCK_ENTRY_GUARD_INVALID")
        if guard.get("ready") is not True or guard.get("decision") != "ORCHESTRATOR_ENTRY_ACCEPTED":
            raise OrchestrationBlocked("BLOCK_ENTRY_GUARD_NOT_ACCEPTED", str(guard.get("decision")))
        if str(guard.get("receipt_id")) != str(receipt["receipt_id"]):
            raise OrchestrationBlocked("BLOCK_ENTRY_GUARD_RECEIPT_MISMATCH")
        trace.append({"step": "entry_guard_readback", "digest": _digest(guard)})

        final = _object(self.ports.finalize_task_packet(pre, receipt, guard), "BLOCK_FINAL_TASK_PACKET_INVALID")
        if final.get("status") != "READY_TO_ENQUEUE" or final.get("decision") != "PROFILE_EXECUTION_AUTHORITY_FINALIZED":
            raise OrchestrationBlocked("BLOCK_FINAL_TASK_PACKET_NOT_READY", str(final.get("decision")))
        if final.get("task_packet_work_digest") != pre["task_packet_work_digest"]:
            raise OrchestrationBlocked("BLOCK_FINAL_TASK_PACKET_WORK_DIGEST_MISMATCH")
        _required(final, ("final_task_packet_digest", "enqueue_action"), "BLOCK_FINAL_TASK_PACKET_EVIDENCE_MISSING")
        trace.append({"step": "finalize_task_packet", "digest": final["final_task_packet_digest"]})

        dispatch = _object(self.ports.dispatch_worker(final), "BLOCK_WORKER_DISPATCH_INVALID")
        _required(dispatch, ("worker_dispatch_ref", "child_execution_id", "worker_kind"), "BLOCK_WORKER_DISPATCH_EVIDENCE_MISSING")
        if dispatch["child_execution_id"] != child["execution_id"] or dispatch["worker_kind"] != binding_seed["worker_kind"]:
            raise OrchestrationBlocked("BLOCK_WORKER_DISPATCH_CROSSBIND_MISMATCH")
        trace.append({"step": "dispatch_worker", "digest": _digest(dispatch)})

        worker_result = _object(self.ports.collect_worker_result(dispatch), "BLOCK_WORKER_RESULT_INVALID")
        _required(worker_result, ("worker_result_ref", "child_execution_id", "output_digest", "runtime_completion", "profile_contract_valid"), "BLOCK_WORKER_RESULT_EVIDENCE_MISSING")
        if worker_result["child_execution_id"] != child["execution_id"]:
            raise OrchestrationBlocked("BLOCK_WORKER_RESULT_CHILD_MISMATCH")
        if worker_result["runtime_completion"] != "PASS" or worker_result["profile_contract_valid"] != "PASS":
            raise OrchestrationBlocked("BLOCK_WORKER_RUNTIME_OR_CONTRACT_NOT_PASS")
        trace.append({"step": "collect_worker_result", "digest": worker_result["output_digest"]})

        judge = _object(self.ports.execute_step_judge(step, worker_result), "BLOCK_STEP_JUDGE_INVALID")
        _required(judge, ("judge_code", "judge_result", "judge_execution_ref", "executor_identity", "worker_identity"), "BLOCK_STEP_JUDGE_EVIDENCE_MISSING")
        if judge["judge_code"] != step["judge_code"] or judge["executor_identity"] == judge["worker_identity"]:
            raise OrchestrationBlocked("BLOCK_STEP_JUDGE_INDEPENDENCE_OR_IDENTITY_MISMATCH")
        if judge["judge_result"] not in {"PASS_WITH_EVIDENCE", "PASS"}:
            raise OrchestrationBlocked("BLOCK_STEP_JUDGE_NOT_PASS", str(judge["judge_result"]))
        trace.append({"step": "step_judge_handoff", "digest": _digest(judge)})

        checkpoint_payload = {
            "orchestration_execution_id": orchestration_execution_id,
            "parent_execution_id": parent_execution_id,
            "skill_code": parent["skill_code"],
            "source_revision": parent["source_revision"],
            "step_id": step["step_id"],
            "worker_ref": binding_seed["worker_ref"],
            "child_execution_id": child["execution_id"],
            "task_packet_work_digest": pre["task_packet_work_digest"],
            "final_task_packet_digest": final["final_task_packet_digest"],
            "output_digest": worker_result["output_digest"],
            "judge_code": judge["judge_code"],
            "judge_result": judge["judge_result"],
            "no_runtime_activation": True,
            "no_production_activation": True,
            "trace": trace,
        }
        checkpoint = _object(self.ports.checkpoint(checkpoint_payload), "BLOCK_CHECKPOINT_INVALID")
        if checkpoint.get("status") != "RECORDED" or checkpoint.get("no_runtime_activation") is not True or checkpoint.get("no_production_activation") is not True:
            raise OrchestrationBlocked("BLOCK_CHECKPOINT_NOT_CLEAN")

        result = {
            "schema_version": "LF_SKILL_ORCHESTRATION_STEP_RESULT_V1",
            "status": "PASS",
            "operation_code": self.OPERATION_CODE,
            "orchestration_execution_id": orchestration_execution_id,
            "parent_execution_id": parent_execution_id,
            "step_id": step["step_id"],
            "worker_ref": binding_seed["worker_ref"],
            "worker_kind": binding_seed["worker_kind"],
            "child_execution_id": child["execution_id"],
            "task_packet_work_digest": pre["task_packet_work_digest"],
            "final_task_packet_digest": final["final_task_packet_digest"],
            "output_digest": worker_result["output_digest"],
            "judge_code": judge["judge_code"],
            "judge_result": judge["judge_result"],
            "checkpoint_ref": checkpoint.get("checkpoint_ref"),
            "trace": trace,
        }
        result["result_digest"] = _digest(result)
        return result
