"""J07 traceability validator with independent source-authority support.

Legacy mode preserves historical package regressions. Operational mode must use
--require-source-authority with a caller-pinned SHA-256 so coverage and semantic
truth cannot be derived from the candidate Story Pack itself.
"""
from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from pathlib import Path
from typing import Any

from lf_common import (
    add_common_input,
    duplicate_values,
    emit,
    failure,
    load_json,
    main_guard,
    parser,
    require_object,
    result_object,
    utc_now,
)

JUDGE = "J07_AUDIT_TRACEABILITY"
AUTH_SCHEMA = "lf-source-authority/v1"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def _dicts(value: Any) -> list[dict[str, Any]]:
    return [x for x in value if isinstance(x, dict)] if isinstance(value, list) else []


def _get(value: Any, dotted: str) -> Any:
    cur = value
    if not dotted or dotted == "$":
        return cur
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def _collection(pack: dict[str, Any], path: str) -> list[Any]:
    value = _get(pack, path)
    if isinstance(value, list):
        return value
    return [value] if isinstance(value, dict) else []


def _locate(pack: dict[str, Any], locator: dict[str, Any]) -> list[Any]:
    values = _collection(pack, str(locator.get("collection") or "$._missing"))
    match = locator.get("match") if isinstance(locator.get("match"), dict) else {}
    matched = [
        item for item in values
        if not match or (
            isinstance(item, dict)
            and all(_get(item, str(key)) == expected for key, expected in match.items())
        )
    ]
    field = locator.get("field")
    return matched if field is None else [_get(item, str(field)) for item in matched]


def _refs(value: Any) -> set[str]:
    refs: set[str] = set()
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "source_ref" and isinstance(item, str) and item.strip():
                refs.add(item.strip())
            elif key == "source_refs" and isinstance(item, list):
                refs.update(str(x).strip() for x in item if isinstance(x, str) and x.strip())
            refs.update(_refs(item))
    elif isinstance(value, list):
        for item in value:
            refs.update(_refs(item))
    return refs


def _norm(value: Any) -> str:
    text = unicodedata.normalize("NFC", str(value or ""))
    text = text.translate(str.maketrans({"“": '"', "”": '"', "‘": "'", "’": "'", "\u00a0": " "}))
    return " ".join(text.split())


def _operator(pack: dict[str, Any], values: list[Any], assertion: dict[str, Any]) -> bool:
    op = str(assertion.get("operator") or "eq")
    expected = assertion.get("expected")
    if op == "exists":
        return bool(values) and any(v is not None for v in values)
    if op == "absent":
        return not values or all(v is None for v in values)
    if op == "eq":
        return bool(values) and any(v == expected for v in values)
    if op == "neq":
        return bool(values) and all(v != expected for v in values)
    if op == "contains":
        return any(isinstance(v, (list, str, dict)) and expected in v for v in values)
    if op == "not_contains":
        return all(not isinstance(v, (list, str, dict)) or expected not in v for v in values)
    if op == "set_eq":
        want = set(expected if isinstance(expected, list) else [expected])
        return any(isinstance(v, list) and set(v) == want for v in values)
    if op == "regex":
        try:
            rx = re.compile(str(expected))
        except re.error:
            return False
        return any(isinstance(v, str) and rx.search(v) is not None for v in values)
    if op == "forbid_regex":
        try:
            rx = re.compile(str(expected), re.I | re.S)
        except re.error:
            return False
        return all(not isinstance(v, str) or rx.search(v) is None for v in values)
    if op in {"normalized_eq", "lexical_exact_nfc"}:
        return any(_norm(v) == _norm(expected) for v in values)
    if op == "normalized_eq_casefold":
        return any(_norm(v).casefold() == _norm(expected).casefold() for v in values)
    if op == "diacritic_semantic_eq":
        def fold(x: Any) -> str:
            raw = unicodedata.normalize("NFD", _norm(x).casefold())
            return "".join(ch for ch in raw if unicodedata.category(ch) != "Mn")
        return any(fold(v) == fold(expected) for v in values)
    if op == "gte":
        return any(isinstance(v, (int, float)) and v >= expected for v in values)
    if op == "lte":
        return any(isinstance(v, (int, float)) and v <= expected for v in values)
    if op == "in":
        return isinstance(expected, list) and any(v in expected for v in values)
    if op == "truthy":
        return any(bool(v) for v in values)
    if op == "falsy":
        return any(not bool(v) for v in values)
    if op == "same_as":
        other = assertion.get("other_locator")
        other_values = _locate(pack, other) if isinstance(other, dict) else []
        return bool(values) and bool(other_values) and any(v == x for v in values for x in other_values)
    return False


