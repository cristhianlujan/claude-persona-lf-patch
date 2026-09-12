#!/usr/bin/env python3
"""
NO BYPASS Judge Profile/Card/Skill LF v0.1 — sandbox self-test.

Scope:
- Sandbox/read-only.
- No Supabase write.
- No runtime.
- No production/general enablement.
- Mirror técnico del criterio objetivo para audit-skill-protocols.

Run:
  python3 sandbox/no_bypass_judge_profile_card_skill/no_bypass_judge_selftest.py
"""
from __future__ import annotations

import copy
import json
from typing import Any, Dict, List

APPROVED = {"APROBADO", "PASS", "APPROVED", "OK", "VALIDADO"}
VALID_ARTIFACT_TYPES = {"skill", "card", "perfil", "profile"}
REQUIRED_ACTIVE_ASSET = "ACT-0045"


def has_value(value: Any) -> bool:
    if value is None or value is False:
        return False
    if isinstance(value, str) and value.strip() == "":
        return False
    if isinstance(value, list) and len(value) == 0:
        return False
    if isinstance(value, dict) and len(value) == 0:
        return False
    return True


def is_approved(value: Any) -> bool:
    return str(value or "").strip().upper() in APPROVED


def step_key(step: Dict[str, Any]) -> str:
    return f"{step.get('pack_id', '__root__')}::{step.get('step_order')}::{step.get('step_id')}"


def has_evidence(evidence: Dict[str, Any], key: Any) -> bool:
    return has_value(key) and has_value(evidence.get(str(key)))


