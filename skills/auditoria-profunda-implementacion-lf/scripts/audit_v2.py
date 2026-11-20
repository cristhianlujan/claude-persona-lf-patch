"""Evidence accounting for deep audits; native reasoning supplies semantic reviews.

Presence, word count, a PASS string or a snapshot flag never prove content quality.
These functions check accounting and contextual obligations, not external authority.
"""
from __future__ import annotations

import re

STEP_ORDERS = (0, 10, 20, 30, 40, 45, 47, 50, 60, 70, 80)
FIELD_STATES = {"ACCEPTABLE", "WEAK", "MISSING", "CONTRADICTORY", "NOT_EVALUATED", "NOT_APPLICABLE"}
EVIDENCE_KINDS = {"MEASURED_THIS_AUDIT", "MEASURED_PREVIOUSLY", "CODE_READ_ONLY", "NOT_MEASURED"}
COLORS = {"ACCEPTABLE": ("🟢", "#dcfce7"), "WEAK": ("🟡", "#fef9c3"),
          "MISSING": ("🔴", "#fee2e2"), "CONTRADICTORY": ("🔴", "#fee2e2"),
          "NOT_EVALUATED": ("⚪", "#e5e7eb"), "NOT_APPLICABLE": ("—", "#f3f4f6")}


def lot_coverage(tasks):
    applicable = [t for t in tasks if t["status"] != "NOT_APPLICABLE"]
    done = sum(t["status"] == "VERIFIED" for t in applicable)
    return {"verified": done, "applicable": len(applicable),
            "percent": round(100 * done / len(applicable), 2) if applicable else None,
            "not_executed": sum(t["status"] == "NOT_EXECUTED" for t in applicable),
            "blocked": sum(t["status"] == "BLOCKED" for t in applicable)}


def flow_verdict(report):
    """A completed audit lot or old persisted 11/11 cannot accredit a new E2E."""
    reasons = []
    context = report["audit_context"]
    if not context["new_e2e_executed"]:
        reasons.append("NO_NEW_E2E_EXECUTION")
    steps = report["steps"]
    if sorted(s["order"] for s in steps) != list(STEP_ORDERS):
        reasons.append("ELEVEN_STEP_LEDGER_INCOMPLETE")
    for step in steps:
        if (step["behavior_status"] != "EXECUTED_AND_VERIFIED"
                or step["runtime_origin"] != "NEW_AUDIT_RUN"
                or not step["resolved_receipts"]
                or step["execution_id"] != context["source_execution_id"]):
            reasons.append("STEP_NOT_ACCREDITED:" + str(step["order"]))
    if context["ig_execution_required"] and not context["ig_invocation_verified"]:
        reasons.append("IG_INVOCATION_NOT_VERIFIED")
    for hop in report.get("hops", []):
        optional_ig = (hop["id"].startswith("H-IG-") and not context["ig_execution_required"]
            and hop["run_binding"] == "NOT_APPLICABLE" and hop["hash_binding"] == "NOT_APPLICABLE"
            and bool(hop["applicability_reason"]))
        if optional_ig:
            continue
        if hop["run_binding"] not in ("RECORDED_PARENT_MATCH",):
            reasons.append("HOP_RUN_NOT_ACCREDITED:" + hop["id"])
        if hop["hash_binding"] not in ("RECORDED_MATCH", "NOT_APPLICABLE"):
            reasons.append("HOP_HASH_NOT_ACCREDITED:" + hop["id"])
    return {"verdict": "FLOW_ACCREDITED" if not reasons else "FLOW_NOT_ACCREDITED", "reasons": reasons}


def contract_grade(contract, profiles):
    """Use the worst contextual required field; never average away missing meaning."""
    profile = profiles[contract["type"]]
    fields = contract["fields"]
    errors = []
    if contract["format"] not in profile["accepted_formats"]:
        errors.append("CONTRACT_FORMAT_INCOMPATIBLE_WITH_TYPE")
    for name, requirement in profile["fields"].items():
        cell = fields.get(name)
        if cell is None:
            errors.append("REVIEW_CELL_MISSING:" + name)
            continue
        state = cell.get("status")
        if state not in FIELD_STATES:
            errors.append("FIELD_REVIEW_STATUS_INVALID:" + name)
            continue
        if not cell.get("reason"):
            errors.append("CONTEXT_REASON_MISSING:" + name)
        if state == "NOT_APPLICABLE" and requirement["required"]:
            errors.append("REQUIRED_FIELD_CANNOT_BE_NA:" + name)
        if state == "ACCEPTABLE":
            if (not cell.get("literal") or not cell.get("source_refs")
                    or not cell.get("semantic_checks")
                    or not cell.get("consumer_expectation")):
                errors.append("SEMANTIC_ACCEPTANCE_UNSUPPORTED:" + name)
        if state in ("WEAK", "MISSING", "CONTRADICTORY"):
            if not cell.get("proposed_rewrite") or not cell.get("consumer_expectation"):
                errors.append("ACTIONABLE_REWRITE_MISSING:" + name)
    if errors:
        return {"grade": "NOT_EVALUATED", "errors": errors}
    critical = [fields[n]["status"] for n, r in profile["fields"].items() if r["required"] and r["critical"]]
    required = [fields[n]["status"] for n, r in profile["fields"].items() if r["required"]]
    if any(s in ("MISSING", "CONTRADICTORY") for s in critical):
        grade = "LOW"
    elif "WEAK" in critical:
        grade = "LOW"
    elif "NOT_EVALUATED" in required:
        grade = "NOT_EVALUATED"
    elif any(s in ("WEAK", "MISSING", "CONTRADICTORY") for s in required):
        grade = "MEDIUM"
    else:
        grade = "ACCEPTABLE"
    return {"grade": grade, "errors": []}