def _surface_items(pack: dict[str, Any], surface: str) -> list[dict[str, Any]]:
    if surface == "acceptance_criteria":
        return _dicts(_get(pack, "core.acceptance_criteria"))
    if surface == "audit_events":
        return _dicts(_get(pack, "audit.events"))
    if surface == "security_privacy":
        sec = pack.get("security_privacy")
        return [sec] if isinstance(sec, dict) else []
    if surface == "states":
        states = pack.get("states")
        if isinstance(states, list):
            return _dicts(states)
        if isinstance(states, dict):
            merged: list[dict[str, Any]] = []
            for item in states.values():
                if isinstance(item, dict):
                    merged.append(item)
                elif isinstance(item, list):
                    merged.extend(_dicts(item))
            return merged or [states]
        return []
    return _dicts(pack.get(surface))


def _surface_covers(pack: dict[str, Any], obj: dict[str, Any], surface: str) -> bool:
    ref = str(obj.get("source_ref") or "").strip()
    code = str(obj.get("code") or "").strip()
    items = _surface_items(pack, surface)
    code_keys = {
        "fields": "field_code",
        "validations": "validation_code",
        "errors": "error_code",
        "observations": "observation_code",
        "states": "state_code",
    }
    key = code_keys.get(surface)
    if key:
        return any(item.get(key) == code or ref in _refs(item) for item in items)
    if surface in {"acceptance_criteria", "tests"}:
        return any(ref in _refs(item) or item.get("rule_ref") == code for item in items)
    if surface == "security_privacy":
        return any(ref in _refs(item) or code in json.dumps(item, ensure_ascii=False) for item in items)
    return any(ref in _refs(item) for item in items)


