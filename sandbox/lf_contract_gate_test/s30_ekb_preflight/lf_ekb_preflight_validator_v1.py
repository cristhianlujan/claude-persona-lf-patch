#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from typing import Any

ACTIVE_STATES = {"activo", "active", "abierto", "open"}
HIGH = {"high", "critical", "alta", "alto", "critica", "crítica", "p0"}
MODES = {"DETERMINISTIC_CHECK", "PROCESS_EVIDENCE", "HUMAN_REVIEW"}
PASS_SHA = re.compile(r"^[0-9a-f]{64}$")


def _norm(value: Any) -> str:
    return str(value or "").strip().lower()


def _is_active(row: dict[str, Any]) -> bool:
    # Frozen v1 fixtures predate explicit estado capture; preserve them as active.
    # Live/current fixtures must carry estado and are normalized to Router semantics.
    if "estado" not in row:
        return True
    return _norm(row.get("estado")) in ACTIVE_STATES


def _fingerprint(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def resolve(case: dict[str, Any]) -> dict[str, Any]:
    errors = list(case.get("errors") or [])
    phases = {_norm(x) for x in case.get("lifecycle_phases") or [] if _norm(x)}
    roles = {_norm(x) for x in case.get("consumer_roles") or [] if _norm(x)}
    required = {str(x).strip() for x in case.get("required_codes") or [] if str(x).strip()}
    rules = case.get("active_rule_codes_by_error") or {}

    if not phases or not roles:
        return {"result": "BLOCK_EKB_CONTEXT_EMPTY", "pass": False}

    active_rows = [row for row in errors if row.get("codigo") and _is_active(row)]
    counts = Counter(str(row.get("codigo") or "") for row in active_rows)
    duplicate = sorted(code for code, count in counts.items() if code and count != 1)
    if duplicate:
        return {"result": "BLOCK_EKB_DUPLICATE_ACTIVE_CODE", "pass": False, "duplicate_active_codes": duplicate}

    active = {str(row.get("codigo")): row for row in active_rows}
    missing_required = sorted(required - set(active))
    if missing_required:
        return {"result": "BLOCK_EKB_REQUIRED_CODE_MISSING", "pass": False, "missing_required_codes": missing_required}

    selected: dict[str, dict[str, Any]] = {}
    for code, row in active.items():
        row_roles = {_norm(x) for x in row.get("consumer_role") or [] if _norm(x)}
        context_match = _norm(row.get("lifecycle_phase")) in phases and bool(row_roles & roles)
        if code in required or context_match:
            selected[code] = row

    selected_codes = sorted(selected)
    unhandled = sorted(
        code
        for code, row in selected.items()
        if _norm(row.get("severidad")) in HIGH
        and not bool(row.get("has_inline_prevention"))
        and not bool(rules.get(code))
    )
    if unhandled:
        return {
            "result": "BLOCK_EKB_UNHANDLED_HIGH_CRITICAL",
            "pass": False,
            "matched_error_codes": selected_codes,
            "unhandled_high_critical_codes": unhandled,
        }

    control_codes = sorted(
        required
        | {
            code
            for code, row in selected.items()
            if _norm(row.get("severidad")) in HIGH
        }
    )

    coverage = case.get("control_coverage") or {}
    if coverage.get("coverage_version") != "LF_EKB_CONTROL_COVERAGE_V1" or not isinstance(coverage.get("bindings"), list):
        return {"result": "BLOCK_EKB_CONTROL_COVERAGE_INCOMPLETE", "pass": False, "reason": "COVERAGE_SHAPE_INVALID"}

    bindings = coverage["bindings"]
    binding_counts = Counter(str(row.get("error_code") or "") for row in bindings)
    missing_bindings = sorted(code for code in control_codes if binding_counts[code] == 0)
    duplicate_bindings = sorted(code for code in control_codes if binding_counts[code] > 1)
    unknown_bindings = sorted(code for code in binding_counts if code and code not in selected)
    if missing_bindings or duplicate_bindings or unknown_bindings:
        return {
            "result": "BLOCK_EKB_CONTROL_COVERAGE_INCOMPLETE",
            "pass": False,
            "matched_error_codes": selected_codes,
            "required_control_codes": control_codes,
            "missing_control_bindings": missing_bindings,
            "duplicate_control_bindings": duplicate_bindings,
            "unknown_control_bindings": unknown_bindings,
        }

    pending: list[str] = []
    invalid: list[str] = []
    blocked: list[str] = []
    by_code = {str(row.get("error_code")): row for row in bindings}
    for code in control_codes:
        binding = by_code[code]
        mode = str(binding.get("control_mode") or "")
        status = str(binding.get("status") or "")
        if mode not in MODES or not str(binding.get("control_ref") or "").strip():
            invalid.append(code)
            continue
        if status == "BLOCKED":
            blocked.append(code)
            continue
        if status in {"PENDING", "REVIEW_REQUIRED"}:
            pending.append(code)
            continue
        if status != "PASS":
            invalid.append(code)
            continue
        if binding.get("executed") is not True:
            invalid.append(code)
            continue
        if not str(binding.get("evidence_ref") or "").strip():
            invalid.append(code)
            continue
        if not PASS_SHA.fullmatch(str(binding.get("evidence_sha256") or "")):
            invalid.append(code)
            continue

    if invalid or blocked:
        result = "BLOCK_EKB_CONTROL_EVIDENCE_INVALID"
        passed = False
    elif pending:
        result = "EKB_RESOLVED_CONTROLS_PENDING"
        passed = False
    else:
        result = "PASS_EKB_PREFLIGHT_CONTROLS_BOUND"
        passed = True

    inherited_rules = {
        code: sorted(set(str(x) for x in rules.get(code) or []))
        for code in selected_codes
        if rules.get(code)
    }
    receipt_core = {
        "result": result,
        "pass": passed,
        "operation_code": case.get("operation_code"),
        "lifecycle_phases": sorted(phases),
        "consumer_roles": sorted(roles),
        "required_codes": sorted(required),
        "matched_error_codes": selected_codes,
        "required_control_codes": control_codes,
        "inherited_active_rules": inherited_rules,
        "selected_categories": sorted({str(row.get("categoria")) for row in selected.values()}),
        "pending_control_bindings": sorted(pending),
        "blocked_control_bindings": sorted(blocked),
        "control_evidence_failures": sorted(invalid),
        "detectability_is_not_execution_evidence": True,
        "active_state_vocabulary": sorted(ACTIVE_STATES),
        "high_severity_vocabulary": sorted(HIGH),
    }
    return receipt_core | {"receipt_sha256": _fingerprint(receipt_core)}