def validate(payload: Dict[str, Any]) -> Dict[str, Any]:
    findings: List[str] = []
    evidence = payload.get("evidence") or {}
    canonical = sorted(payload.get("canonical_steps") or [], key=lambda x: x.get("step_order", 999999))
    executed = sorted(payload.get("steps") or [], key=lambda x: x.get("step_order", 999999))
    packs = payload.get("packs") or []

    if not has_value(payload.get("operation_code")):
        findings.append("OPERATION_CODE_REQUIRED")
    if str(payload.get("artifact_type", "")).strip().lower() not in VALID_ARTIFACT_TYPES:
        findings.append("ARTIFACT_TYPE_INVALID")
    if payload.get("canonical_protocol_loaded") is not True:
        findings.append("CANONICAL_PROTOCOL_REQUIRED")
    if not has_value(payload.get("canonical_protocol_source")):
        findings.append("CANONICAL_SOURCE_REQUIRED")
    if REQUIRED_ACTIVE_ASSET not in str(payload.get("active_asset", "")).upper():
        findings.append("ACTIVE_ASSET_REQUIRED")
    if not canonical:
        findings.append("CANONICAL_STEPS_REQUIRED")
    if not executed:
        findings.append("EXECUTED_STEPS_REQUIRED")

    canonical_keys = [step_key(s) for s in canonical]
    executed_keys = [step_key(s) for s in executed]
    canonical_set = set(canonical_keys)
    executed_set = set(executed_keys)

    for key, step in zip(canonical_keys, canonical):
        if step.get("required", True) is not False and key not in executed_set:
            findings.append(f"CANONICAL_STEP_NOT_EXECUTED:{key}")
    for key in executed_keys:
        if key not in canonical_set:
            findings.append(f"NON_CANONICAL_STEP_EXECUTED:{key}")
    if canonical_keys != executed_keys:
        findings.append("SEQUENCE_ORDER_INVALID")

    for step in executed:
        key = step_key(step)
        evidence_key = step.get("evidence_key") or step.get("evidence_required")
        if not has_evidence(evidence, evidence_key):
            findings.append(f"STEP_EVIDENCE_REQUIRED:{key}")
        if step.get("evidence_reviewed_by_judge") is not True:
            findings.append(f"STEP_EVIDENCE_JUDGE_REVIEW_REQUIRED:{key}")
        if step.get("approved_by_judge") is not True and not is_approved(step.get("judge_status")) and not is_approved(step.get("status")):
            findings.append(f"STEP_JUDGE_APPROVAL_REQUIRED:{key}")
        if has_value(step.get("restrictions")):
            findings.append(f"STEP_RESTRICTIONS_NOT_ALLOWED:{key}")
        if has_value(step.get("missing")):
            findings.append(f"STEP_MISSING_NOT_ALLOWED:{key}")
        if has_value(step.get("observations")):
            findings.append(f"STEP_OBSERVATIONS_NOT_ALLOWED:{key}")

    canonical_pack_ids = {s.get("pack_id") for s in canonical if has_value(s.get("pack_id"))}
    provided_pack_ids = {p.get("pack_id") for p in packs}
    if canonical_pack_ids and not packs:
        findings.append("PACKS_REQUIRED")
    for pack_id in canonical_pack_ids:
        if pack_id not in provided_pack_ids:
            findings.append(f"CANONICAL_PACK_NOT_VALIDATED:{pack_id}")
    for pack in packs:
        pack_id = pack.get("pack_id")
        if pack_id not in canonical_pack_ids:
            findings.append(f"NON_CANONICAL_PACK:{pack_id}")
        if pack.get("approved_by_judge") is not True and not is_approved(pack.get("judge_status")) and not is_approved(pack.get("status")):
            findings.append(f"PACK_JUDGE_APPROVAL_REQUIRED:{pack_id}")
        if has_value(pack.get("restrictions")):
            findings.append(f"PACK_RESTRICTIONS_NOT_ALLOWED:{pack_id}")
        if has_value(pack.get("missing")):
            findings.append(f"PACK_MISSING_NOT_ALLOWED:{pack_id}")
        if not any(s.get("pack_id") == pack_id for s in executed):
            findings.append(f"PACK_STEPS_REQUIRED:{pack_id}")

    for flag in (payload.get("judge") or {}).get("fail_if", []):
        if has_evidence(evidence, flag):
            findings.append(f"JUDGE_FAIL_FLAG_PRESENT:{flag}")
    for flag in (payload.get("judge") or {}).get("pass_if", []):
        if not has_evidence(evidence, flag):
            findings.append(f"JUDGE_PASS_FLAG_MISSING:{flag}")

    readback = payload.get("readback") or {}
    if readback.get("performed") is not True:
        findings.append("READBACK_REQUIRED")
    if readback.get("matches_expected") is not True:
        findings.append("READBACK_MATCH_REQUIRED")
    if readback.get("approved_by_judge") is not True:
        findings.append("READBACK_JUDGE_APPROVAL_REQUIRED")
    if (payload.get("audit_log") or {}).get("registered") is not True:
        findings.append("AUDIT_LOG_REQUIRED")

    findings = sorted(set(findings))
    return {
        "status": "APROBADO" if not findings else "BLOCKED",
        "approved": not findings,
        "fail_closed": True,
        "findings": findings,
    }