def validate_against_authority(
    pack: dict[str, Any], authority: dict[str, Any]
) -> tuple[dict[str, list[str]], dict[str, Any]]:
    objects = _dicts(authority.get("objects"))
    assertions = _dicts(authority.get("assertions", []))
    conflicts = _dicts(authority.get("conflicts", []))
    known_refs = {
        str(obj.get("source_ref") or "").strip()
        for obj in objects if str(obj.get("source_ref") or "").strip()
    }
    candidate_refs = _refs(pack)
    missing_surfaces: list[str] = []
    objects_without_ref: list[str] = []
    for obj in objects:
        ref = str(obj.get("source_ref") or "").strip()
        code = str(obj.get("code") or ref or "<unknown>")
        if not ref:
            objects_without_ref.append(code)
            continue
        surfaces = obj.get("required_surfaces", [])
        if obj.get("required") is True and not surfaces:
            surfaces = ["acceptance_criteria"]
        if not isinstance(surfaces, list):
            missing_surfaces.append(f"{code}:invalid_required_surfaces")
            continue
        for surface in surfaces:
            if not _surface_covers(pack, obj, str(surface)):
                missing_surfaces.append(f"{code}:{surface}")

    failed_semantics: list[str] = []
    skipped: list[str] = []
    for assertion in assertions:
        code = str(assertion.get("assertion_code") or "<unnamed>")
        source_refs = assertion.get("source_refs")
        if source_refs is None and assertion.get("source_ref"):
            source_refs = [assertion.get("source_ref")]
        if not isinstance(source_refs, list) or any(str(ref) not in known_refs for ref in source_refs):
            failed_semantics.append(f"{code}:source_ref_unresolved")
            continue
        when = assertion.get("when")
        if isinstance(when, dict):
            when_values = _locate(pack, when.get("locator", {}) if isinstance(when.get("locator"), dict) else {})
            if not _operator(pack, when_values, when):
                skipped.append(code)
                continue
        locator = assertion.get("locator") if isinstance(assertion.get("locator"), dict) else {}
        if not _operator(pack, _locate(pack, locator), assertion):
            failed_semantics.append(code)

    candidate_conflicts = {
        str(x.get("conflict_code") or "")
        for x in _dicts(_get(pack, "dependencies_risks.conflicts"))
    }
    missing_conflicts = [
        str(c.get("conflict_code") or "<unnamed-conflict>")
        for c in conflicts
        if str(c.get("status") or "OPEN") in {"OPEN", "DECISION_REQUIRED"}
        and str(c.get("conflict_code") or "") not in candidate_conflicts
    ]
    checks = {
        "unresolvable_source_refs": sorted(candidate_refs - known_refs),
        "duplicate_authority_source_refs": duplicate_values(
            str(x.get("source_ref") or "").strip() for x in objects if x.get("source_ref")
        ),
        "authority_objects_without_source_ref": sorted(objects_without_ref),
        "independent_source_coverage_missing": sorted(missing_surfaces),
        "source_semantic_assertions_failed": sorted(failed_semantics),
        "source_conflicts_not_surfaced": sorted(missing_conflicts),
    }
    return checks, {
        "authority_object_count": len(objects),
        "authority_assertion_count": len(assertions),
        "authority_conflict_count": len(conflicts),
        "candidate_source_ref_count": len(candidate_refs),
        "skipped_conditional_assertions": sorted(skipped),
    }


def _legacy(pack: dict[str, Any]) -> tuple[dict[str, list[str]], dict[str, Any]]:
    criteria = _dicts(_get(pack, "core.acceptance_criteria"))
    validations = _dicts(pack.get("validations"))
    tests = _dicts(pack.get("tests"))
    audit_raw = pack.get("audit")
    audit = audit_raw if isinstance(audit_raw, dict) else {}
    audit_events = _dicts(audit.get("events"))
    criterion_ids = {x.get("criterion_code") for x in criteria if x.get("criterion_code")}
    rule_ids = {x.get("validation_code") for x in validations if x.get("validation_code")}
    rule_ids.update(x.get("error_code") for x in _dicts(pack.get("errors")) if x.get("error_code"))
    rule_ids.update(x.get("observation_code") for x in _dicts(pack.get("observations")) if x.get("observation_code"))
    rule_ids.update(x.get("audit_event_code") for x in audit_events if x.get("audit_event_code"))
    rule_ids.update(x.get("event_code") for x in _dicts(pack.get("analytics")) if x.get("event_code"))
    sec = pack.get("security_privacy")
    if isinstance(sec, dict):
        if sec.get("cross_tenant_policy") == "DENY":
            rule_ids.add("SEC-CROSS-TENANT-DENY")
        if sec.get("idempotency_required") is True:
            rule_ids.add("SEC-IDEMPOTENCY-REQUIRED")
    covered_criteria = {x.get("criterion_ref") for x in tests if x.get("criterion_ref") in criterion_ids}
    covered_rules = {x.get("rule_ref") for x in tests if x.get("rule_ref") in rule_ids}
    checks = {
        "audit_contract_missing": [] if isinstance(audit_raw, dict) and (audit_events or audit.get("reason")) else ["audit"],
        "audit_events_without_code": [f"audit.events[{i}]" for i, x in enumerate(audit_events) if not x.get("audit_event_code")],
        "audit_events_without_source_reference": sorted(x.get("audit_event_code", "<missing>") for x in audit_events if not x.get("source_ref")),
        "criteria_without_source_reference": sorted(x.get("criterion_code") for x in criteria if not x.get("source_ref")),
        "rules_without_source_reference": sorted(x.get("validation_code") for x in validations if not x.get("source_ref")),
        "criteria_without_test_reference": sorted(criterion_ids - covered_criteria),
        "critical_rules_without_test": sorted(x.get("validation_code") for x in validations if x.get("critical") and x.get("validation_code") not in covered_rules),
        "tests_without_story_reference": [x.get("test_code") for x in tests if x.get("criterion_ref") not in criterion_ids and x.get("rule_ref") not in rule_ids],
        "tests_without_evidence_path": [x.get("test_code") for x in tests if not x.get("evidence_path")],
        "duplicate_test_codes": duplicate_values(x.get("test_code") for x in tests if x.get("test_code")),
    }
    return checks, {
        "audit_event_count": len(audit_events),
        "audit_reason_present": bool(audit.get("reason")),
        "criterion_count": len(criterion_ids),
        "rule_count": len(rule_ids),
        "test_count": len(tests),
        "covered_criteria_count": len(covered_criteria),
        "covered_rules_count": len(covered_rules),
    }


