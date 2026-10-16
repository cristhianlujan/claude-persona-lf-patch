#!/usr/bin/env python3
"""A16Q_C2: fail-closed verification of a REAL Router -> consumer execution bundle.

This runner does not invoke models, write to a database, route requests or create
evidence. It validates a bundle previously captured from an independently
authorized real run. No fixture, fallback or producer assertion can become PASS.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

TEST_CODE = "ENG_A16Q_C2_ROUTER_CONSUMER_E2E"
SCHEMA = "PROGRAMMING_A16Q_C2_REAL_CONSUMER_EVIDENCE_V1"
CASES = ("PARTIAL_SCREEN_DEMO", "FULL_SCOPE", "TARGETED_MODIFICATION")
TRACE_FIELDS = (
    "literal_request", "router", "resolved_asset", "action", "operation",
    "scope_and_mode", "selected_profiles_skills_adapters",
    "input_governance_if_applicable", "applicable_contracts_and_guards",
    "real_consumer", "authorized_result", "receipts", "readback",
)
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
EXEC_RE = re.compile(r"^EXEC-[A-Za-z0-9_-]+$")
FAILURES = (
    "ROUTER_BYPASS", "INPUT_SHA_DRIFT", "EXCLUDED_TARGET",
    "UNAUTHORIZED_PROFILE", "STALE_AUTHORITY", "MISSING_RECEIPT",
)
PROHIBITED_EVIDENCE_MODES = frozenset(
    {"FIXTURE", "MOCK", "SIMULATION", "SYNTHETIC", "HISTORICAL_REPLAY"}
)


def _digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _sha(value: Any) -> bool:
    return isinstance(value, str) and SHA_RE.fullmatch(value) is not None


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _hash_part(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    return value[7:] if value.startswith("sha256:") else value


def _fail(errors: list[str], name: str, condition: bool) -> None:
    if not condition:
        errors.append(name)


def check_case(case_name: str, record: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(record, dict):
        return ["CASE_RECORD_NOT_OBJECT"]
    _fail(errors, "CASE_ID_MISMATCH", record.get("case_id") == case_name)
    _fail(errors, "NOT_REAL_EXECUTION", record.get("evidence_mode") == "REAL_AUTHORIZED_RUNTIME")
    trace = record.get("trace")
    if not isinstance(trace, dict):
        return errors + ["TRACE_NOT_OBJECT"]
    _fail(errors, "TRACE_FIELD_SET_INCOMPLETE",
          all(field in trace for field in TRACE_FIELDS))
    request = trace.get("literal_request")
    router = trace.get("router")
    asset = trace.get("resolved_asset")
    action = trace.get("action")
    operation = trace.get("operation")
    scope = trace.get("scope_and_mode")
    candidates = trace.get("selected_profiles_skills_adapters")
    ig = trace.get("input_governance_if_applicable")
    guards = trace.get("applicable_contracts_and_guards")
    consumer = trace.get("real_consumer")
    result = trace.get("authorized_result")
    receipts = trace.get("receipts")
    readback = trace.get("readback")
    if not all(isinstance(x, dict) for x in (
        request, router, asset, action, operation, scope,
        candidates, ig, guards, consumer, result, receipts, readback
    )):
        return errors + ["TRACE_OBJECT_INCOMPLETE"]

    literal = request.get("text")
    digest = _digest(literal) if _nonempty(literal) else None
    request_id = request.get("request_id")
    exec_id = operation.get("canonical_execution_id")
    source_sha = asset.get("source_sha256")
    _fail(errors, "REQUEST_ID_INVALID", _nonempty(request_id))
    _fail(errors, "LITERAL_OR_SHA_INVALID", digest is not None
          and _sha(digest) and _hash_part(request.get("sha256")) == digest)
    _fail(errors, "ROUTER_AUTHORITY_UNVERIFIED", router.get("router") == "ACT-0001"
          and router.get("status") in {"READY_TO_EXECUTE", "READY_INSPECTION"}
          and _nonempty(router.get("authority_receipt_ref"))
          and _sha(_hash_part(router.get("authority_receipt_sha256"))))
    _fail(errors, "ROUTER_INPUT_BINDING_MISSING",
          _hash_part(router.get("request_sha256")) == digest
          and router.get("request_id") == request_id)
    _fail(errors, "ASSET_SOURCE_NOT_ATTESTED", _nonempty(asset.get("asset_code"))
          and _sha(source_sha) and _nonempty(asset.get("source_ref"))
          and asset.get("currentness") == "CURRENT")
    _fail(errors, "ACTION_OPERATION_NOT_BOUND", _nonempty(action.get("action_code"))
          and _nonempty(operation.get("operation_code"))
          and action.get("operation_code") == operation.get("operation_code"))
    _fail(errors, "CANONICAL_EXECUTION_MISSING", _nonempty(exec_id)
          and EXEC_RE.fullmatch(exec_id) is not None)
    _fail(errors, "SCOPE_MISMATCH", scope.get("case_id") == case_name
          and scope.get("request_id") == request_id
          and _hash_part(scope.get("request_sha256")) == digest
          and isinstance(scope.get("exclusions"), list)
          and scope.get("exclusions_preserved") is True)
    _fail(errors, "WORKER_BINDING_UNRESOLVED", isinstance(candidates.get("profiles"), list)
          and isinstance(candidates.get("skills"), list)
          and isinstance(candidates.get("adapters"), list)
          and _nonempty(candidates.get("selection_receipt_ref")))
    _fail(errors, "INPUT_GOVERNANCE_INVALID", ig.get("status") in {"CURRENT", "NOT_APPLICABLE"}
          and (ig.get("status") == "NOT_APPLICABLE"
               or _nonempty(ig.get("current_receipt_ref"))))
    _fail(errors, "CONTRACT_GUARDS_INVALID", guards.get("currentness") == "CURRENT"
          and _nonempty(guards.get("contract_receipt_ref"))
          and guards.get("pre_execution_guard") == "PASS")
    _fail(errors, "CONSUMER_ID_NOT_BOUND", _nonempty(consumer.get("consumer_code"))
          and consumer.get("request_id") == request_id
          and consumer.get("canonical_execution_id") == exec_id
          and _hash_part(consumer.get("received_input_sha256")) == digest
          and _nonempty(consumer.get("router_authority_receipt_ref"))
          and _nonempty(consumer.get("runtime_dispatch_receipt_ref")))
    _fail(errors, "CONSUMER_SOURCE_NOT_BOUND",
          consumer.get("profile_source_sha256") == source_sha)
    raw_text = result.get("raw_output")
    raw_sha = _digest(raw_text) if isinstance(raw_text, str) else None
    _fail(errors, "RAW_OUTPUT_INVALID", _nonempty(raw_text)
          and _hash_part(result.get("raw_output_sha256")) == raw_sha
          and result.get("request_id") == request_id
          and result.get("canonical_execution_id") == exec_id)
    _fail(errors, "VALIDATOR_OR_SEMANTIC_JUDGE_UNATTESTED",
          result.get("contract_validator") == "PASS"
          and result.get("semantic_judge") == "PASS"
          and _nonempty(result.get("validation_receipt_ref")))
    _fail(errors, "RECEIPT_CHAIN_NOT_BOUND",
          _nonempty(receipts.get("router_authority_receipt_ref"))
          and receipts.get("router_authority_receipt_ref") == consumer.get("router_authority_receipt_ref")
          and receipts.get("canonical_execution_id") == exec_id
          and receipts.get("request_id") == request_id
          and _nonempty(receipts.get("operation_receipt_ref"))
          and _nonempty(receipts.get("consumer_receipt_ref"))
          and _nonempty(receipts.get("context_receipt_ref")))
    _fail(errors, "INDEPENDENT_READBACK_MISSING",
          readback.get("request_id") == request_id
          and readback.get("canonical_execution_id") == exec_id
          and _hash_part(readback.get("literal_sha256")) == digest
          and _hash_part(readback.get("raw_output_sha256")) == raw_sha
          and readback.get("source_sha256") == source_sha
          and readback.get("result_status") == "PASS"
          and _nonempty(readback.get("independent_readback_ref")))
    _fail(errors, "UNAUTHORIZED_WRITE", readback.get("production_changed") is False
          and readback.get("unauthorized_effects") == 0)
    return errors


def validate(bundle: Any) -> dict[str, Any]:
    errors: list[str] = []
    if not isinstance(bundle, dict):
        return {"status": "FAIL", "code": TEST_CODE, "errors": ["INVALID_BUNDLE"]}
    _fail(errors, "SCHEMA_MISMATCH", bundle.get("schema") == SCHEMA)
    _fail(errors, "REAL_PROVIDER_PROVENANCE_REQUIRED",
          bundle.get("evidence_mode") == "REAL_AUTHORIZED_RUNTIME"
          and bundle.get("evidence_mode") not in PROHIBITED_EVIDENCE_MODES)
    _fail(errors, "TRUSTED_PROVIDER_CAPTURE_MISSING",
          _nonempty(bundle.get("provider_execution_ref"))
          and _nonempty(bundle.get("independent_provider_readback_ref"))
          and _nonempty(bundle.get("source_head_sha256"))
          and _sha(bundle.get("source_head_sha256")))
    _fail(errors, "REAL_EXECUTION_NOT_ATTESTED",
          bundle.get("provider_attested") is True
          and bundle.get("independent_reviewer_attested") is True)
    cases = bundle.get("cases")
    if not isinstance(cases, dict) or set(cases) != set(CASES):
        errors.append("EXACT_THREE_CASES_REQUIRED")
        cases = {}
    details: dict[str, list[str]] = {}
    for name in CASES:
        errs = check_case(name, cases.get(name))
        if errs:
            details[name] = errs
    neg = bundle.get("negative_controls")
    if not isinstance(neg, dict) or set(neg) != set(FAILURES):
        errors.append("EXACT_NEGATIVE_CONTROL_SET_REQUIRED")
    else:
        for case in FAILURES:
            v = neg[case]
            if not isinstance(v, dict) or v.get("verdict") != "BLOCKED" or v.get("effect_performed") is not False or not _nonempty(v.get("evidence_ref")):
                errors.append("NEGATIVE_NOT_ATTESTED:" + case)
    if bundle.get("production_changed") is not False:
        errors.append("PRODUCTION_CHANGE_FORBIDDEN")
    all_errors = errors + [f"{k}:{e}" for k, v in details.items() for e in v]
    return {
        "test_code": TEST_CODE, "status": "FAIL" if all_errors else "PASS",
        "case_count": 3, "mandatory_trace_fields_per_case": len(TRACE_FIELDS),
        "errors": all_errors, "checks": details, "source": "EXTERNAL_EVIDENCE_ONLY",
        "checkpoint_close_authorized": False,  # Never self-authorizes C2.
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--evidence", type=Path, help="Real, independently acquired provider and consumer evidence JSON")
    p.add_argument("--self-test", action="store_true", help="Negative-only checks; NEVER a passing consumer receipt")
    a = p.parse_args()
    if a.self_test and a.evidence:
        p.error("--self-test and --evidence are mutually exclusive")
    if a.self_test:
        synthetic = {"schema": SCHEMA, "evidence_mode": "SYNTHETIC", "cases": {}}
        observed = validate(synthetic)
        if observed["status"] != "FAIL" or "REAL_PROVIDER_PROVENANCE_REQUIRED" not in observed["errors"]:
            print(json.dumps({"status": "FAIL", "error": "SELF_TEST_DID_NOT_REJECT_SYNTHETIC"}))
            return 2
        print(json.dumps({"status": "NEGATIVE_SELF_TEST_PASS", "checkpoint_pass": False,
                          "real_consumer_attested": False, "rejected": observed["errors"]}, sort_keys=True))
        return 0
    if not a.evidence:
        print(json.dumps({"status": "BLOCKED", "test_code": TEST_CODE,
                          "errors": ["REAL_EVIDENCE_NOT_PROVIDED"],
                          "checkpoint_close_authorized": False}, sort_keys=True))
        return 2
    try:
        payload = json.loads(a.evidence.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "BLOCKED", "test_code": TEST_CODE,
                          "errors": ["EVIDENCE_READ_OR_JSON_INVALID", type(exc).__name__],
                          "checkpoint_close_authorized": False}, sort_keys=True))
        return 2
    result = validate(payload)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
