#!/usr/bin/env python3
"""Deterministic activation gate for ASSURANCE_EVALUATOR.

The gate does not discover applicability, query Supabase, execute Assurance,
or mutate any authority. It only validates one Router decision against a
caller-supplied readback of the canonical subject binding table.
"""
from __future__ import annotations

from typing import Any, Iterable, Mapping

ROUTER_SCHEMA = "lf-assurance-router-decision/v1"
APP_AUTHORITY = "CHANGESET_GOVERNANCE_LF_V1"
ALLOWED_SUBJECT_TYPES = frozenset(
    {"WORKFLOW", "OPERATION", "STRATEGY", "PROFILE", "CARD", "ADAPTER", "SKILL", "CAPABILITY"}
)
ALLOWED_BINDING_STATUSES = frozenset({"CANDIDATO", "ACTIVE", "RETIRED"})


class AssuranceActivationError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _require_text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise AssuranceActivationError(code)
    return value.strip()


def _validate_router_decision(router_decision: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(router_decision, Mapping):
        raise AssuranceActivationError("BLOCKED_ROUTER_DECISION_SHAPE")
    expected = {
        "schema_version",
        "applicability_authority",
        "assurance_applicable",
        "subject_type",
        "subject_code",
        "subject_revision",
        "decision_ref",
    }
    if set(router_decision) != expected:
        raise AssuranceActivationError(
            "BLOCKED_ROUTER_DECISION_FIELDS",
            ",".join(sorted(set(router_decision) ^ expected)),
        )

    if router_decision["schema_version"] != ROUTER_SCHEMA:
        raise AssuranceActivationError("BLOCKED_ROUTER_DECISION_SCHEMA")
    if router_decision["applicability_authority"] != APP_AUTHORITY:
        raise AssuranceActivationError("BLOCKED_APPLICABILITY_AUTHORITY")
    if not isinstance(router_decision["assurance_applicable"], bool):
        raise AssuranceActivationError("BLOCKED_ROUTER_APPLICABILITY_TYPE")

    subject_type = _require_text(router_decision["subject_type"], "BLOCKED_SUBJECT_TYPE")
    if subject_type not in ALLOWED_SUBJECT_TYPES:
        raise AssuranceActivationError("BLOCKED_SUBJECT_TYPE", subject_type)
    subject_code = _require_text(router_decision["subject_code"], "BLOCKED_SUBJECT_CODE")
    if subject_code == "*":
        raise AssuranceActivationError("BLOCKED_NON_EXACT_ROUTER_SUBJECT")
    subject_revision = _require_text(
        router_decision["subject_revision"], "BLOCKED_SUBJECT_REVISION"
    )
    decision_ref = _require_text(router_decision["decision_ref"], "BLOCKED_DECISION_REF")

    return {
        "assurance_applicable": router_decision["assurance_applicable"],
        "subject_type": subject_type,
        "subject_code": subject_code,
        "subject_revision": subject_revision,
        "decision_ref": decision_ref,
    }


def _validate_binding(row: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(row, Mapping):
        raise AssuranceActivationError("BLOCKED_BINDING_SHAPE")
    required = {
        "binding_code",
        "subject_type",
        "subject_code",
        "standard_claim_code",
        "standard_claim_version",
        "status",
    }
    missing = sorted(required - set(row))
    if missing:
        raise AssuranceActivationError("BLOCKED_BINDING_FIELDS", ",".join(missing))

    binding_code = _require_text(row["binding_code"], "BLOCKED_BINDING_CODE")
    subject_type = _require_text(row["subject_type"], "BLOCKED_BINDING_SUBJECT_TYPE")
    if subject_type not in ALLOWED_SUBJECT_TYPES:
        raise AssuranceActivationError("BLOCKED_BINDING_SUBJECT_TYPE", subject_type)
    subject_code = _require_text(row["subject_code"], "BLOCKED_BINDING_SUBJECT_CODE")
    claim_code = _require_text(row["standard_claim_code"], "BLOCKED_BINDING_CLAIM_CODE")
    claim_version = row["standard_claim_version"]
    if not isinstance(claim_version, int) or isinstance(claim_version, bool) or claim_version <= 0:
        raise AssuranceActivationError("BLOCKED_BINDING_CLAIM_VERSION", binding_code)
    status = _require_text(row["status"], "BLOCKED_BINDING_STATUS")
    if status not in ALLOWED_BINDING_STATUSES:
        raise AssuranceActivationError("BLOCKED_BINDING_STATUS", f"{binding_code}:{status}")

    return {
        "binding_code": binding_code,
        "subject_type": subject_type,
        "subject_code": subject_code,
        "standard_claim_code": claim_code,
        "standard_claim_version": claim_version,
        "status": status,
    }


def resolve_assurance_activation(
    *,
    router_decision: Mapping[str, Any],
    subject_bindings: Iterable[Mapping[str, Any]],
) -> dict[str, Any]:
    """Resolve whether the Assurance evaluator is allowed to run.

    READY does not execute the evaluator. It only proves that the Router
    explicitly declared applicability and that exactly one ACTIVE exact binding
    exists for the same subject.
    """
    try:
        decision = _validate_router_decision(router_decision)
        bindings = tuple(_validate_binding(row) for row in subject_bindings)

        if not decision["assurance_applicable"]:
            return {
                "schema_version": "lf-assurance-activation-decision/v1",
                "status": "NOT_APPLICABLE_NO_EXECUTION",
                "execute_assurance": False,
                "reason_code": "ROUTER_NOT_APPLICABLE",
                "subject_type": decision["subject_type"],
                "subject_code": decision["subject_code"],
                "subject_revision": decision["subject_revision"],
                "decision_ref": decision["decision_ref"],
                "binding_code": None,
                "claim_code": None,
                "claim_version": None,
            }

        active_same_type = tuple(
            row
            for row in bindings
            if row["status"] == "ACTIVE" and row["subject_type"] == decision["subject_type"]
        )
        active_wildcards = tuple(row for row in active_same_type if row["subject_code"] == "*")
        if active_wildcards:
            raise AssuranceActivationError(
                "BLOCKED_NON_EXACT_ACTIVE_BINDING",
                ",".join(sorted(row["binding_code"] for row in active_wildcards)),
            )

        exact = tuple(
            row
            for row in active_same_type
            if row["subject_code"] == decision["subject_code"]
        )
        if not exact:
            return {
                "schema_version": "lf-assurance-activation-decision/v1",
                "status": "NOT_APPLICABLE_NO_EXECUTION",
                "execute_assurance": False,
                "reason_code": "NO_ACTIVE_EXACT_BINDING",
                "subject_type": decision["subject_type"],
                "subject_code": decision["subject_code"],
                "subject_revision": decision["subject_revision"],
                "decision_ref": decision["decision_ref"],
                "binding_code": None,
                "claim_code": None,
                "claim_version": None,
            }
        if len(exact) != 1:
            raise AssuranceActivationError(
                "BLOCKED_AMBIGUOUS_ACTIVE_BINDING",
                ",".join(sorted(row["binding_code"] for row in exact)),
            )

        binding = exact[0]
        return {
            "schema_version": "lf-assurance-activation-decision/v1",
            "status": "READY_FOR_ASSURANCE_EVALUATOR",
            "execute_assurance": True,
            "reason_code": "EXACT_ACTIVE_BINDING",
            "subject_type": decision["subject_type"],
            "subject_code": decision["subject_code"],
            "subject_revision": decision["subject_revision"],
            "decision_ref": decision["decision_ref"],
            "binding_code": binding["binding_code"],
            "claim_code": binding["standard_claim_code"],
            "claim_version": binding["standard_claim_version"],
        }
    except AssuranceActivationError as exc:
        return {
            "schema_version": "lf-assurance-activation-decision/v1",
            "status": "BLOCKED",
            "execute_assurance": False,
            "reason_code": exc.code,
            "detail": exc.detail,
        }