def evaluate(
    pack: dict[str, Any], authority: dict[str, Any] | None = None
) -> tuple[list[str], list[dict[str, Any]], dict[str, Any]]:
    checks, evidence = _legacy(pack)
    if authority is not None:
        source_checks, source_evidence = validate_against_authority(pack, authority)
        checks.update(source_checks)
        evidence.update(source_evidence)
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(
            key,
            "source_authority" if key.startswith(("source_", "independent_", "unresolvable_", "duplicate_authority_", "authority_")) else ("tests" if "test" in key else "validations"),
            f"Repair references/semantics: {values}",
        )
        for key, values in checks.items() if values
    ]
    evidence.update({"traceability_breaks": sum(len(v) for v in checks.values()), "checks": checks})
    return sorted(failed), repairs, evidence


def _load_authority(
    path: Path | None, expected_sha: str | None, required: bool
) -> tuple[dict[str, Any] | None, list[str], dict[str, Any]]:
    blockers: list[str] = []
    evidence: dict[str, Any] = {"source_authority_required": required}
    if path is None:
        if required:
            blockers.append("independent_source_authority_missing")
        return None, blockers, evidence
    if not path.is_file():
        return None, ["independent_source_authority_unavailable"], evidence
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    evidence.update({"source_authority_path": str(path), "source_authority_sha256": digest})
    if expected_sha is None:
        if required:
            blockers.append("source_authority_expected_sha_missing")
    elif not HEX64.fullmatch(expected_sha):
        blockers.append("source_authority_expected_sha_invalid")
    elif digest != expected_sha:
        blockers.append("source_authority_sha_mismatch")
    try:
        authority = require_object(load_json(path), "source_authority")
    except Exception:
        return None, blockers + ["source_authority_invalid_json"], evidence
    if authority.get("schema_version") != AUTH_SCHEMA:
        blockers.append("source_authority_schema_mismatch")
    if not isinstance(authority.get("objects"), list):
        blockers.append("source_authority_objects_missing")
    if not isinstance(authority.get("assertions", []), list):
        blockers.append("source_authority_assertions_invalid")
    return authority, blockers, evidence


def run() -> int:
    started_at = utc_now()
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--judge-version")
    cli.add_argument("--executor-identity")
    cli.add_argument("--source-authority", type=Path)
    cli.add_argument("--source-authority-sha256")
    cli.add_argument("--require-source-authority", action="store_true")
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")
    authority, blockers, auth_evidence = _load_authority(
        args.source_authority,
        args.source_authority_sha256,
        args.require_source_authority,
    )
    failed, repairs, evidence = evaluate(pack, authority)
    evidence.update(auth_evidence)
    evidence["input_path"] = str(args.input)
    return emit(result_object(
        JUDGE,
        failed,
        evidence,
        args.evidence_ref or [f"file:{args.input}"],
        repairs,
        blocking_assertions=sorted(set(blockers)),
        retry_count=args.retry_count,
        judge_version=args.judge_version,
        executor_identity=args.executor_identity,
        started_at=started_at,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
