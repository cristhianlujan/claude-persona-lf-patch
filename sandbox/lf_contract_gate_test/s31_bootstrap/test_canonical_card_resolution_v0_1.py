#!/usr/bin/env python3
import importlib.util, json, sys
from pathlib import Path

here=Path(__file__).parent
spec=importlib.util.spec_from_file_location("cardv",here/"validate_canonical_card_resolution_v0_1.py")
m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
c=json.loads((here/"canonical_card_resolution_v0_1.json").read_text())
assert m.validate_contract(c)["status"]==m.PASS
assert m.boundary_map(c,"S26_SOURCE_FIRST_POLICY","EXACT")["canonical"]=={"status":"RESOLVED","mode":"EXACT"}
assert m.boundary_map(c,"S26_SOURCE_FIRST_POLICY","COMPOSED")["canonical"]["mode"]=="COMPOSED"
assert m.boundary_map(c,"S26_SOURCE_FIRST_POLICY","GENERIC_SAFE")["canonical"]["mode"]=="GENERIC_SAFE"
assert m.boundary_map(c,"S26_GOVERNANCE_GATE","COMPATIBLE")["canonical"]["mode"]=="COMPATIBLE"
assert m.boundary_map(c,"S26_GOVERNANCE_GATE","NONE")["canonical"]["status"]=="NO_DIRECT_CARD"
assert m.boundary_map(c,"S26_GOVERNANCE_GATE","AMBIGUOUS")["canonical"]["action"]=="FAIL_CLOSED"
assert m.boundary_map(c,"S26_RUNTIME_AUTHORITY","FALLBACK:NO_CARD_GOVERNED")["canonical"]["status"]=="NO_DIRECT_CARD"

r=m.fallback_decision(c,[]); assert r["alternative"]=="CONTRACT_SCHEMA" and r["manual_allowed"] is False

def attempt(a,result="FAIL",**extra):
    return {"alternative":a,"result":result,"typed_attempt":True,"reason":"governed_attempt","evidence_ref":"receipt://x",**extra}

# Full governed exhaustion requires an explicit manual-readiness record with no unresolved blocker.
manual=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","READY",blocker_unresolved=False)]
r=m.fallback_decision(c,manual); assert r["code"]=="MANUAL_REQUIRED" and r["manual_allowed"] is True

# Missing attempt evidence is fail-closed, including PASS attempts.
bad=attempt("CONTRACT_SCHEMA"); bad["evidence_ref"]=""
assert m.fallback_decision(c,[bad])["code"]=="BLOCK_FALLBACK_ATTEMPT_EVIDENCE_INCOMPLETE"
bad=attempt("CONTRACT_SCHEMA","PASS"); bad["reason"]=""
assert m.fallback_decision(c,[bad])["code"]=="BLOCK_FALLBACK_ATTEMPT_EVIDENCE_INCOMPLETE"

# Schema invention remains forbidden.
c2=json.loads(json.dumps(c)); c2["invariants"]["schema_invention_allowed"]=True
assert m.validate_contract(c2)["code"]=="BLOCK_SCHEMA_INVENTION_ALLOWED"

# Safe alternatives exhausted without explicit manual readiness evidence cannot authorize manual.
no_manual=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION")]
r=m.fallback_decision(c,no_manual); assert r["code"]=="BLOCK_MANUAL_READINESS_EVIDENCE_MISSING" and r["manual_allowed"] is False

# Duplicate/conflicting attempt identities are rejected instead of last-write-wins collapse.
dup=[attempt("CONTRACT_SCHEMA"),attempt("CONTRACT_SCHEMA","PASS")]
assert m.fallback_decision(c,dup)["code"]=="BLOCK_DUPLICATE_FALLBACK_ATTEMPT"

# Unknown alternatives cannot be ignored.
unknown=[{"alternative":"UNREGISTERED","result":"PASS","typed_attempt":True,"reason":"x","evidence_ref":"r"}]
assert m.fallback_decision(c,unknown)["code"]=="BLOCK_UNKNOWN_FALLBACK_ALTERNATIVE"

# Attempts must follow the declared governed sequence.
out_of_order=[attempt("GENERIC_CAPABILITY")]
assert m.fallback_decision(c,out_of_order)["code"]=="BLOCK_FALLBACK_SEQUENCE_VIOLATION"

# Manual readiness must explicitly prove blocker clearance and READY status.
blocked=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","READY",blocker_unresolved=True)]
assert m.fallback_decision(c,blocked)["code"]=="BLOCK_MANUAL_BLOCKER_STATUS_NOT_CLEARED"
missing_clear=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","READY")]
assert m.fallback_decision(c,missing_clear)["code"]=="BLOCK_MANUAL_BLOCKER_STATUS_NOT_CLEARED"
bad_manual_result=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","FAIL",blocker_unresolved=False)]
assert m.fallback_decision(c,bad_manual_result)["code"]=="BLOCK_MANUAL_READINESS_RESULT_INVALID"

# A governed PASS at each safe tier resolves immediately and never reaches manual.
assert m.fallback_decision(c,[attempt("CONTRACT_SCHEMA","PASS")])["code"]=="RESOLVED_WITH_GOVERNED_FALLBACK"
assert m.fallback_decision(c,[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY","PASS")])["alternative"]=="GENERIC_CAPABILITY"
assert m.fallback_decision(c,[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION","PASS")])["alternative"]=="SAFE_COMPOSITION"

print("PASS_S31_CANONICAL_CARD_RESOLUTION_V0_1_SELFTEST=19/19")
