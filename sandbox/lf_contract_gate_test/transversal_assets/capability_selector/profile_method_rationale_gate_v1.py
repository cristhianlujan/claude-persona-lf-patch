"""Evidence-grounded rationale boundary for model explanation.

A correct typed decision does not imply a supported narrative. Requires explicit
claim-level provenance and an external semantic verifier; no automatic authority.
"""
from __future__ import annotations
from typing import Any,Callable

def verify_rationale(
    answer:dict[str,Any],
    *,
    verify_source:Callable[[str],bool]|None,
    verify_claim:Callable[[dict[str,Any],dict[str,Any]],bool]|None,
)->dict[str,Any]:
    fail={"schema":"PROFILE_METHOD_RATIONALE_BOUNDARY_V1","status":"BLOCKED",
          "publication_authorized":False,"cutover_eligible":False}
    if not isinstance(answer,dict) or answer.get("causality_proven") is not False:
        return {**fail,"reason":"INVALID_ANSWER_OR_CAUSALITY_OVERCLAIM"}
    claims=answer.get("reason_claims")
    if not isinstance(claims,list) or not claims:
        return {**fail,"reason":"CLAIM_LEVEL_EVIDENCE_REQUIRED"}
    if not callable(verify_source) or not callable(verify_claim):
        return {**fail,"reason":"INDEPENDENT_SOURCE_AND_SEMANTIC_VERIFIERS_REQUIRED"}
    for i,claim in enumerate(claims):
        if not isinstance(claim,dict) or claim.get("type") not in ("OBSERVATION","HYPOTHESIS","INFERENCE"):
            return {**fail,"reason":"CLAIM_SCHEMA_INVALID","claim_index":i}
        refs=claim.get("evidence_refs")
        if not isinstance(refs,list) or not refs or any(not isinstance(x,str) or not x for x in refs):
            return {**fail,"reason":"CLAIM_EVIDENCE_REQUIRED","claim_index":i}
        verified=[]
        for ref in refs:
            try: approved=verify_source(ref) is True
            except Exception: approved=False
            verified.append(approved)
        if not all(verified):
            return {**fail,"reason":"CLAIM_USES_UNVERIFIED_SOURCE","claim_index":i}
        try:semantic=verify_claim(claim,answer) is True
        except Exception:semantic=False
        if not semantic:
            return {**fail,"reason":"INDEPENDENT_SEMANTIC_JUDGE_DID_NOT_VERIFY","claim_index":i}
    return {**fail,"status":"TEST_ONLY_GROUNDED_RATIONALE",
            "reason":"PROVENANCE_AND_SEMANTICS_VERIFIED_TEST_ONLY",
            "claim_count":len(claims)}