def vague_candidates(text):
    """Hints only. Negation, cross-references and domain context require native review."""
    phrases = ("según corresponda", "validar correctamente", "gestionar adecuadamente",
               "revisar el backend", "manejar errores", "datos necesarios")
    return [{"phrase": p, "status": "HYPOTHESIS_REQUIRES_CONTEXT"}
            for p in phrases if p in text.lower()]


def plan_summary(explain):
    plan = explain[0]["QUERY PLAN"][0]
    nodes = []
    def walk(node):
        nodes.append({k: node[k] for k in ("Node Type", "Relation Name", "Index Name", "Actual Rows",
                                          "Actual Loops", "Shared Hit Blocks", "Shared Read Blocks") if k in node})
        for child in node.get("Plans", []):
            walk(child)
    walk(plan["Plan"])
    return {"execution_ms": plan["Execution Time"], "planning_ms": plan.get("Planning Time"),
            "actual_rows": plan["Plan"]["Actual Rows"],
            "shared_hit_blocks": plan["Plan"].get("Shared Hit Blocks", 0),
            "shared_read_blocks": plan["Plan"].get("Shared Read Blocks", 0), "nodes": nodes,
            "materialize_plan_node_is_materialized_view": False}


def materialization_assessment(measurement):
    if measurement.get("immediate_freshness") is True:
        return {"decision": "REJECT_MATERIALIZATION", "reason": "IMMEDIATE_FRESHNESS_REQUIRED", "benefit_ms": None}
    required = ("frequency_measured", "cost_measured", "equivalence_verified", "refresh_verified",
                "security_equivalent", "invalidation_verified")
    if not all(measurement.get(k) is True for k in required):
        return {"decision": "NOT_EVALUATED", "reason": "FREQUENCY_COST_OR_SAFETY_NOT_PROVEN", "benefit_ms": None}
    window, lag = measurement.get("freshness_budget_ms"), measurement.get("worst_refresh_lag_ms")
    if not isinstance(window, (int, float)) or not isinstance(lag, (int, float)) or window <= 0 or lag > window:
        return {"decision": "REJECT_MATERIALIZATION", "reason": "REFRESH_EXCEEDS_FRESHNESS_BUDGET", "benefit_ms": None}
    values = [measurement.get(k) for k in ("calls_per_interval", "mean_query_ms", "refresh_cost_ms")]
    if any(type(v) not in (int, float) or v < 0 for v in values):
        return {"decision": "NOT_EVALUATED", "reason": "MEASURED_NUMBERS_MISSING", "benefit_ms": None}
    benefit = values[0] * values[1] - values[2]
    return {"decision": "OPTIONAL_CANDIDATE" if benefit > 0 else "KEEP_CURRENT",
            "reason": "MEASURED_FREQUENCY_TIMES_COST_MINUS_REFRESH", "benefit_ms": benefit}


def sample_metrics(rows):
    passes = sum(r["pass_steps"] for r in rows)
    missing = sum(r["pass_missing_evidence_ref"] for r in rows)
    empty = sum(r["pass_empty_payload"] for r in rows)
    reported = [r for r in rows if r["ig_reported"]]
    no_invocation = sum(r["ig_invocations"] == 0 for r in reported)
    statuses = {}
    for row in rows:
        status = row.get("status", "NOT_RECORDED")
        statuses[status] = statuses.get(status, 0) + 1
    return {"sampled_runs": len(rows), "run_status_counts": statuses, "persisted_pass_steps": passes,
            "pass_missing_evidence_ref": missing,
            "pass_missing_evidence_ref_percent": round(100 * missing / passes, 2) if passes else None,
            "pass_empty_payload": empty,
            "ig_reported_runs": len(reported), "ig_reported_without_invocation": no_invocation,
            "ig_reported_without_invocation_percent": round(100 * no_invocation / len(reported), 2) if reported else None,
            "confirmed_false_pass_rate": None,
            "interpretation": "Pointer presence and naming anomalies are indicators, not semantic false-PASS classification. IG may be optional."}


def negative_coverage(emitters):
    eligible = [e for e in emitters if e["classification"] == "EMITTER"]
    executed = [e for e in eligible if e["negative_test"]["status"] == "EXECUTED_REJECTED_BROKEN_INPUT"]
    return {"emitters": len(eligible), "negatives_verified": len(executed),
            "percent": round(100 * len(executed) / len(eligible), 2) if eligible else None,
            "unverified_ids": [e["id"] for e in eligible if e not in executed]}
