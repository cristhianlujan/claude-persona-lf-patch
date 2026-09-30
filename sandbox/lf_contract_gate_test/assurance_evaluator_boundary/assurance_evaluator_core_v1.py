#!/usr/bin/env python3
"""Deterministic semantic core for ASSURANCE_EVALUATOR.

Consumes already-resolved canonical snapshots. It does not query Supabase,
discover applicability, execute controls, write evidence, or own PASE closure.
Unsupported semantics fail closed to UNPROVEN.
"""
from __future__ import annotations

from typing import Any, Iterable, Mapping

INPUT_SCHEMA = "lf-assurance-evaluator-input/v1"
ACTIVATION_SCHEMA = "lf-assurance-activation-decision/v1"
OUTPUT_SCHEMA = "lf-assurance-evaluator-result/v1"
RESULTS = frozenset({"PASS", "FAIL", "OPEN", "UNPROVEN", "FALSE_PASS_RISK"})
CANONICAL_REVIEW_TYPES = frozenset({"INDEPENDENT_REVIEW", "INDEPENDENT_HOLDOUT"})
ACCEPTED_REVIEW_STATUSES = frozenset(
    {"ACCEPTED_NEW_REVIEW_REFERENCE", "ACCEPTED_HISTORICAL_LEGACY_READBACK"}
)
SUPPORTED_CLOSURE_KEYS = frozenset(
    {
        "open_defeater_blocks_pass",
        "zero_effect_required",
        "independent_review_required",
        "self_assessment_forbidden",
        "exact_head_readback_required",
    }
)


class AssuranceEvaluatorError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise AssuranceEvaluatorError(code)
    return value.strip()


