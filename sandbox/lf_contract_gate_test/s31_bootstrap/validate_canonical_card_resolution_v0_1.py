#!/usr/bin/env python3
from __future__ import annotations
from typing import Any, Mapping

PASS="PASS"; BLOCKED="BLOCKED"
EXPECTED_STATUSES=["RESOLVED","NO_DIRECT_CARD","AMBIGUOUS","BLOCKED"]
EXPECTED_MODES=["EXACT","COMPATIBLE","COMPOSED","GENERIC_SAFE"]
EXPECTED_FALLBACK=["CONTRACT_SCHEMA","GENERIC_CAPABILITY","SAFE_COMPOSITION","MANUAL_REQUIRED"]

def _block(code:str,**extra:Any)->dict: return {"status":BLOCKED,"code":code,**extra}

def validate_contract(c:Mapping[str,Any])->dict:
    if c.get("contract_version")!="S31_CANONICAL_CARD_RESOLUTION_V0_1": return _block("BLOCK_CARD_CONTRACT_VERSION")
    if c.get("resolution_statuses")!=EXPECTED_STATUSES: return _block("BLOCK_CARD_STATUS_VOCABULARY")
    if c.get("resolution_modes")!=EXPECTED_MODES: return _block("BLOCK_CARD_MODE_VOCABULARY")
    if c.get("fallback_sequence")!=EXPECTED_FALLBACK: return _block("BLOCK_CARD_FALLBACK_ORDER")
    inv=c.get("invariants") or {}
    required_true=("no_direct_card_is_not_manual","ambiguous_fail_closed","source_authority_precedence","manual_requires_all_safe_alternatives_exhausted","typed_failure_evidence_required","cards_define_how_not_what")
    if any(inv.get(k) is not True for k in required_true): return _block("BLOCK_CARD_INVARIANT_MISSING")
    if inv.get("schema_invention_allowed") is not False: return _block("BLOCK_SCHEMA_INVENTION_ALLOWED")
    compat=c.get("compatibility_policy") or {}
    if compat.get("big_bang_migration") is not False or compat.get("independent_s26_patch_required") is not False:
        return _block("BLOCK_CARD_BIG_BANG_OR_CROSS_LANE_PATCH")
    return {"status":PASS,"code":"PASS_CARD_CONTRACT"}

def boundary_map(c:Mapping[str,Any],source:str,state:str)->dict:
    mappings=(c.get("boundary_mappings") or {}).get(source)
    if not isinstance(mappings,Mapping) or state not in mappings: return _block("BLOCK_CARD_BOUNDARY_MAPPING_MISSING",source=source,state=state)
    out=dict(mappings[state])
    if out.get("status")=="AMBIGUOUS" and out.get("action")!="FAIL_CLOSED": return _block("BLOCK_AMBIGUITY_NOT_FAIL_CLOSED")
    return {"status":PASS,"code":"PASS_CARD_BOUNDARY_MAPPING","canonical":out}

def fallback_decision(c:Mapping[str,Any],attempts:list[Mapping[str,Any]])->dict:
    if validate_contract(c).get("status")!=PASS: return validate_contract(c)
    by={x.get("alternative"):x for x in attempts if isinstance(x,Mapping)}
    for alternative in EXPECTED_FALLBACK[:-1]:
        item=by.get(alternative)
        if item is None:
            return {"status":PASS,"code":"TRY_SAFE_FALLBACK","alternative":alternative,"manual_allowed":False}
        if item.get("result")=="PASS":
            return {"status":PASS,"code":"RESOLVED_WITH_GOVERNED_FALLBACK","alternative":alternative,"manual_allowed":False}
        if item.get("result")!="FAIL" or item.get("typed_attempt") is not True or not item.get("reason") or not item.get("evidence_ref"):
            return _block("BLOCK_FALLBACK_FAILURE_EVIDENCE_INCOMPLETE",alternative=alternative)
    manual=by.get("MANUAL_REQUIRED")
    if manual is None:
        return {"status":PASS,"code":"MANUAL_REQUIRED","manual_allowed":True}
    if manual.get("blocker_unresolved") is True:
        return _block("BLOCK_MANUAL_WITH_UNRESOLVED_BLOCKER")
    return {"status":PASS,"code":"MANUAL_REQUIRED","manual_allowed":True}
