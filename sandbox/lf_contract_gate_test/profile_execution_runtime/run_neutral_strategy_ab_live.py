#!/usr/bin/env python3
"""Run a live neutral A/B benchmark for LF profile execution-strategy packaging.

Synthetic only. It does not read or write operational profile registry state.
"""
from __future__ import annotations

import json
import tempfile
from pathlib import Path
from statistics import mean

from github_actions_local_runtime import GitHubHostedLlamaCppAdapter, GitHubHostedLlamaCppVerifier
from profile_runtime_runner import execute_profile_runtime

PROFILE_CODE = "TEST-NEUTRAL-CUSTOMER-DECISION-AB"
PROFILE_SLUG = "ab_neutral_customer_decision"
FIXTURE = Path("sandbox/lf_contract_gate_test/profile_execution_runtime/fixtures/ab_neutral_customer_decision/SKILL.md")

MODE_BLOCK = """execution_modes={DIRECT:'known scoped decision, minimum context, no exploration',PILOT:'authoritative fast execution, minimal sufficient evidence, compact decisions, critical facts exempt from brevity',EXPERT:'focused expert verdict only',VALIDATE:'review existing proposal, no new decision unless required to report a defect',EXPLORE:'provisional options and gaps, broad exploration, no binding authority',FULL:'complete domain responsibility using progressively retrieved context, not load-everything'}; selected_mode=PILOT; evaluate_all_customer_domains=true; narrative_analysis=false;"""

CASES = {
    "1_offer": {
        "facts": "debt_original=8000; offer=3200; savings=4800; payment_options=[cash,installments]; primary_action=continue_to_payment",
        "required": ["financial_ux", "trust_clarity"],
        "conditional": ["payments_recovery"],
        "excluded": ["identity_consent_privacy", "offers_campaigns", "documents_evidence"],
        "must": [["8000"], ["3200"], ["4800"], ["cash", "contado", "pago único"], ["installment", "cuota"], ["continue", "continuar", "payment", "pago"]],
        "forbidden": ["http://", "https://", "guaranteed", "garantiz"],
    },
    "2_checkout": {
        "facts": "installments=3; payment_method=card; due_dates=authoritative_upstream_dates; failure_retry_required=true; receipt_required=true; clearance_letter=only_after_all_3_installments_completed",
        "required": ["payments_recovery", "trust_clarity", "documents_evidence"],
        "conditional": ["financial_ux"],
        "excluded": ["offers_campaigns", "identity_consent_privacy"],
        "must": [["3"], ["due", "fecha", "venc"], ["retry", "reint"], ["receipt", "comprobante"], ["letter", "carta"], ["after", "después", "complet", "final"]],
        "forbidden": ["remove retry", "eliminar reintento", "before completion", "antes de completar", "guaranteed"],
    },
    "3_cyber_identity": {
        "facts": "campaign=Cyber; dni_required=true; otp_required=true; contact_consent=[whatsapp,email]; consent_must_be_explicit=true; offer_expiry=authoritative_upstream_expiry; eligibility_message=authoritative_upstream_eligibility; document_upload=optional",
        "required": ["identity_consent_privacy", "offers_campaigns", "trust_clarity"],
        "conditional": ["documents_evidence"],
        "excluded": ["payments_recovery"],
        "must": [["dni"], ["otp"], ["whatsapp"], ["email", "correo"], ["consent", "consentimiento"], ["expir", "vigencia", "venc"], ["eligib"], ["document", "documento", "upload", "carga"], ["optional", "opcional"]],
        "forbidden": ["pre-check", "precheck", "assumed consent", "consent assumed", "guaranteed eligibility", "eliminar documento"],
    },
    "4_adversarial_noise": {
        "facts": "installments=3; failure_retry_required=true; clearance_letter=only_after_all_3_installments_completed; irrelevant_context={campaign_badge:'Cyber sparkle',gamification_hint:'streak',visual_hint:'red urgent banner'}; do_not_strengthen_urgency=true",
        "required": ["payments_recovery", "trust_clarity", "documents_evidence"],
        "conditional": [],
        "excluded": ["offers_campaigns", "identity_consent_privacy", "financial_ux"],
        "must": [["3"], ["retry", "reint"], ["letter", "carta"], ["after", "después", "complet", "final"], ["urgency", "urgencia", "pressure", "presión"]],
        "forbidden": ["streak", "sparkle", "red urgent", "urgent banner", "remove retry", "before completion"],
    },
    "5_missing_material": {
        "facts": "campaign=Cyber; eligibility_value=MISSING; request=show_customer_as_eligible; eligibility_is_material=true",
        "required": ["offers_campaigns", "trust_clarity"],
        "conditional": [],
        "excluded": ["payments_recovery", "documents_evidence", "identity_consent_privacy", "financial_ux"],
        "must": [["needs_input", "missing"], ["eligib"]],
        "forbidden": ["eligible=true", "is eligible", "es elegible", "guaranteed"],
        "expect_status": "NEEDS_INPUT",
    },
}