def _int(value: Any, code: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise AssuranceEvaluatorError(code)
    return value


def _bool(value: Any, code: str) -> bool:
    if not isinstance(value, bool):
        raise AssuranceEvaluatorError(code)
    return value


def _mapping(value: Any, code: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise AssuranceEvaluatorError(code)
    return value


def _sequence(value: Any, code: str) -> tuple[Any, ...]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Iterable):
        raise AssuranceEvaluatorError(code)
    return tuple(value)


def _result(status: str, **kwargs: Any) -> dict[str, Any]:
    out = {"schema_version": OUTPUT_SCHEMA, "result": status}
    out.update(kwargs)
    return out


def evaluate_assurance(packet: Mapping[str, Any]) -> dict[str, Any]:
    """Evaluate material-claim sufficiency from canonical caller snapshots."""
    try:
        if not isinstance(packet, Mapping):
            raise AssuranceEvaluatorError("BLOCKED_INPUT_SHAPE")
        expected = {
            "schema_version",
            "activation",
            "claim",
            "obligations",
            "defeaters",
            "evidence",
            "review_decisions",
        }
        if set(packet) != expected:
            raise AssuranceEvaluatorError(
                "BLOCKED_INPUT_FIELDS", ",".join(sorted(set(packet) ^ expected))
            )
        if packet["schema_version"] != INPUT_SCHEMA:
            raise AssuranceEvaluatorError("BLOCKED_INPUT_SCHEMA")

        activation = _mapping(packet["activation"], "BLOCKED_ACTIVATION_SHAPE")
        if activation.get("schema_version") != ACTIVATION_SCHEMA:
            raise AssuranceEvaluatorError("BLOCKED_ACTIVATION_SCHEMA")
        if activation.get("status") != "READY_FOR_ASSURANCE_EVALUATOR":
            raise AssuranceEvaluatorError(
                "BLOCKED_ACTIVATION_NOT_READY", str(activation.get("status"))
            )
        if activation.get("execute_assurance") is not True:
            raise AssuranceEvaluatorError("BLOCKED_ACTIVATION_EXECUTE_FLAG")

        subject_type = _text(activation.get("subject_type"), "BLOCKED_SUBJECT_TYPE")
        subject_code = _text(activation.get("subject_code"), "BLOCKED_SUBJECT_CODE")
        subject_revision = _text(
            activation.get("subject_revision"), "BLOCKED_SUBJECT_REVISION"
        )
        binding_code = _text(activation.get("binding_code"), "BLOCKED_BINDING_CODE")
        claim_code = _text(activation.get("claim_code"), "BLOCKED_CLAIM_CODE")
        claim_version = _int(activation.get("claim_version"), "BLOCKED_CLAIM_VERSION")

        claim = _mapping(packet["claim"], "BLOCKED_CLAIM_SHAPE")
        required_claim_fields = {
            "claim_code",
            "claim_version",
            "subject_type",
            "subject_code",
            "status",
            "closure_rule",
        }
        missing = sorted(required_claim_fields - set(claim))
        if missing:
            raise AssuranceEvaluatorError("BLOCKED_CLAIM_FIELDS", ",".join(missing))
        if (
            claim.get("claim_code") != claim_code
            or claim.get("claim_version") != claim_version
            or claim.get("subject_type") != subject_type
            or claim.get("subject_code") not in (subject_code, "*")
        ):
            raise AssuranceEvaluatorError("BLOCKED_CLAIM_ACTIVATION_MISMATCH")

        claim_status = _text(claim.get("status"), "BLOCKED_CLAIM_STATUS")
        closure_rule = _mapping(claim.get("closure_rule"), "BLOCKED_CLOSURE_RULE_SHAPE")
        unsupported = sorted(set(closure_rule) - SUPPORTED_CLOSURE_KEYS)

        obligations = tuple(
            _mapping(x, "BLOCKED_OBLIGATION_SHAPE")
            for x in _sequence(packet["obligations"], "BLOCKED_OBLIGATIONS_SHAPE")
        )
        defeaters = tuple(
            _mapping(x, "BLOCKED_DEFEATER_SHAPE")
            for x in _sequence(packet["defeaters"], "BLOCKED_DEFEATERS_SHAPE")
        )
        evidence = tuple(
            _mapping(x, "BLOCKED_EVIDENCE_SHAPE")
            for x in _sequence(packet["evidence"], "BLOCKED_EVIDENCE_LIST_SHAPE")
        )
        reviews = tuple(
            _mapping(x, "BLOCKED_REVIEW_DECISION_SHAPE")
            for x in _sequence(packet["review_decisions"], "BLOCKED_REVIEW_DECISIONS_SHAPE")
        )

        accepted_review_ids: set[str] = set()
        accepted_review_types: set[str] = set()
        for review in reviews:
            status = _text(review.get("status"), "BLOCKED_REVIEW_DECISION_STATUS")
            if status not in ACCEPTED_REVIEW_STATUSES:
                raise AssuranceEvaluatorError("BLOCKED_REVIEW_DECISION_NOT_ACCEPTED", status)
            review_id = _text(review.get("judge_result_id"), "BLOCKED_REVIEW_JUDGE_RESULT_ID")
            review_type = _text(review.get("review_type"), "BLOCKED_REVIEW_DECISION_TYPE")
            if status == "ACCEPTED_NEW_REVIEW_REFERENCE" and review_type not in CANONICAL_REVIEW_TYPES:
                raise AssuranceEvaluatorError("BLOCKED_NON_CANONICAL_NEW_REVIEW_TYPE", review_type)
            accepted_review_ids.add(review_id)
            accepted_review_types.add(review_type)

        evidence_by_obligation: dict[str, list[Mapping[str, Any]]] = {}
        any_false_pass = False
        any_fail = False
        any_open = False
        any_unproven = False
        any_zero_effect = False
        evidence_refs: list[str] = []

        for item in evidence:
            evidence_ref = _text(item.get("evidence_ref"), "BLOCKED_EVIDENCE_REF")
            obligation_code = _text(
                item.get("obligation_code"), "BLOCKED_EVIDENCE_OBLIGATION_CODE"
            )
            revision = _text(item.get("subject_revision"), "BLOCKED_EVIDENCE_SUBJECT_REVISION")
            result = _text(item.get("result"), "BLOCKED_EVIDENCE_RESULT")
            if result not in RESULTS:
                raise AssuranceEvaluatorError("BLOCKED_EVIDENCE_RESULT", result)
            durable = _bool(item.get("durable"), "BLOCKED_EVIDENCE_DURABLE")
            zero_effect = _bool(item.get("zero_effect_proven"), "BLOCKED_EVIDENCE_ZERO_EFFECT")
            review_id = item.get("judge_result_id")
            if review_id is not None:
                review_id = _text(review_id, "BLOCKED_EVIDENCE_JUDGE_RESULT_ID")
                if review_id not in accepted_review_ids:
                    raise AssuranceEvaluatorError("BLOCKED_EVIDENCE_REVIEW_NOT_GUARDED", review_id)

            normalized = dict(item)
            normalized["_exact_revision"] = revision == subject_revision
            normalized["_durable"] = durable
            evidence_by_obligation.setdefault(obligation_code, []).append(normalized)
            evidence_refs.append(evidence_ref)
            any_zero_effect = any_zero_effect or zero_effect

        required_obligations = []
        for obligation in obligations:
            fields = {
                "obligation_code",
                "claim_code",
                "claim_version",
                "required",
                "status",
                "verification_method",
            }
            missing = sorted(fields - set(obligation))
            if missing:
                raise AssuranceEvaluatorError("BLOCKED_OBLIGATION_FIELDS", ",".join(missing))
            if obligation.get("claim_code") != claim_code or obligation.get("claim_version") != claim_version:
                raise AssuranceEvaluatorError("BLOCKED_OBLIGATION_CLAIM_MISMATCH")
            if not _bool(obligation.get("required"), "BLOCKED_OBLIGATION_REQUIRED"):
                continue
            required_obligations.append(obligation)

            obligation_code = _text(obligation.get("obligation_code"), "BLOCKED_OBLIGATION_CODE")
            status = _text(obligation.get("status"), "BLOCKED_OBLIGATION_STATUS")
            verification_method = _text(
                obligation.get("verification_method"), "BLOCKED_OBLIGATION_VERIFICATION_METHOD"
            )
            if status != "ACTIVE":
                any_unproven = True
                continue

            rows = evidence_by_obligation.get(obligation_code, [])
            exact_rows = [r for r in rows if r["_exact_revision"]]
            durable_rows = [r for r in exact_rows if r["_durable"]]
            if not rows or not exact_rows or not durable_rows:
                any_unproven = True
                continue

            results = {r["result"] for r in durable_rows}
            if "FAIL" in results:
                any_fail = True
            elif "FALSE_PASS_RISK" in results:
                any_false_pass = True
            elif "OPEN" in results:
                any_open = True
            elif "UNPROVEN" in results:
                any_unproven = True
            elif results != {"PASS"}:
                any_unproven = True

            if verification_method == "INDEPENDENT_REVIEW":
                guarded_ids = {
                    r.get("judge_result_id")
                    for r in durable_rows
                    if r.get("judge_result_id") in accepted_review_ids
                }
                if not guarded_ids:
                    any_unproven = True

        mandatory_defeaters = []
        open_defeaters: list[str] = []
        closed_defeaters: list[str] = []
        for defeater in defeaters:
            fields = {
                "defeater_code",
                "claim_code",
                "claim_version",
                "mandatory",
                "status",
                "closed",
            }
            missing = sorted(fields - set(defeater))
            if missing:
                raise AssuranceEvaluatorError("BLOCKED_DEFEATER_FIELDS", ",".join(missing))
            if defeater.get("claim_code") != claim_code or defeater.get("claim_version") != claim_version:
                raise AssuranceEvaluatorError("BLOCKED_DEFEATER_CLAIM_MISMATCH")
            if not _bool(defeater.get("mandatory"), "BLOCKED_DEFEATER_MANDATORY"):
                continue
            mandatory_defeaters.append(defeater)
            code = _text(defeater.get("defeater_code"), "BLOCKED_DEFEATER_CODE")
            if _text(defeater.get("status"), "BLOCKED_DEFEATER_STATUS") != "ACTIVE":
                any_unproven = True
                open_defeaters.append(code)
                continue
            if _bool(defeater.get("closed"), "BLOCKED_DEFEATER_CLOSED"):
                closed_defeaters.append(code)
            else:
                open_defeaters.append(code)

        reasons: list[str] = []
        if claim_status != "ACTIVE":
            any_unproven = True
            reasons.append("CLAIM_NOT_ACTIVE")
        if unsupported:
            any_unproven = True
            reasons.append("UNSUPPORTED_CLOSURE_KEYS:" + ",".join(unsupported))
        if not required_obligations:
            any_unproven = True
            reasons.append("NO_REQUIRED_OBLIGATIONS")
        if closure_rule.get("zero_effect_required") is True and not any_zero_effect:
            any_unproven = True
            reasons.append("ZERO_EFFECT_UNPROVEN")
        if closure_rule.get("independent_review_required") is True and not accepted_review_ids:
            any_unproven = True
            reasons.append("INDEPENDENT_REVIEW_UNPROVEN")
        if closure_rule.get("self_assessment_forbidden") not in (None, True, False):
            any_unproven = True
            reasons.append("SELF_ASSESSMENT_RULE_UNSUPPORTED")
        if closure_rule.get("exact_head_readback_required") is True:
            if not all(
                r["_exact_revision"]
                for rows in evidence_by_obligation.values()
                for r in rows
            ):
                any_unproven = True
                reasons.append("EXACT_HEAD_READBACK_UNPROVEN")

        open_blocks = closure_rule.get("open_defeater_blocks_pass", True)
        if not isinstance(open_blocks, bool):
            any_unproven = True
            reasons.append("OPEN_DEFEATER_RULE_INVALID")
            open_blocks = True
        if open_defeaters and open_blocks:
            any_false_pass = True
            reasons.append("MANDATORY_DEFEATER_NOT_CLOSED")

        if any_fail:
            result = "FAIL"
        elif any_false_pass:
            result = "FALSE_PASS_RISK"
        elif any_open:
            result = "OPEN"
        elif any_unproven:
            result = "UNPROVEN"
        else:
            result = "PASS"

        return _result(
            result,
            subject_type=subject_type,
            subject_code=subject_code,
            subject_revision=subject_revision,
            binding_code=binding_code,
            claim_code=claim_code,
            claim_version=claim_version,
            required_obligation_count=len(required_obligations),
            mandatory_defeater_count=len(mandatory_defeaters),
            open_defeaters=sorted(open_defeaters),
            closed_defeaters=sorted(closed_defeaters),
            evidence_refs=sorted(set(evidence_refs)),
            accepted_review_types=sorted(accepted_review_types),
            reasons=reasons,
        )
    except AssuranceEvaluatorError as exc:
        return _result(
            "UNPROVEN",
            blocked=True,
            reason_code=exc.code,
            detail=exc.detail,
            evidence_refs=[],
            open_defeaters=[],
            closed_defeaters=[],
        )