def valid_payload() -> Dict[str, Any]:
    canonical = [
        {"pack_id": "PACK_ROUTER", "step_order": 1, "step_id": "router", "evidence_required": "EV_ROUTER"},
        {"pack_id": "PACK_PROTOCOL", "step_order": 2, "step_id": "canonical_protocol", "evidence_required": "EV_PROTOCOL"},
        {"pack_id": "PACK_EXECUTION", "step_order": 3, "step_id": "generate_candidate", "evidence_required": "EV_CANDIDATE"},
        {"pack_id": "PACK_VERIFICATION", "step_order": 4, "step_id": "readback", "evidence_required": "EV_READBACK"},
    ]
    steps = []
    for step in canonical:
        item = copy.deepcopy(step)
        item.update({
            "status": "APROBADO",
            "judge_status": "APROBADO",
            "evidence_reviewed_by_judge": True,
            "approved_by_judge": True,
            "restrictions": [],
            "missing": [],
            "observations": [],
        })
        steps.append(item)
    return {
        "operation_code": "CREATE_PROFILE_CARD_SKILL_NO_BYPASS_SANDBOX",
        "artifact_type": "perfil",
        "active_asset": "ACT-0045 / SKILL_CREADORA_PERFILES_Y_CARDS_LF",
        "canonical_protocol_loaded": True,
        "canonical_protocol_source": "Supabase/public.v_lf_fuente_operativa/ACT-0045",
        "canonical_steps": canonical,
        "steps": steps,
        "packs": [
            {"pack_id": "PACK_ROUTER", "status": "APROBADO", "approved_by_judge": True, "restrictions": [], "missing": []},
            {"pack_id": "PACK_PROTOCOL", "status": "APROBADO", "approved_by_judge": True, "restrictions": [], "missing": []},
            {"pack_id": "PACK_EXECUTION", "status": "APROBADO", "approved_by_judge": True, "restrictions": [], "missing": []},
            {"pack_id": "PACK_VERIFICATION", "status": "APROBADO", "approved_by_judge": True, "restrictions": [], "missing": []},
        ],
        "evidence": {
            "EV_ROUTER": {"source": "router", "reviewed": True},
            "EV_PROTOCOL": {"source": "ACT-0045", "reviewed": True},
            "EV_CANDIDATE": {"source": "candidate_package", "reviewed": True},
            "EV_READBACK": {"source": "readback", "reviewed": True},
            "EV_FINAL_PASS": {"source": "judge", "reviewed": True},
        },
        "judge": {"pass_if": ["EV_FINAL_PASS"], "fail_if": ["EV_BLOCKER"]},
        "readback": {"performed": True, "matches_expected": True, "approved_by_judge": True},
        "audit_log": {"registered": True},
    }


def mutate_case(name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    p = copy.deepcopy(payload)
    if name == "non_canonical_step":
        p["steps"].append({"pack_id": "PACK_EXECUTION", "step_order": 99, "step_id": "invented_step", "evidence_required": "EV_X", "approved_by_judge": True, "evidence_reviewed_by_judge": True})
    elif name == "missing_step_evidence":
        p["evidence"].pop("EV_CANDIDATE", None)
    elif name == "step_not_judge_reviewed":
        p["steps"][1]["evidence_reviewed_by_judge"] = False
    elif name == "pack_restriction":
        p["packs"][2]["restrictions"] = ["solo aprobado con condicion"]
    elif name == "pack_missing":
        p["packs"][2]["missing"] = ["falta sustento"]
    elif name == "pass_with_observation":
        p["steps"][2]["observations"] = ["pendiente menor"]
    elif name == "missing_readback":
        p["readback"]["performed"] = False
    elif name == "missing_audit_log":
        p["audit_log"]["registered"] = False
    elif name == "no_act_0045":
        p["active_asset"] = "ACT-0001"
    elif name == "protocol_not_loaded":
        p["canonical_protocol_loaded"] = False
    return p


def main() -> int:
    base = valid_payload()
    cases = {"valid_full_approved": (base, "APROBADO")}
    for case in [
        "non_canonical_step",
        "missing_step_evidence",
        "step_not_judge_reviewed",
        "pack_restriction",
        "pack_missing",
        "pass_with_observation",
        "missing_readback",
        "missing_audit_log",
        "no_act_0045",
        "protocol_not_loaded",
    ]:
        cases[case] = (mutate_case(case, base), "BLOCKED")

    results = []
    ok_all = True
    for name, (payload, expected) in cases.items():
        out = validate(payload)
        ok = out["status"] == expected
        ok_all = ok_all and ok
        results.append({"case": name, "expected": expected, "actual": out["status"], "ok": ok, "findings": out["findings"]})

    report = {
        "suite": "NO_BYPASS_JUDGE_PROFILE_CARD_SKILL_LF_v0_1_SANDBOX_SELFTEST",
        "overall_status": "PASS" if ok_all else "FAIL",
        "authority": "Python/GitHub sandbox mirror; audit-skill-protocols remains target official judge",
        "results": results,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
