"""Check source -> rule -> criterion -> test -> evidence traceability for J07/J10.

When an independent source-authority sidecar is supplied, this validator also
performs fail-closed source-to-candidate coverage and semantic reconciliation.
The authority sidecar is external to the Story Pack and must be SHA-bound by
the caller; candidate content can never enlarge the authoritative universe.
"""
from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from pathlib import Path
from typing import Any

from lf_common import (
    add_common_input, duplicate_values, emit, failure, load_json, main_guard,
    parser, require_object, result_object, utc_now,
)

JUDGE = "J07_AUDIT_TRACEABILITY"
AUTH_SCHEMA = "lf-source-authority/v1"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _dicts(value: Any) -> list[dict[str, Any]]:
    return [x for x in value if isinstance(x, dict)] if isinstance(value, list) else []


def _get(obj: Any, dotted: str) -> Any:
    cur = obj
    if not dotted or dotted == "$":
        return cur
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def _collection(pack: dict[str, Any], path: str) -> list[Any]:
    value = _get(pack, path)
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [value]
    return []


def _locate(pack: dict[str, Any], locator: dict[str, Any]) -> list[Any]:
    collection = str(locator.get("collection") or "$._missing")
    values = _collection(pack, collection)
    match = locator.get("match") if isinstance(locator.get("match"), dict) else {}
    matched = []
    for item in values:
        if match:
            if not isinstance(item, dict) or any(_get(item, str(k)) != v for k, v in match.items()):
                continue
        matched.append(item)
    field = locator.get("field")
    if field is None:
        return matched
    return [_get(item, str(field)) for item in matched]


def _refs(value: Any) -> set[str]:
    out: set[str] = set()
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "source_ref" and isinstance(item, str) and item.strip():
                out.add(item.strip())
            elif key == "source_refs" and isinstance(item, list):
                out.update(str(x).strip() for x in item if isinstance(x, str) and x.strip())
            out.update(_refs(item))
    elif isinstance(value, list):
        for item in value:
            out.update(_refs(item))
    return out


def _norm_text(value: Any, *, collapse_spaces: bool = True) -> str:
    text = unicodedata.normalize("NFC", str(value or ""))
    text = text.translate(str.maketrans({"“": '"', "”": '"', "‘": "'", "’": "'", "\u00a0": " "}))
    return " ".join(text.split()) if collapse_spaces else text


def _operator(values: list[Any], operator: str, expected: Any, assertion: dict[str, Any]) -> bool:
    if operator == "exists":
        return bool(values) and any(v is not None for v in values)
    if operator == "absent":
        return not values or all(v is None for v in values)
    if operator == "eq":
        return bool(values) and any(v == expected for v in values)
    if operator == "neq":
        return bool(values) and all(v != expected for v in values)
    if operator == "contains":
        return any((expected in v if isinstance(v, (list, str, dict)) else False) for v in values)
    if operator == "not_contains":
        return all((expected not in v if isinstance(v, (list, str, dict)) else True) for v in values)
    if operator == "set_eq":
        want = set(expected if isinstance(expected, list) else [expected])
        return any(isinstance(v, list) and set(v) == want for v in values)
    if operator == "regex":
        try:
            rx = re.compile(str(expected))
        except re.error:
            return False
        return any(isinstance(v, str) and bool(rx.search(v)) for v in values)
    if operator == "normalized_eq":
        return any(_norm_text(v) == _norm_text(expected) for v in values)
    if operator == "normalized_eq_casefold":
        return any(_norm_text(v).casefold() == _norm_text(expected).casefold() for v in values)
    if operator == "diacritic_semantic_eq":
        def fold(x: Any) -> str:
            normalized = unicodedata.normalize("NFD", _norm_text(x).casefold())
            return "".join(ch for ch in normalized if unicodedata.category(ch) != "Mn")
        return any(fold(v) == fold(expected) for v in values)
    if operator == "lexical_exact_nfc":
        return any(_norm_text(v) == _norm_text(expected) for v in values)
    if operator == "forbid_regex":
        try:
            rx = re.compile(str(expected), re.I | re.S)
        except re.error:
            return False
        return all(not (isinstance(v, str) and rx.search(v)) for v in values)
    if operator == "gte":
        return any(isinstance(v, (int, float)) and v >= expected for v in values)
    if operator == "lte":
        return any(isinstance(v, (int, float)) and v <= expected for v in values)
    if operator == "in":
        return any(v in expected for v in values) if isinstance(expected, list) else False
    if operator == "truthy":
        return any(bool(v) for v in values)
    if operator == "falsy":
        return any(not bool(v) for v in values)
    if operator == "same_as":
        other = assertion.get("other_locator")
        other_values = _locate(assertion.get("_pack", {}), other) if isinstance(other, dict) else []
        return bool(values) and bool(other_values) and any(v == o for v in values for o in other_values)
    return False


