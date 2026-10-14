#!/usr/bin/env python3
"""Additive AS-IS / TO-BE / GAP gate for PE10E_C4. No production admission."""
from __future__ import annotations
import hashlib
import json
import math
import argparse
import sys
from pathlib import Path
from datetime import datetime
from typing import Any

ARMS = ("A_ORIGINAL", "B_UPDATER_V01", "C_EVOLUTION_CURRENT", "D_EVOLUTION_TARGET")
SCHEMA = "PROFILE_EXPERT_ASIS_TOBE_GAP_GATE_V1"

def digest(target: dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(target, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()

def _time(value: Any) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        raise ValueError("timezone required")
    return dt

def _number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and 0 <= value <= 1

def _blocked(codes: list[str]) -> dict[str, Any]:
    return {"schema": SCHEMA, "status": "BLOCK", "blocking_codes": sorted(set(codes)), "benchmark_admitted": False, "cutover_eligible": False}

def evaluate(raw: dict[str, Any], target: dict[str, Any], upstream: dict[str, Any]) -> dict[str, Any]:
    """Compute observed gaps; require upstream four-arm evidence and frozen expert criteria."""
    codes: list[str] = []
    if not all(isinstance(x, dict) for x in (raw, target, upstream)):
        return _blocked(["INVALID_INPUT"])
    if raw.get("benchmark_scope") != "EXPERT_TASK_PERFORMANCE_E2E":
        codes.append("BENCHMARK_SCOPE_INVALID")
    if raw.get("raw_frozen") is not True:
        codes.append("RAW_NOT_FROZEN")
    if target.get("schema") != "PE10E_FROZEN_EXPERT_TARGET_V1":
        codes.append("TO_BE_SCHEMA_INVALID")
    if not target.get("target_standard_ref") or not target.get("source_commit"):
        codes.append("TO_BE_STANDARD_SOURCE_MISSING")
    if target.get("frozen_before_raw") is not True or raw.get("target_contract_sha256") != digest(target):
        codes.append("TO_BE_NOT_SOURCE_BOUND")
    try:
        if _time(target["frozen_at"]) >= _time(raw["raw_started_at"]):
            codes.append("TO_BE_NOT_FROZEN_BEFORE_RAW")
    except (ValueError, TypeError, KeyError, AttributeError):
        codes.append("TO_BE_FREEZE_TIME_INVALID")
    if (upstream.get("schema") != "PROFILE_EXPERT_BEHAVIOR_SCORE_V1" or
        upstream.get("status") != "BENCHMARK_PASS" or upstream.get("blocking_codes") or
        upstream.get("cutover_eligible") is not False):
        codes.append("FOUR_ARM_BENCHMARK_NOT_ADMITTED")
    # The AS-IS is the EFFECTIVE pre-update profile, not an assumed arm C.
    # A can be current when starting from generic, B after updater v0.1,
    # and C only if current Evolution is already the exact effective profile.
    binding = target.get("as_is_binding")
    if not isinstance(binding, dict):
        codes.append("AS_IS_BINDING_MISSING")
        binding = {}
    as_is_arm = binding.get("arm")
    if as_is_arm not in ARMS[:-1]:
        codes.append("AS_IS_ARM_NOT_PRE_UPDATE")
    if not all(isinstance(binding.get(k), str) and binding[k].strip()
               for k in ("profile_revision", "source_ref", "source_sha256", "authority_readback_ref")):
        codes.append("AS_IS_SOURCE_AUTHORITY_MISSING")
    if not (isinstance(binding.get("source_sha256"), str) and
            len(binding["source_sha256"]) == 64 and
            all(c in "0123456789abcdef" for c in binding["source_sha256"])):
        codes.append("AS_IS_SOURCE_SHA_INVALID")
    raw_binding = raw.get("as_is_binding")
    if not isinstance(raw_binding, dict) or any(
        raw_binding.get(k) != binding.get(k)
        for k in ("arm", "profile_revision", "source_ref", "source_sha256", "authority_readback_ref")
    ):
        codes.append("AS_IS_SOURCE_NOT_BOUND_TO_RAW")
    cases = raw.get("cases")
    domains = target.get("domain_targets")
    if not isinstance(cases, list) or not cases:
        codes.append("NO_EXECUTED_CASES")
        cases = []
    if not isinstance(domains, dict) or not domains:
        codes.append("TO_BE_DOMAIN_TARGETS_MISSING")
        domains = {}
    ids = [c.get("case_id") for c in cases if isinstance(c, dict)]
    if len(ids) != len(cases) or any(not x for x in ids) or len(set(ids)) != len(ids):
        codes.append("CASE_IDS_NOT_UNIQUE")
    if upstream.get("case_count") != len(cases):
        codes.append("UPSTREAM_CASE_COUNT_MISMATCH")
    encountered = set()
    acc: dict[str, dict[str, Any]] = {}
    total_weight = 0.0
    sums = {arm: 0.0 for arm in ARMS}
    for case in cases:
        if not isinstance(case, dict):
            codes.append("CASE_INVALID")
            continue
        domain = case.get("domain_family")
        if not isinstance(domain, str) or not domain:
            codes.append("CASE_DOMAIN_INVALID")
            continue
        encountered.add(domain)
        if case.get("task_type") != "OPEN_TASK":
            codes.append("MCQ_OR_PROXY_CASE_NOT_ACCEPTABLE")
        dif = case.get("difficulty")
        if type(dif) not in (int, float) or not 1 <= dif <= 5:
            codes.append("CASE_DIFFICULTY_INVALID")
            continue
        weight = float(dif) * (2 if case.get("critical") is True else 1)
        values = {}
        if as_is_arm in ARMS[:-1]:
            as_is_record = case.get("arms", {}).get(as_is_arm) if isinstance(case.get("arms"), dict) else None
            if not isinstance(as_is_record, dict) or as_is_record.get("profile_revision") != binding.get("profile_revision"):
                codes.append("AS_IS_PROFILE_REVISION_MISMATCH")
        for arm in ARMS:
            record = case.get("arms", {}).get(arm) if isinstance(case.get("arms"), dict) else None
            score = record.get("score") if isinstance(record, dict) else None
            if not _number(score):
                codes.append("ARM_SCORE_MISSING_OR_INVALID")
                continue
            values[arm] = float(score)
        if len(values) != len(ARMS):
            continue
        a = acc.setdefault(domain, {"weight": 0.0, "cases": 0, "sum": {arm: 0.0 for arm in ARMS}})
        a["weight"] += weight
        a["cases"] += 1
        total_weight += weight
        for arm, score in values.items():
            a["sum"][arm] += weight * score
            sums[arm] += weight * score
    if set(domains) != encountered:
        codes.append("TO_BE_DOMAIN_COVERAGE_MISMATCH")
    if total_weight <= 0:
        codes.append("NO_VALID_SCORES")
    reported = upstream.get("arm_scores", {})
    if not isinstance(reported, dict):
        reported = {}
    for arm in ARMS:
        calculated = sums[arm] / total_weight if total_weight else None
        if calculated is None or not _number(reported.get(arm)) or abs(calculated - float(reported[arm])) > 0.000002:
            codes.append("UPSTREAM_SCORE_MISMATCH")
    if codes:
        return _blocked(codes)
    rows = []
    for domain in sorted(domains):
        item = domains[domain]
        if not isinstance(item, dict):
            codes.append("TO_BE_DOMAIN_CONFIG_INVALID")
            continue
        minimum, n = item.get("quality_min"), item.get("minimum_open_cases")
        if not _number(minimum) or minimum == 0 or type(n) is not int or n < 1:
            codes.append("TO_BE_THRESHOLD_INVALID")
            continue
        if not item.get("rubric_ref") or not item.get("standard_ref"):
            codes.append("TO_BE_RUBRIC_OR_STANDARD_MISSING")
            continue
        v = acc[domain]
        if v["cases"] < n:
            codes.append("TO_BE_SAMPLE_NOT_MET")
        as_is = v["sum"][as_is_arm] / v["weight"]
        post = v["sum"]["D_EVOLUTION_TARGET"] / v["weight"]
        original = v["sum"]["A_ORIGINAL"] / v["weight"]
        gap_before = max(0., float(minimum) - as_is)
        gap_after = max(0., float(minimum) - post)
        rows.append({
            "domain_family": domain, "cases": v["cases"],
            "original_A": round(original, 6),
            "as_is_effective": round(as_is, 6),
            "as_is_arm": as_is_arm,
            "as_is_profile_revision": binding["profile_revision"],
            "to_be_minimum": minimum,
            "post_updater_D": round(post, 6),
            "gap_initial": round(gap_before, 6),
            "gap_residual": round(gap_after, 6),
            "gap_closed": round(max(0., gap_before - gap_after), 6),
            "target_attainment_pct": round(min(100., post / minimum * 100), 2),
            "target_met": post >= minimum,
            "target_standard_ref": item["standard_ref"],
        })
    if codes:
        return _blocked(codes)
    unmet = [r["domain_family"] for r in rows if not r["target_met"]]
    return {
        "schema": SCHEMA,
        "status": "TARGET_PASS" if not unmet else "TARGET_FAIL",
        "blocking_codes": [f"TO_BE_NOT_MET:{d}" for d in unmet],
        "benchmark_scope": "EXPERT_TASK_PERFORMANCE_E2E",
        "target_contract_sha256": digest(target),
        "reference_baseline": as_is_arm,
        "baseline_profile_revision": binding["profile_revision"],
        "baseline_source_sha256": binding["source_sha256"],
        "historic_control": "A_ORIGINAL",
        "domain_results": rows,
        "target_met_domains": len(rows)-len(unmet),
        "total_domains": len(rows),
        "benchmark_admitted": False,
        "cutover_eligible": False,
        "note": "Supplementary gate only. External runtime provenance and independent assurance remain mandatory."
    }

def main() -> int:
    """Read existing artifacts; never generate model outputs or admit deployment."""
    parser = argparse.ArgumentParser(description="Supplementary PE10E_C4 AS-IS/TO-BE/GAP calculation")
    parser.add_argument("--raw", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--upstream", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = evaluate(
            json.loads(args.raw.read_text(encoding="utf-8")),
            json.loads(args.target.read_text(encoding="utf-8")),
            json.loads(args.upstream.read_text(encoding="utf-8")),
        )
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        result = _blocked(["INPUT_ARTIFACT_UNAVAILABLE_OR_INVALID"])
        result["detail"] = type(exc).__name__
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    return 0 if result["status"] == "TARGET_PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