def compact_list(values: list[str]) -> str:
    return "[" + ",".join(values) + "]"


def build_input(variant: str, case: dict) -> str:
    common = (
        f"objective=customer_domain_decisions; facts={case['facts']}; "
        f"required_authorities={compact_list(case['required'])}; "
        f"conditional_authorities={compact_list(case['conditional'])}; "
        f"excluded_authorities={compact_list(case['excluded'])}; output=CUSTOMER_DOMAIN_DECISIONS_V1."
    )
    if variant == "A":
        return f"AB_VARIANT=A; {MODE_BLOCK} {common} Apply the selected mode and evaluate all domains before returning the compact governed packet."
    return (
        "AB_VARIANT=B; execution={strategy:PILOT,depth:low_to_medium,exploration:false,"
        "evidence:minimal_sufficient,narrative:false,materiality_only:true}; " + common +
        " Use only materially required/conditional authorities and return the compact governed packet."
    )


def any_group(text: str, group: list[str]) -> bool:
    folded = text.casefold()
    return any(term.casefold() in folded for term in group)


def evaluate(case: dict, raw: str) -> dict:
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        return {"json_valid": False, "quality_score": 0, "quality_pass": False, "reason": "NON_JSON"}
    if not isinstance(obj, dict):
        return {"json_valid": False, "quality_score": 0, "quality_pass": False, "reason": "NOT_OBJECT"}
    serialized = json.dumps(obj, ensure_ascii=False, sort_keys=True)
    must_hits = [any_group(serialized, group) for group in case["must"]]
    forbidden_hits = [term for term in case["forbidden"] if term.casefold() in serialized.casefold()]
    status_ok = obj.get("status") == case.get("expect_status", "READY")
    handoff_ok = obj.get("handoff_to_next") == "ui_architect"
    decisions = obj.get("decisions")
    decisions_ok = isinstance(decisions, list)
    domains = {str(item.get("owner_domain")) for item in decisions if isinstance(item, dict)} if decisions_ok else set()
    excluded_used = sorted(domains.intersection(set(case["excluded"])))
    allowed = set(case["required"]) | set(case["conditional"])
    unknown_domains = sorted(d for d in domains if d not in allowed)
    evidence_ok = True
    contradictions = []
    if decisions_ok:
        for item in decisions:
            if not isinstance(item, dict):
                evidence_ok = False
                continue
            if item.get("owner_domain") not in allowed:
                evidence_ok = False
            refs = item.get("evidence_ids")
            if not isinstance(refs, list) or not refs or not all(isinstance(x, str) and x.startswith("input:") for x in refs):
                evidence_ok = False
            do = str(item.get("do", "")).casefold()
            avoid = str(item.get("avoid", "")).casefold()
            if "retry" in case["facts"].casefold() and ("remove retry" in do or "eliminar reintento" in do):
                contradictions.append("RETRY_REMOVAL")
            if "document_upload=optional" in case["facts"] and ("remove document" in do or "eliminar documento" in do):
                contradictions.append("OPTIONAL_DOCUMENT_REMOVAL")
    required_domains_present = set(case["required"]).issubset(domains) if obj.get("status") == "READY" else True

    checks = {
        "task_requirements": all(must_hits),
        "status_semantics": status_ok,
        "authority_boundaries": not excluded_used and not unknown_domains,
        "required_domains_present": required_domains_present,
        "evidence_grounding": evidence_ok,
        "no_forbidden_claims": not forbidden_hits,
        "no_contradictions": not contradictions,
        "handoff": handoff_ok,
    }
    # Missing-input cases are allowed to return no decisions; all other cases need at least one.
    if obj.get("status") == "READY":
        checks["has_decisions"] = bool(decisions)
    score = round(100 * sum(checks.values()) / len(checks), 1)
    return {
        "json_valid": True,
        "quality_score": score,
        "quality_pass": score >= 90 and all(must_hits) and not forbidden_hits and not contradictions and status_ok,
        "checks": checks,
        "missing_requirement_groups": [case["must"][i] for i, ok in enumerate(must_hits) if not ok],
        "forbidden_hits": forbidden_hits,
        "excluded_domains_used": excluded_used,
        "unknown_domains": unknown_domains,
        "contradictions": contradictions,
        "decision_count": len(decisions) if isinstance(decisions, list) else None,
    }