def _surface_items(pack: dict[str, Any], surface: str) -> list[dict[str, Any]]:
    if surface == "acceptance_criteria":
        return _dicts(_get(pack, "core.acceptance_criteria"))
    if surface in {"fields", "validations", "errors", "observations", "tests", "analytics"}:
        return _dicts(pack.get(surface))
    if surface == "audit_events":
        return _dicts(_get(pack, "audit.events"))
    if surface == "states":
        raw = pack.get("states")
        if isinstance(raw, list):
            return _dicts(raw)
        if isinstance(raw, dict):
            merged: list[dict[str, Any]] = []
            for value in raw.values():
                if isinstance(value, dict):
                    merged.append(value)
                elif isinstance(value, list):
                    merged.extend(_dicts(value))
            return merged or [raw]
    if surface == "security_privacy":
        raw = pack.get("security_privacy")
        return [raw] if isinstance(raw, dict) else []
    return []


def _surface_covers(pack: dict[str, Any], obj: dict[str, Any], surface: str) -> bool:
    source_ref = str(obj.get("source_ref") or "").strip()
    code = str(obj.get("code") or "").strip()
    items = _surface_items(pack, surface)
    if surface == "fields":
        return any(x.get("field_code") == code or source_ref in _refs(x) for x in items)
    if surface == "validations":
        return any(x.get("validation_code") == code or source_ref in _refs(x) for x in items)
    if surface == "errors":
        return any(x.get("error_code") == code or source_ref in _refs(x) for x in items)
    if surface == "observations":
        return any(x.get("observation_code") == code or source_ref in _refs(x) for x in items)
    if surface == "states":
        return any(x.get("state_code") == code or source_ref in _refs(x) for x in items)
    if surface == "acceptance_criteria":
        return any(source_ref in _refs(x) or x.get("rule_ref") == code for x in items)
    if surface == "tests":
        return any(source_ref in _refs(x) or x.get("rule_ref") == code for x in items)
    if surface == "security_privacy":
        return any(source_ref in _refs(x) or code in json.dumps(x, ensure_ascii=False) for x in items)
    return any(source_ref in _refs(x) for x in items)


def load_authority(path: Path, expected_sha: str | None, require: bool) -> tuple[dict[str, Any] | None, list[str], dict[str, Any]]:
    blockers: list[str] = []
    evidence: dict[str, Any] = {"source_authority_required": require}
    if not path:
        if require:
            blockers.append("independent_source_authority_missing")
        return None, blockers, evidence
    if not path.is_file():
        blockers.append("independent_source_authority_unavailable")
        return None, blockers, evidence
    digest = sha256_file(path)
    evidence.update({"source_authority_path": str(path), "source_authority_sha256": digest})
    if expected_sha:
        if not HEX64.fullmatch(expected_sha):
            blockers.append("source_authority_expected_sha_invalid")
        elif digest != expected_sha:
            blockers.append("source_authority_sha_mismatch")
    elif require:
        blockers.append("source_authority_expected_sha_missing")
    try:
        authority = require_object(load_json(path), "source_authority")
    except Exception:
        blockers.append("source_authority_invalid_json")
        return None, blockers, evidence
    if authority.get("schema_version") != AUTH_SCHEMA:
        blockers.append("source_authority_schema_mismatch")
    if not isinstance(authority.get("objects"), list):
        blockers.append("source_authority_objects_missing")
    if not isinstance(authority.get("assertions", []), list):
        blockers.append("source_authority_assertions_invalid")
    return authority, blockers, evidence


