"""Governed-input adapter: method receipt -> typed action proposal, fail-closed.

Does not promote, deploy, or prove causal correctness. Independent verification
callbacks and exact source matching are required from the caller.
"""
from __future__ import annotations
import hashlib,json
from typing import Any, Callable


def _sha(value: Any) -> str:
    return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()


def _blocked(reason: str) -> dict[str, Any]:
    return {"schema":"PROFILE_METHOD_RESULT_CONSUMPTION_V1",
            "status":"BLOCKED","reason":reason,"recommended_action":None,
            "causality_proven":False,"authority_write":False,
            "cutover_eligible":False}


def consume_hypothesis_method_result(
    receipt: dict[str, Any],
    method_result: dict[str, Any],
    *,
    verify_receipt: Callable[[dict[str, Any]], bool] | None,
    verify_method_result: Callable[[dict[str, Any]], bool] | None,
) -> dict[str, Any]:
    if not isinstance(receipt,dict) or not isinstance(method_result,dict):
        return _blocked("RECEIPT_OR_OUTPUT_MISSING")
    if not callable(verify_receipt) or not callable(verify_method_result):
        return _blocked("INDEPENDENT_VERIFIER_MISSING")
    try:
        verified=verify_receipt(receipt) is True and verify_method_result(method_result) is True
    except Exception:
        verified=False
    if not verified:
        return _blocked("INDEPENDENT_EVIDENCE_VERIFICATION_FAILED")
    if receipt.get("method_id")!="CAUSAL_ANALYSIS":
        return _blocked("METHOD_ID_NOT_SUPPORTED")
    if receipt.get("result_state")!="EXECUTED_VERIFIED":
        return _blocked("METHOD_EXECUTION_NOT_VERIFIED")
    if receipt.get("scope")!="TEST_NON_AUTHORITY":
        return _blocked("SCOPE_NOT_SUPPORTED")
    if receipt.get("receipt_sha256")!=_sha({k:v for k,v in receipt.items() if k!="receipt_sha256"}):
        return _blocked("RECEIPT_HASH_MISMATCH")
    if method_result.get("schema") not in {"CAUSAL_HYPOTHESIS_FALSIFICATION_V1","CAUSAL_HYPOTHESIS_FALSIFICATION_V2"}:
        return _blocked("METHOD_OUTPUT_SCHEMA_UNSUPPORTED")
    if method_result.get("status")!="EVALUATED" or method_result.get("causal_proof") is not False:
        return _blocked("METHOD_OUTPUT_INVALID_OR_CAUSALITY_OVERCLAIMED")
    rows=method_result.get("hypotheses")
    if not isinstance(rows,list) or not 2<=len(rows)<=8:
        return _blocked("HYPOTHESIS_ROWS_INVALID")
    ids=set()
    for x in rows:
        if not isinstance(x,dict) or x.get("state") not in ("FALSIFIED","NOT_FALSIFIED","UNTESTED"):
            return _blocked("HYPOTHESIS_STATE_INVALID")
        mid=x.get("hypothesis_id")
        if not isinstance(mid,str) or not mid or mid in ids:
            return _blocked("HYPOTHESIS_ID_INVALID")
        ids.add(mid)
        if not isinstance(x.get("falsified_by"),list) or not isinstance(x.get("unverified_prediction_probes"),list):
            return _blocked("HYPOTHESIS_PROVENANCE_FIELDS_MISSING")
        if x["state"]=="FALSIFIED" and not x["falsified_by"]:
            return _blocked("FALSIFICATION_HAS_NO_COUNTEREVIDENCE")
        if x["state"]!="FALSIFIED" and x["falsified_by"]:
            return _blocked("NONFALSIFIED_CONTRADICTORY_RECEIPT")
    survivors=[x for x in rows if x["state"]!="FALSIFIED"]
    if len(survivors)!=1 or survivors[0]["unverified_prediction_probes"] or survivors[0]["state"]=="UNTESTED":
        action="COLLECT_MORE_EVIDENCE"
    else:
        action="INVESTIGATE_"+survivors[0]["hypothesis_id"]
    return {
        "schema":"PROFILE_METHOD_RESULT_CONSUMPTION_V1",
        "status":"TEST_ONLY_RECONCILED",
        "recommended_action":action,
        "falsified_hypotheses":sorted(x["hypothesis_id"] for x in rows if x["state"]=="FALSIFIED"),
        "method_receipt_sha256":receipt["receipt_sha256"],
        "counterevidence_probes":sorted(set(p for x in rows for p in x["falsified_by"])),
        "unverified_probes":sorted(set(p for x in survivors for p in x["unverified_prediction_probes"])),
        "causality_proven":False,
        "authority_write":False,
        "cutover_eligible":False,
        "is_model_reasoning_improvement":False,
    }