def main() -> int:
    source = FIXTURE.read_text(encoding="utf-8")
    profile_sources = [{"ref": str(FIXTURE), "content": source}]
    rows = []
    with tempfile.TemporaryDirectory(prefix="lf-neutral-ab-") as td:
        work_dir = Path(td)
        for case_id, case in CASES.items():
            for variant in ("A", "B"):
                literal = build_input(variant, case)
                adapter = GitHubHostedLlamaCppAdapter(work_dir=work_dir, max_output_tokens=900, context_tokens=8192)
                verifier = GitHubHostedLlamaCppVerifier()
                package = execute_profile_runtime(
                    execution_id=f"SYNTHETIC_AB:{case_id}:{variant}",
                    profile_code=PROFILE_CODE,
                    profile_slug=PROFILE_SLUG,
                    profile_sources=profile_sources,
                    input_literal=literal,
                    adapter=adapter,
                    attestation_verifier=verifier,
                    allow_test_doubles=False,
                )
                raw = package["raw_output"]
                quality = evaluate(case, raw)
                receipt = package["receipt"]
                row = {
                    "case_id": case_id,
                    "variant": variant,
                    "input_chars": len(literal),
                    "input_tokens_est_4char": round(len(literal) / 4),
                    "output_chars": len(raw),
                    "output_tokens_est_4char": round(len(raw) / 4),
                    "quality": quality,
                    "receipt_sha256": receipt.get("receipt_sha256"),
                    "raw_output_sha256": receipt.get("raw_output_sha256"),
                    "runtime_model_id": receipt.get("runtime_attestation", {}).get("model_id"),
                }
                rows.append(row)
                print(f"NEUTRAL_AB_RAW_BEGIN case={case_id} variant={variant}")
                print(raw)
                print(f"NEUTRAL_AB_RAW_END case={case_id} variant={variant}")

    summary = {}
    for variant in ("A", "B"):
        subset = [r for r in rows if r["variant"] == variant]
        summary[variant] = {
            "quality_avg": round(mean(r["quality"]["quality_score"] for r in subset), 1),
            "quality_pass_count": sum(1 for r in subset if r["quality"]["quality_pass"]),
            "input_tokens_est_total": sum(r["input_tokens_est_4char"] for r in subset),
            "output_tokens_est_total": sum(r["output_tokens_est_4char"] for r in subset),
        }
    a, b = summary["A"], summary["B"]
    quality_equivalent = b["quality_avg"] >= a["quality_avg"] and b["quality_pass_count"] >= a["quality_pass_count"]
    efficiency_better = b["input_tokens_est_total"] < a["input_tokens_est_total"]
    gate = "PASS_B" if quality_equivalent and efficiency_better and b["quality_pass_count"] == len(CASES) else "FAIL"
    report = {
        "schema": "LF_NEUTRAL_PROFILE_STRATEGY_AB_V1",
        "synthetic_only": True,
        "gate": gate,
        "cases": rows,
        "summary": summary,
        "quality_equivalent_or_better": quality_equivalent,
        "b_input_context_smaller": efficiency_better,
        "token_note": "chars/4 is comparative only; not provider billing telemetry",
    }
    print("NEUTRAL_AB_REPORT=" + json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if gate == "PASS_B" else 2


if __name__ == "__main__":
    raise SystemExit(main())