def validate_against_authority(pack: dict[str, Any], authority: dict[str, Any]) -> tuple[dict[str, list[str]], dict[str, Any]]:
    objects = _dicts(authority.get("objects"))
    assertions = _dicts(authority.get("assertions", []))
    conflicts = _dicts(authority.get("conflicts", []))
    known_refs = {str(x.get("source_ref") or "").strip() for x in objects if str(x.get("source_ref") or "").strip()}
    candidate_refs = _refs(pack)

    unresolvable = sorted(candidate_refs - known_refs)
    duplicate_source_refs = duplicate_values(str(x.get("source_ref") or "").strip() for x in objects if x.get("source_ref"))
    missing_source_objects: list[str] = []
    missing_surface_coverage: list[str] = []
    for obj in objects:
        ref = str(obj.get("source_ref") or "").strip()
        code = str(obj.get("code") or ref or "<unknown>")
        if not ref:
            missing_source_objects.append(code)
            continue
        required_surfaces = obj.get("required_surfaces", [])
        if obj.get("required") is True and not required_surfaces:
            required_surfaces = ["acceptance_criteria"]
        if not isinstance(required_surfaces, list):
            missing_surface_coverage.append(f"{code}:invalid_required_surfaces")
            continue
        for surface in required_surfaces:
            if not _surface_covers(pack, obj, str(surface)):
                missing_surface_coverage.append(f"{code}:{surface}")

    failed_assertions: list[str] = []
    skipped_assertions: list[str] = []
    for assertion in assertions:
        code = str(assertion.get("assertion_code") or "<unnamed>")
        source_refs = assertion.get("source_refs")
        if source_refs is None and assertion.get("source_ref"):
            source_refs = [assertion.get("source_ref")]
        if not isinstance(source_refs, list) or any(str(x) not in known_refs for x in source_refs):
            failed_assertions.append(f"{code}:source_ref_unresolved")
            continue
        when = assertion.get("when")
        if isinstance(when, dict):
            values = _locate(pack, when.get("locator", {}) if isinstance(when.get("locator"), dict) else {})
            when_copy = dict(when); when_copy["_pack"] = pack
            if not _operator(values, str(when.get("operator") or "eq"), when.get("expected"), when_copy):
                skipped_assertions.append(code)
                continue
        locator = assertion.get("locator") if isinstance(assertion.get("locator"), dict) else {}
        values = _locate(pack, locator)
        assertion_copy = dict(assertion); assertion_copy["_pack"] = pack
        if not _operator(values, str(assertion.get("operator") or "eq"), assertion.get("expected"), assertion_copy):
            failed_assertions.append(code)

    conflict_missing: list[str] = []
    candidate_conflicts = _dicts(_get(pack, "dependencies_risks.conflicts"))
    declared_conflicts = {str(x.get("conflict_code") or "") for x in candidate_conflicts}
    for conflict in conflicts:
        if str(conflict.get("status") or "OPEN") not in {"OPEN", "DECISION_REQUIRED"}:
            continue
        code = str(conflict.get("conflict_code") or "<unnamed-conflict>")
        if code not in declared_conflicts:
            conflict_missing.append(code)

    checks = {
        "unresolvable_source_refs": unresolvable,
        "duplicate_authority_source_refs": duplicate_source_refs,
        "authority_objects_without_source_ref": sorted(missing_source_objects),
        "independent_source_coverage_missing": sorted(missing_surface_coverage),
        "source_semantic_assertions_failed": sorted(failed_assertions),
        "source_conflicts_not_surfaced": sorted(conflict_missing),
    }
    evidence = {
        "authority_object_count": len(objects),
        "authority_assertion_count": len(assertions),
        "authority_conflict_count": len(conflicts),
        "candidate_source_ref_count": len(candidate_refs),
        "skipped_conditional_assertions": sorted(skipped_assertions),
    }
    return checks, evidence


