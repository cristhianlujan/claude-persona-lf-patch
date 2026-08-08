#!/usr/bin/env python3
"""Semantic validator for J02_SCREEN_DECOMPOSITION v0.7."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object, sha256_file

JUDGE = "J02_SCREEN_DECOMPOSITION"
VERSION = "v0.7"
REGISTRATION = "supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION"
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ASSERTIONS = (
    "input_schema_valid", "source_snapshot_sha_present", "source_screen_code_matches_target",
    "context_coverage", "field_coverage", "permission_coverage", "transition_coverage",
    "unmapped_count", "unjustified_count", "conflicting_count", "duplicate_functional_units",
    "functional_units_complete", "functional_units_without_code",
    "coverage_mapped_to_unknown_functional_unit", "confirmed_rules_have_source",
    "coverage_summary_mismatch", "blocking_pending_decisions",
)
INVENTORIES = {
    "context_coverage": ("context_inventory", "CONTEXT", ("code", "source_ref")),
    "field_coverage": ("field_inventory", "FIELD", ("code", "source_ref")),
    "permission_coverage": ("permission_inventory", "PERMISSION", ("permission_code", "source_ref")),
    "transition_coverage": ("transition_inventory", "TRANSITION", ("source_ref",)),
}


def obj(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def arr(value: Any, name: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValidationInputError(f"{name}_must_be_array")
    return value


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def runtime_meta() -> dict[str, Any]:
    path = Path(__file__).resolve()
    raw = path.read_bytes()
    blob = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
    return {
        "semantic_validator_path": str(path),
        "semantic_validator_sha256": hashlib.sha256(raw).hexdigest(),
        "semantic_validator_git_blob_sha1": blob,
        "semantic_validator_bytes": len(raw),
    }


def schema_path() -> Path:
    override = os.getenv("LF_SCREEN_DECOMPOSITION_SCHEMA")
    return Path(override).resolve() if override else Path(__file__).resolve().parent.parent / "schemas" / "screen-decomposition.schema.json"


def schema_errors(dec: dict[str, Any]) -> tuple[list[str], str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise ValidationInputError("jsonschema_not_available") from exc
    path = schema_path()
    if not path.is_file():
        raise ValidationInputError("input_schema_unavailable")
    schema = obj(load_json(path), "screen_decomposition_schema")
    jsonschema.Draft7Validator.check_schema(schema)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    errors = sorted(f"{'/'.join(map(str, e.absolute_path)) or '$'}:{e.message}" for e in validator.iter_errors(dec))
    return errors, sha256_file(path)


def runtime_blockers(executor: str | None, version: str | None, expected_sha: str | None, registration: str | None, meta: dict[str, Any]) -> list[str]:
    out: list[str] = []
    if not str(executor or "").strip(): out.append("executor_identity_missing")
    if not str(version or "").strip(): out.append("judge_version_missing")
    elif str(version).strip() != VERSION: out.append("judge_version_mismatch")
    expected = str(expected_sha or "").strip()
    if not expected: out.append("semantic_validator_unavailable")
    elif not SHA_RE.fullmatch(expected): out.append("semantic_validator_sha_expected_invalid")
    elif expected != meta["semantic_validator_sha256"]: out.append("semantic_validator_sha_unreconciled")
    if str(registration or "").strip() != REGISTRATION: out.append("semantic_validator_unregistered")
    return out


def preflight(payload: Any) -> tuple[str | None, dict[str, Any] | None, list[str]]:
    if not isinstance(payload, dict) or "target_screen_code" not in payload or "screen_decomposition" not in payload:
        return None, None, ["required_input_missing"]
    target, dec = payload.get("target_screen_code"), payload.get("screen_decomposition")
    blockers: list[str] = []
    if not isinstance(target, str) or not target.strip(): blockers.append("required_input_missing")
    if not isinstance(dec, dict): return str(target or "").strip() or None, None, ["required_input_missing"]
    for key in ("context_inventory", "field_inventory", "permission_inventory", "transition_inventory"):
        if not isinstance(dec.get(key), list): blockers.append("inventory_missing_or_invalid"); break
    units, coverage = dec.get("functional_units"), dec.get("coverage_items")
    if not isinstance(units, list): blockers.append("inventory_missing_or_invalid")
    elif not units: blockers.append("functional_units_empty")
    if not isinstance(coverage, list): blockers.append("inventory_missing_or_invalid")
    elif not coverage: blockers.append("coverage_items_empty")
    if not isinstance(dec.get("coverage_summary"), dict): blockers.append("required_input_missing")
    if not str(dec.get("source_version") or "").strip() or not str(dec.get("main_responsibility") or "").strip():
        blockers.append("source_version_or_main_responsibility_empty")
    if not isinstance(dec.get("source_snapshot_sha"), str) or not SHA_RE.fullmatch(dec["source_snapshot_sha"]):
        blockers.append("input_sha256_missing")
    decisions = dec.get("pending_decisions")
    if not isinstance(decisions, list): blockers.append("required_input_missing")
    elif any(isinstance(x, dict) and x.get("blocking") is True and x.get("status") == "OPEN" for x in decisions):
        blockers.append("required_decision_prevents_decomposition")
    return str(target or "").strip() or None, dec, sorted(set(blockers))


def coverage_ids(items: list[Any], kind: str) -> set[str]:
    out: set[str] = set()
    for item in items:
        if not isinstance(item, dict) or item.get("source_type") != kind or item.get("mapping_status") not in {"MAPPED", "JUSTIFIED_OUT"}: continue
        for key in ("source_item_code", "source_ref"):
            value = item.get(key)
            if isinstance(value, str) and value.strip(): out.add(value.strip())
    return out


def uncovered(entries: list[Any], items: list[Any], kind: str, fields: tuple[str, ...]) -> int:
    covered = coverage_ids(items, kind)
    misses = 0
    for entry in entries:
        if not isinstance(entry, dict): misses += 1; continue
        ids = {entry[f].strip() for f in fields if isinstance(entry.get(f), str) and entry[f].strip()}
        if not ids or ids.isdisjoint(covered): misses += 1
    return misses


def duplicate_units(units: list[Any]) -> tuple[int, list[str]]:
    seen_codes: set[str] = set(); seen_semantics: set[tuple[str, str, str]] = set(); keys: list[str] = []; count = 0
    for i, unit in enumerate(units):
        if not isinstance(unit, dict): count += 1; keys.append(f"invalid:{i}"); continue
        code = str(unit.get("functional_unit_code") or "").strip()
        semantic = tuple(str(unit.get(k) or "").strip().casefold() for k in ("actor", "goal", "observable_output"))
        duplicate = False
        if code and code in seen_codes: keys.append(f"code:{code}"); duplicate = True
        if all(semantic) and semantic in seen_semantics: keys.append("semantic:" + "|".join(semantic)); duplicate = True
        if duplicate: count += 1
        if code: seen_codes.add(code)
        if all(semantic): seen_semantics.add(semantic)
    return count, sorted(set(keys))


def semantic(target: str, dec: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    errors, schema_sha = schema_errors(dec)
    contexts, fields = arr(dec.get("context_inventory"), "context_inventory"), arr(dec.get("field_inventory"), "field_inventory")
    permissions, transitions = arr(dec.get("permission_inventory"), "permission_inventory"), arr(dec.get("transition_inventory"), "transition_inventory")
    units, items = arr(dec.get("functional_units"), "functional_units"), arr(dec.get("coverage_items"), "coverage_items")
    summary = obj(dec.get("coverage_summary"), "coverage_summary")
    codes = {str(x.get("functional_unit_code")).strip() for x in units if isinstance(x, dict) and str(x.get("functional_unit_code") or "").strip()}
    statuses = [x.get("mapping_status") for x in items if isinstance(x, dict)]
    unmapped = unjustified = conflicting = unknown = 0
    for item in items:
        if not isinstance(item, dict): unmapped += 1; continue
        status, mapped = item.get("mapping_status"), item.get("mapped_to")
        if status == "CONFLICT": conflicting += 1
        if status not in {"MAPPED", "JUSTIFIED_OUT"}: unmapped += 1
        if status == "JUSTIFIED_OUT" and len(str(item.get("justification") or "").strip()) < 3: unjustified += 1
        if status == "MAPPED" and (not isinstance(mapped, list) or not mapped or any(not isinstance(code, str) or code not in codes for code in mapped)): unknown += 1
    duplicates, duplicate_keys = duplicate_units(units)
    incomplete = without_code = confirmed_without_source = 0
    required = ("actor", "goal", "trigger", "observable_output", "risk_level", "decision", "justification", "source_ref", "classification")
    for unit in units:
        if not isinstance(unit, dict): incomplete += 1; without_code += 1; continue
        if not str(unit.get("functional_unit_code") or "").strip(): without_code += 1
        if any(not str(unit.get(k) or "").strip() for k in required) or (unit.get("decision") == "MERGE_WITH" and not str(unit.get("merge_target") or "").strip()): incomplete += 1
        if unit.get("classification") == "CONFIRMED" and len(str(unit.get("source_ref") or "").strip()) < 3: confirmed_without_source += 1
    calculated = {
        "source_items_count": len(items), "mapped_count": statuses.count("MAPPED"), "justified_count": statuses.count("JUSTIFIED_OUT"),
        "unmapped_count": unmapped, "unjustified_count": unjustified, "conflicting_count": conflicting,
        "duplicate_functional_units_count": duplicates,
    }
    mismatch = [k for k, v in calculated.items() if summary.get(k) != v]
    blocking = sum(1 for x in dec.get("pending_decisions") or [] if isinstance(x, dict) and x.get("blocking") is True and x.get("status") == "OPEN")
    checks = {
        "input_schema_valid": len(errors), "source_snapshot_sha_present": 0 if isinstance(dec.get("source_snapshot_sha"), str) and SHA_RE.fullmatch(dec["source_snapshot_sha"]) else 1,
        "source_screen_code_matches_target": 0 if dec.get("screen_code") == target else 1,
        "unmapped_count": unmapped, "unjustified_count": unjustified, "conflicting_count": conflicting,
        "duplicate_functional_units": duplicates, "functional_units_complete": incomplete, "functional_units_without_code": without_code,
        "coverage_mapped_to_unknown_functional_unit": unknown, "confirmed_rules_have_source": confirmed_without_source,
        "coverage_summary_mismatch": len(mismatch), "blocking_pending_decisions": blocking,
    }
    for assertion, (inventory, kind, identifiers) in INVENTORIES.items(): checks[assertion] = uncovered(dec.get(inventory) or [], items, kind, identifiers)
    checks = {key: int(checks.get(key, 1)) for key in ASSERTIONS}
    evidence = {
        "input_schema_ref": "schemas/screen-decomposition.schema.json", "input_schema_sha256": schema_sha,
        "input_schema_valid": checks["input_schema_valid"], "schema_validation_errors": errors,
        "source_snapshot_sha": dec.get("source_snapshot_sha"), "source_version": dec.get("source_version"), "main_responsibility": dec.get("main_responsibility"),
        "context_count": len(contexts), "field_count": len(fields), "permission_count": len(permissions), "transition_count": len(transitions),
        "functional_units_count": len(units), "coverage_items_count": len(items), "recomputed_coverage_summary": calculated,
        "declared_coverage_summary": summary, "semantic_duplicate_keys": duplicate_keys, "mismatched_summary_fields": mismatch, "checks": checks,
    }
    return checks, evidence


def build(payload: Any, refs: list[str], retry: int, executor: str | None, version: str | None, expected_sha: str | None, registration: str | None, input_sha: str, input_path: str | None, command: str) -> dict[str, Any]:
    meta = runtime_meta(); blockers = runtime_blockers(executor, version, expected_sha, registration, meta)
    target, dec, payload_blockers = preflight(payload); blockers = sorted(set(blockers + payload_blockers))
    evidence: dict[str, Any] = {**meta, "semantic_validator_registration_ref": registration, "semantic_validator_expected_sha256": expected_sha, "executor_identity": executor, "judge_version": version, "input_sha256": input_sha, "input_path": input_path, "checks": {}}
    checks: dict[str, int] = {}
    if not blockers and target and dec:
        checks, extra = semantic(target, dec); evidence.update(extra)
    evidence["blocking_assertions"] = blockers
    repairs = [failure(k, f"$.evidence.checks.{k}", f"Repair until {k}=0 without weakening A44") for k, v in checks.items() if v]
    return result_object(JUDGE, [k for k, v in checks.items() if v], evidence, refs, repairs, blockers, retry_count=retry, judge_version=version, executor_identity=executor, command=command)


def positive() -> dict[str, Any]:
    fu = {"functional_unit_code":"FU-SEARCH","actor":"Operator","goal":"Search an authorized customer","trigger":"Submit search","observable_output":"Authorized customer result","risk_level":"LOW","decision":"CREATE_STORY","justification":"Independent observable business result","source_ref":"SRC-FU","classification":"CONFIRMED"}
    inv = {
        "context_inventory":[{"code":"CTX-SEARCH","description":"Customer search","source_ref":"SRC-C"}],
        "field_inventory":[{"code":"FLD-DOC","context_code":"CTX-SEARCH","source_ref":"SRC-F"}],
        "permission_inventory":[{"permission_code":"PERM-SEARCH","actor_profile":"OPERATOR","action_code":"SEARCH","source_ref":"SRC-P"}],
        "transition_inventory":[{"from":"IDLE","action":"SEARCH","to":"RESULTS","allowed":True,"source_ref":"SRC-T"}],
    }
    items = [
        {"source_item_code":"CTX-SEARCH","source_type":"CONTEXT","source_ref":"SRC-C","mapping_status":"MAPPED","mapped_to":["FU-SEARCH"],"justification":"Mapped context"},
        {"source_item_code":"FLD-DOC","source_type":"FIELD","source_ref":"SRC-F","mapping_status":"MAPPED","mapped_to":["FU-SEARCH"],"justification":"Mapped field"},
        {"source_item_code":"PERM-SEARCH","source_type":"PERMISSION","source_ref":"SRC-P","mapping_status":"MAPPED","mapped_to":["FU-SEARCH"],"justification":"Mapped permission"},
        {"source_item_code":"TR-SEARCH","source_type":"TRANSITION","source_ref":"SRC-T","mapping_status":"MAPPED","mapped_to":["FU-SEARCH"],"justification":"Mapped transition"},
    ]
    return {"target_screen_code":"SCR-SEARCH","screen_decomposition":{"screen_code":"SCR-SEARCH","module_code":"MOD-CUSTOMERS","source_version":"v1","source_snapshot_sha":"a"*64,"main_responsibility":"Allow an operator to search authorized customers",**inv,"functional_units":[fu],"coverage_items":items,"coverage_summary":{"source_items_count":4,"mapped_count":4,"justified_count":0,"unmapped_count":0,"unjustified_count":0,"conflicting_count":0,"duplicate_functional_units_count":0},"pending_decisions":[]}}


def case(name: str, payload: Any, result: str, assertion: str, executor: str | None, version: str | None, sha: str | None, registration: str | None) -> dict[str, Any]:
    out = build(payload, [f"self-test://{name}"], 0, executor, version, sha, registration, canonical_sha(payload), None, f"self-test:{name}")
    signals = set(out["failed_assertions"]) | set(out["blocking_assertions"])
    return {"name":name,"expected_result":result,"actual_result":out["result"],"expected_assertion":assertion,"signals":sorted(signals),"passed":out["result"]==result and assertion in signals}


def self_test() -> int:
    good = positive(); meta = runtime_meta(); sha = meta["semantic_validator_sha256"]; executor = "LF_SELF_TEST"
    ok = build(good,["self-test://positive"],0,executor,VERSION,sha,REGISTRATION,canonical_sha(good),None,"self-test:positive")
    tests: list[tuple[str, Any, str, str, str | None, str | None, str | None, str | None]] = []
    x=copy.deepcopy(good); x["screen_decomposition"]["functional_units"][0]["decision"]="MERGE_WITH"; tests.append(("schema_invalid_merge_without_target",x,"RETURN_TO_WORKER","input_schema_valid",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["functional_units"][0]["trigger"]=""; tests.append(("empty_trigger",x,"RETURN_TO_WORKER","input_schema_valid",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["coverage_items"][0]["mapping_status"]="PENDING"; tests.append(("pending_coverage_item",x,"RETURN_TO_WORKER","unmapped_count",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["functional_units"].append(copy.deepcopy(x["screen_decomposition"]["functional_units"][0])); tests.append(("duplicate_same_code",x,"RETURN_TO_WORKER","duplicate_functional_units",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); u=copy.deepcopy(x["screen_decomposition"]["functional_units"][0]); u["functional_unit_code"]="FU-SEARCH-2"; x["screen_decomposition"]["functional_units"].append(u); tests.append(("duplicate_semantics",x,"RETURN_TO_WORKER","duplicate_functional_units",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["context_inventory"][0]={"code":"CTX-OTHER","description":"Other context","source_ref":"SRC-OTHER"}; tests.append(("unrelated_context",x,"RETURN_TO_WORKER","context_coverage",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["coverage_items"]=[i for i in x["screen_decomposition"]["coverage_items"] if i["source_type"]!="FIELD"]; x["screen_decomposition"]["coverage_summary"].update(source_items_count=3,mapped_count=3); tests.append(("missing_field",x,"RETURN_TO_WORKER","field_coverage",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["pending_decisions"]=[{"decision_code":"DEC-1","missing_fact":"Required fact","why_required":"Needed before decomposition","source_checked":["SRC-D"],"blocking":True,"status":"OPEN"}]; tests.append(("blocking_decision",x,"BLOCKED","required_decision_prevents_decomposition",executor,VERSION,sha,REGISTRATION))
    tests += [("missing_runtime",good,"BLOCKED","semantic_validator_unavailable",executor,VERSION,None,REGISTRATION),("unregistered",good,"BLOCKED","semantic_validator_unregistered",executor,VERSION,sha,None),("sha_mismatch",good,"BLOCKED","semantic_validator_sha_unreconciled",executor,VERSION,"0"*64,REGISTRATION)]
    x=copy.deepcopy(good); x["screen_decomposition"]["coverage_items"][0]["mapped_to"]=["FU-UNKNOWN"]; tests.append(("unknown_mapping",x,"RETURN_TO_WORKER","coverage_mapped_to_unknown_functional_unit",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["functional_units"]=[]; tests.append(("empty_units",x,"BLOCKED","functional_units_empty",executor,VERSION,sha,REGISTRATION))
    x=copy.deepcopy(good); x["screen_decomposition"]["coverage_items"]=[]; tests.append(("empty_coverage",x,"BLOCKED","coverage_items_empty",executor,VERSION,sha,REGISTRATION))
    tests += [("missing_executor",good,"BLOCKED","executor_identity_missing",None,VERSION,sha,REGISTRATION),("missing_version",good,"BLOCKED","judge_version_missing",executor,None,sha,REGISTRATION)]
    results=[case(*t) for t in tests]
    output={"judge":JUDGE,"version":VERSION,"positive_pass":ok["result"]=="PASS_WITH_EVIDENCE" and ok["assertions_passed"]==17,"positive_assertions":f"{ok['assertions_passed']}/{ok['assertions_total']}","negative_cases_total":len(results),"negative_cases_passed":sum(r["passed"] for r in results),"negative_results":results}
    output["self_test_pass"]=output["positive_pass"] and output["negative_cases_passed"]==output["negative_cases_total"]
    print(json.dumps(output,ensure_ascii=False,sort_keys=True)); return 0 if output["self_test_pass"] else 1


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("input",nargs="?",type=Path); parser.add_argument("--evidence-ref",action="append",default=[]); parser.add_argument("--retry-count",type=int,default=0); parser.add_argument("--expected-validator-sha256",default=os.getenv("LF_EXPECTED_VALIDATOR_SHA256")); parser.add_argument("--registration-ref",default=os.getenv("LF_VALIDATOR_REGISTRATION_REF")); parser.add_argument("--self-test",action="store_true"); args=parser.parse_args()
    if args.self_test: return self_test()
    if args.input is None: raise ValidationInputError("input_required")
    payload=load_json(args.input); out=build(payload,args.evidence_ref,args.retry_count,os.getenv("LF_EXECUTOR_IDENTITY"),os.getenv("LF_JUDGE_VERSION"),args.expected_validator_sha256,args.registration_ref,sha256_file(args.input),str(args.input)," ".join(sys.argv)); return emit(out)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
