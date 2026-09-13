#!/usr/bin/env python3
from __future__ import annotations
from typing import Any, Mapping

PASS="PASS"; BLOCKED="BLOCKED"
EXPECTED_STATUSES=["RESOLVED","NO_DIRECT_CARD","AMBIGUOUS","BLOCKED"]
EXPECTED_MODES=["EXACT","COMPATIBLE","COMPOSED","GENERIC_SAFE"]
EXPECTED_FALLBACK=["CONTRACT_SCHEMA","GENERIC_CAPABILITY","SAFE_COMPOSITION","MANUAL_REQUIRED"]
SAFE_FALLBACK=EXPECTED_FALLBACK[:-1]

def _block(code:str,**extra:Any)->dict: return {"status":BLOCKED,"code":code,**extra}

def _attempt_evidence_ok(item:Mapping[str,Any])->bool:
    return item.get("typed_attempt") is True and bool(item.get("reason")) and bool(item.get("evidence_ref"))

def validate_contract(c:Mapping[str,Any])->dict:
    if c.get("contract_version")!="S31_CANONICAL_CARD_RESOLUTION_V0_1": return _block("BLOCK_CARD_CONTRACT_VERSION")
    if c.get("resolution_statuses")!=EXPECTED_STATUSES: return _block("BLOCK_CARD_STATUS_VOCABULARY")
    if c.get("resolution_modes")!=EXPECTED_MODES: return _block("BLOCK_CARD_MODE_VOCABULARY")
    if c.get("fallback_sequence")!=EXPECTED_FALLBACK: return _block("BLOCK_CARD_FALLBACK_ORDER")
    inv=c.get("invariants") or {}
    required_true=(
        "no_direct_card_is_not_manual","ambiguous_fail_closed","source_authority_precedence",
        "manual_requires_all_safe_alternatives_exhausted","manual_requires_explicit_no_unresolved_blocker_evidence",
        "typed_attempt_evidence_required","fallback_attempts_unique_and_ordered",
        "unknown_fallback_alternatives_forbidden","cards_define_how_not_what"
    )
    if any(inv.get(k) is not True for k in required_true): return _block("BLOCK_CARD_INVARIANT_MISSING")
    if inv.get("schema_invention_allowed") is not False: return _block("BLOCK_SCHEMA_INVENTION_ALLOWED")
    compat=c.get("compatibility_policy") or {}
    if compat.get("big_bang_migration") is not False or compat.get("independent_s26_patch_required") is not False:
        return _block("BLOCK_CARD_BIG_BANG_OR_CROSS_LANE_PATCH")
    rules=c.get("fallback_rules") or {}
    if rules.get("attempts_must_follow_declared_sequence") is not True:
        return _block("BLOCK_FALLBACK_SEQUENCE_GUARD_MISSING")
    if rules.get("missing_manual_readiness_evidence")!="FAIL_CLOSED":
        return _block("BLOCK_MANUAL_READINESS_FAIL_CLOSED_MISSING")
    return {"status":PASS,"code":"PASS_CARD_CONTRACT"}

def boundary_map(c:Mapping[str,Any],source:str,state:str)->dict:
    mappings=(c.get("boundary_mappings") or {}).get(source)
    if not isinstance(mappings,Mapping) or state not in mappings: return _block("BLOCK_CARD_BOUNDARY_MAPPING_MISSING",source=source,state=state)
    out=dict(mappings[state])
    if out.get("status")=="AMBIGUOUS" and out.get("action")!="FAIL_CLOSED": return _block("BLOCK_AMBIGUITY_NOT_FAIL_CLOSED")
    return {"status":PASS,"code":"PASS_CARD_BOUNDARY_MAPPING","canonical":out}

def fallback_decision(c:Mapping[str,Any],attempts:list[Mapping[str,Any]])->dict:
    contract=validate_contract(c)
    if contract.get("status")!=PASS: return contract
    if not isinstance(attempts,list): return _block("BLOCK_FALLBACK_ATTEMPTS_NOT_LIST")
    normalized=[]
    for index,item in enumerate(attempts):
        if not isinstance(item,Mapping): return _block("BLOCK_FALLBACK_ATTEMPT_SHAPE",index=index)
        alternative=item.get("alternative")
        if alternative not in EXPECTED_FALLBACK:
            return _block("BLOCK_UNKNOWN_FALLBACK_ALTERNATIVE",index=index,alternative=alternative)
        normalized.append(item)
    alternatives=[x.get("alternative") for x in normalized]
    if len(alternatives)!=len(set(alternatives)):
        return _block("BLOCK_DUPLICATE_FALLBACK_ATTEMPT")
    if alternatives != EXPECTED_FALLBACK[:len(alternatives)]:
        return _block("BLOCK_FALLBACK_SEQUENCE_VIOLATION",observed=alternatives)

    for index,alternative in enumerate(SAFE_FALLBACK):
        if index >= len(normalized):
            return {"status":PASS,"code":"TRY_SAFE_FALLBACK","alternative":alternative,"manual_allowed":False}
        item=normalized[index]
        if not _attempt_evidence_ok(item):
            return _block("BLOCK_FALLBACK_ATTEMPT_EVIDENCE_INCOMPLETE",alternative=alternative)
        result=item.get("result")
        if result=="PASS":
            return {"status":PASS,"code":"RESOLVED_WITH_GOVERNED_FALLBACK","alternative":alternative,"manual_allowed":False}
        if result!="FAIL":
            return _block("BLOCK_SAFE_FALLBACK_RESULT_INVALID",alternative=alternative,result=result)

    if len(normalized) < len(EXPECTED_FALLBACK):
        return _block("BLOCK_MANUAL_READINESS_EVIDENCE_MISSING",manual_allowed=False)
    manual=normalized[-1]
    if not _attempt_evidence_ok(manual):
        return _block("BLOCK_MANUAL_READINESS_EVIDENCE_INCOMPLETE",manual_allowed=False)
    if manual.get("result")!="READY":
        return _block("BLOCK_MANUAL_READINESS_RESULT_INVALID",result=manual.get("result"),manual_allowed=False)
    if manual.get("blocker_unresolved") is not False:
        return _block("BLOCK_MANUAL_BLOCKER_STATUS_NOT_CLEARED",manual_allowed=False)
    return {"status":PASS,"code":"MANUAL_REQUIRED","manual_allowed":True}