def legacy_checks(pack: dict[str, Any]) -> tuple[dict[str, list[str]], dict[str, Any]]:
    criteria = _dicts(_get(pack, "core.acceptance_criteria"))
    validations = _dicts(pack.get("validations"))
    tests = _dicts(pack.get("tests"))
    audit_raw = pack.get("audit")
    audit = audit_raw if isinstance(audit_raw, dict) else {}
    audit_events = _dicts(audit.get("events"))
    audit_reason = audit.get("reason")
    criterion_ids = {x.get("criterion_code") for x in criteria if x.get("criterion_code")}
    rule_ids = {x.get("validation_code") for x in validations if x.get("validation_code")}
    rule_ids.update(x.get("error_code") for x in _dicts(pack.get("errors")) if x.get("error_code"))
    rule_ids.update(x.get("observation_code") for x in _dicts(pack.get("observations")) if x.get("observation_code"))
    rule_ids.update(x.get("audit_event_code") for x in audit_events if x.get("audit_event_code"))
    rule_ids.update(x.get("event_code") for x in _dicts(pack.get("analytics")) if x.get("event_code"))
    sec = pack.get("security_privacy", {})
    if isinstance(sec, dict):
        if sec.get("cross_tenant_policy") == "DENY": rule_ids.add("SEC-CROSS-TENANT-DENY")
        if sec.get("idempotency_required") is True: rule_ids.add("SEC-IDEMPOTENCY-REQUIRED")
    audit_contract_missing = [] if isinstance(audit_raw, dict) and (audit_events or audit_reason) else ["audit"]
    audit_events_without_source = sorted(x.get("audit_event_code", "<missing>") for x in audit_events if not x.get("source_ref"))
    audit_events_without_code = [f"audit.events[{i}]" for i, x in enumerate(audit_events) if not x.get("audit_event_code")]
    criteria_without_source = sorted(x.get("criterion_code") for x in criteria if not x.get("source_ref"))
    rules_without_source = sorted(x.get("validation_code") for x in validations if not x.get("source_ref"))
    covered_criteria = {x.get("criterion_ref") for x in tests if x.get("criterion_ref") in criterion_ids}
    covered_rules = {x.get("rule_ref") for x in tests if x.get("rule_ref") in rule_ids}
    orphan_tests = [x.get("test_code") for x in tests if x.get("criterion_ref") not in criterion_ids and x.get("rule_ref") not in rule_ids]
    tests_without_evidence = [x.get("test_code") for x in tests if not x.get("evidence_path")]
    checks = {
        "audit_contract_missing": audit_contract_missing,
        "audit_events_without_code": audit_events_without_code,
        "audit_events_without_source_reference": audit_events_without_source,
        "criteria_without_source_reference": criteria_without_source,
        "rules_without_source_reference": rules_without_source,
        "criteria_without_test_reference": sorted(criterion_ids - covered_criteria),
        "critical_rules_without_test": sorted(x.get("validation_code") for x in validations if x.get("critical") and x.get("validation_code") not in covered_rules),
        "tests_without_story_reference": orphan_tests,
        "tests_without_evidence_path": tests_without_evidence,
        "duplicate_test_codes": duplicate_values(x.get("test_code") for x in tests if x.get("test_code")),
    }
    return checks, {
        "audit_event_count": len(audit_events), "audit_reason_present": bool(audit_reason),
        "criterion_count": len(criterion_ids), "rule_count": len(rule_ids), "test_count": len(tests),
        "covered_criteria_count": len(covered_criteria), "covered_rules_count": len(covered_rules),
    }


def evaluate(pack: dict[str, Any], authority: dict[str, Any] | None = None) -> tuple[list[str], list[dict[str, Any]], dict[str, Any]]:
    checks, evidence = legacy_checks(pack)
    if authority is not None:
        source_checks, source_evidence = validate_against_authority(pack, authority)
        checks.update(source_checks)
        evidence.update(source_evidence)
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "source_authority" if key.startswith(("source_", "independent_", "unresolvable_", "duplicate_authority_", "authority_")) else ("tests" if "test" in key else "validations"), f"Repair references/semantics: {values}")
        for key, values in checks.items() if values
    ]
    evidence.update({"traceability_breaks": sum(len(v) for v in checks.values()), "checks": checks})
    return sorted(failed), repairs, evidence


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
    authority, blockers, auth_evidence = load_authority(args.source_authority, args.source_authority_sha256, args.require_source_authority)
    failed, repairs, evidence = evaluate(pack, authority)
    evidence.update(auth_evidence)
    evidence["input_path"] = str(args.input)
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"], repairs,
        blockers=sorted(set(blockers)), retry_count=args.retry_count,
        judge_version=args.judge_version, executor_identity=args.executor_identity,
        started_at=started_at,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
