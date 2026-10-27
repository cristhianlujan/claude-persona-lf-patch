"""Synthetic-only caller design executable. No DB, network, scheduler or model.

Ports in this simulation must explicitly declare synthetic=True. This is not an
operational adapter or authorization boundary. Returned notices never authorize
execution. The SQL ledger, not Python, owns binding_key_sha256.
"""
from copy import deepcopy
import hashlib
import json
import re
from uuid import UUID

FIELDS = {"context_id", "context_sha256", "target_ref", "requested_scope_ids",
          "producer_execution_ref", "entry_contract_digest_sha256"}
HEX = re.compile(r"^[0-9a-f]{64}$")


def normalized_handoff(handoff):
    if not isinstance(handoff, dict) or set(handoff) != FIELDS:
        raise ValueError("CALLER_HANDOFF_INVALID")
    result = deepcopy(handoff)
    for field in FIELDS - {"requested_scope_ids"}:
        if not isinstance(result[field], str) or not result[field].strip():
            raise ValueError("CALLER_HANDOFF_INVALID")
    try:
        if str(UUID(result["context_id"])) != result["context_id"]:
            raise ValueError("CALLER_HANDOFF_INVALID")
    except (ValueError, AttributeError) as exc:
        raise ValueError("CALLER_HANDOFF_INVALID") from exc
    for field in ("context_sha256", "entry_contract_digest_sha256"):
        if not HEX.fullmatch(result[field]):
            raise ValueError("CALLER_HANDOFF_INVALID")
    scopes = result["requested_scope_ids"]
    if (not isinstance(scopes, list) or not scopes
            or any(not isinstance(s, str) or not s.strip() for s in scopes)):
        raise ValueError("CALLER_HANDOFF_INVALID")
    result["requested_scope_ids"] = sorted(set(scopes))
    return result


def caller_request_identity(source_execution_id, router_binding, handoff):
    """Own namespaced fingerprint; deliberately NOT PostgreSQL's D7 digest."""
    binding = normalized_handoff(handoff)
    if (not isinstance(source_execution_id, str) or not source_execution_id.strip()
            or binding["producer_execution_ref"] != source_execution_id
            or not isinstance(router_binding, dict) or not router_binding):
        raise ValueError("CALLER_SOURCE_OR_BINDING_INVALID")
    body = {"schema_version": "PG01_SYNTHETIC_CALLER_REQUEST_IDENTITY_V1",
            "source_execution_id": source_execution_id,
            "router_action_binding": deepcopy(router_binding), "handoff": binding}
    raw = json.dumps(body, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=False, allow_nan=False).encode("utf-8")
    return "caller-sha256:" + hashlib.sha256(raw).hexdigest()


def simulate_caller(source_execution_id, ports, *, max_attempts=3):
    """Exercise the proposed ordering against in-memory synthetic ports only.

    No cached positive admission: every invocation rechecks terminal, context,
    judge and V2 currentness. Transient faults retry only the failed stage.
    Retry delays and durable recovery remain operational design decisions.
    """
    if getattr(ports, "synthetic", None) is not True:
        raise ValueError("SYNTHETIC_PORTS_REQUIRED")
    if type(max_attempts) is not int or not 1 <= max_attempts <= 3:
        raise ValueError("ATTEMPT_LIMIT_INVALID")
    trace = []
    identity = None

    def result(state):
        return {"state": state, "trace": trace, "caller_request_identity": identity,
                "operational_admission": False, "downstream_execution_allowed": False}

    def read(stage, payload):
        for attempt in range(1, max_attempts + 1):
            trace.append({"stage": stage, "attempt": attempt})
            try:
                value = ports.call(stage, deepcopy(payload))
                if not isinstance(value, dict):
                    raise ValueError("READBACK_NOT_OBJECT")
                return value
            except (TimeoutError, ConnectionError):
                if attempt == max_attempts:
                    raise

    try:
        terminal = read("terminal", {"source_execution_id": source_execution_id})
        if (terminal.get("state") != "PASS"
                or terminal.get("execution_id") != source_execution_id):
            return result("WAITING_TERMINAL")
        prepared = read("prepare", {"source_execution_id": source_execution_id})
        request = prepared.get("programming_admission_request")
        if not isinstance(request, dict):
            return result("NO_PROGRAMMING_CONTINUATION")
        if request.get("source_execution_id") != source_execution_id:
            return result("SOURCE_MISMATCH")
        h = normalized_handoff(request.get("programming_handoff"))
        identity = caller_request_identity(source_execution_id,
                                          request.get("router_action_binding"), h)
        context = read("context", {"context_id": h["context_id"]})
        if (context.get("context_id") != h["context_id"]
                or context.get("context_sha256") != h["context_sha256"]
                or context.get("created_by_execution_id") != source_execution_id):
            return result("SNAPSHOT_SOURCE_MISMATCH")
        judge = read("judge", {"context_sha256": context["context_sha256"]})
        if judge.get("state") == "MISSING":
            return result("WAITING_INDEPENDENT_JUDGE")
        if (judge.get("state") != "VERIFIED"
                or judge.get("subject_sha256") != h["context_sha256"]
                or not isinstance(judge.get("execution_id"), str)
                or not judge["execution_id"].strip()):
            return result("JUDGE_INVALID")
        payload = {"request": request, "judge_execution_id": judge["execution_id"]}
        recorded = read("record", payload)
        if recorded.get("status") not in ("RECORDED", "IDEMPOTENT_REPLAY"):
            return result("RECEIPT_WRITE_BLOCKED")
        resolved = read("resolve", {"programming_handoff": h})
        if resolved.get("admissible") is not True:
            return result("RETURN_TO_ANALYSIS_NO_CODE")
        admitted = read("admit", request)
        if admitted.get("downstream_execution_allowed") is not False:
            return result("UNEXPECTED_EFFECT_AUTHORITY")
        if admitted.get("paso") != "PROGRAMACION_DESARROLLO_ADMITIDO":
            return result("ADMISSION_BLOCKED")
        return result("SYNTHETIC_ADMISSION_OBSERVED")
    except (TimeoutError, ConnectionError):
        return result("TRANSIENT_RETRIES_EXHAUSTED")
    except (ValueError, TypeError, KeyError):
        return result("INVALID_SYNTHETIC_READBACK")
