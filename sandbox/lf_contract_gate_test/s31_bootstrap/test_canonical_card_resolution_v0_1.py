#!/usr/bin/env python3
import importlib.util, json, sys
from pathlib import Path

here=Path(__file__).parent
spec=importlib.util.spec_from_file_location("cardv",here/"validate_canonical_card_resolution_v0_1.py")
m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
c=json.loads((here/"canonical_card_resolution_v0_1.json").read_text())
cases=0

assert m.validate_contract(c)["status"]==m.PASS; cases+=1
assert m.boundary_map(c,"S26_SOURCE_FIRST_POLICY","EXACT")["canonical"]=={"status":"RESOLVED","mode":"EXACT"}; cases+=1
assert m.boundary_map(c,"S26_SOURCE_FIRST_POLICY","COMPOSED")["canonical"]["mode"]=="COMPOSED"; cases+=1
assert m.boundary_map(c,"S26_SOURCE_FIRST_POLICY","GENERIC_SAFE")["canonical"]["mode"]=="GENERIC_SAFE"; cases+=1
assert m.boundary_map(c,"S26_GOVERNANCE_GATE","COMPATIBLE")["canonical"]["mode"]=="COMPATIBLE"; cases+=1
assert m.boundary_map(c,"S26_GOVERNANCE_GATE","NONE")["canonical"]["status"]=="NO_DIRECT_CARD"; cases+=1
assert m.boundary_map(c,"S26_GOVERNANCE_GATE","AMBIGUOUS")["canonical"]["action"]=="FAIL_CLOSED"; cases+=1
assert m.boundary_map(c,"S26_RUNTIME_AUTHORITY","FALLBACK:NO_CARD_GOVERNED")["canonical"]["status"]=="NO_DIRECT_CARD"; cases+=1

r=m.fallback_decision(c,"NO_DIRECT_CARD",[]); assert r["alternative"]=="CONTRACT_SCHEMA" and r["manual_allowed"] is False; cases+=1

def attempt(a,result="FAIL",**extra):
    return {"alternative":a,"result":result,"typed_attempt":True,"reason":"governed_attempt","evidence_ref":"receipt://x",**extra}

manual=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","READY",blocker_unresolved=False)]
r=m.fallback_decision(c,"NO_DIRECT_CARD",manual); assert r["code"]=="MANUAL_REQUIRED" and r["manual_allowed"] is True; cases+=1

bad=attempt("CONTRACT_SCHEMA"); bad["evidence_ref"]=""
assert m.fallback_decision(c,"NO_DIRECT_CARD",[bad])["code"]=="BLOCK_FALLBACK_ATTEMPT_EVIDENCE_INCOMPLETE"; cases+=1
bad=attempt("CONTRACT_SCHEMA","PASS"); bad["reason"]=""
assert m.fallback_decision(c,"NO_DIRECT_CARD",[bad])["code"]=="BLOCK_FALLBACK_ATTEMPT_EVIDENCE_INCOMPLETE"; cases+=1

c2=json.loads(json.dumps(c)); c2["invariants"]["schema_invention_allowed"]=True
assert m.validate_contract(c2)["code"]=="BLOCK_SCHEMA_INVENTION_ALLOWED"; cases+=1

no_manual=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION")]
r=m.fallback_decision(c,"NO_DIRECT_CARD",no_manual); assert r["code"]=="BLOCK_MANUAL_READINESS_EVIDENCE_MISSING" and r["manual_allowed"] is False; cases+=1

dup=[attempt("CONTRACT_SCHEMA"),attempt("CONTRACT_SCHEMA","PASS")]
assert m.fallback_decision(c,"NO_DIRECT_CARD",dup)["code"]=="BLOCK_DUPLICATE_FALLBACK_ATTEMPT"; cases+=1

unknown=[{"alternative":"UNREGISTERED","result":"PASS","typed_attempt":True,"reason":"x","evidence_ref":"r"}]
assert m.fallback_decision(c,"NO_DIRECT_CARD",unknown)["code"]=="BLOCK_UNKNOWN_FALLBACK_ALTERNATIVE"; cases+=1

out_of_order=[attempt("GENERIC_CAPABILITY")]
assert m.fallback_decision(c,"NO_DIRECT_CARD",out_of_order)["code"]=="BLOCK_FALLBACK_SEQUENCE_VIOLATION"; cases+=1

blocked=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","READY",blocker_unresolved=True)]
assert m.fallback_decision(c,"NO_DIRECT_CARD",blocked)["code"]=="BLOCK_MANUAL_BLOCKER_STATUS_NOT_CLEARED"; cases+=1
missing_clear=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","READY")]
assert m.fallback_decision(c,"NO_DIRECT_CARD",missing_clear)["code"]=="BLOCK_MANUAL_BLOCKER_STATUS_NOT_CLEARED"; cases+=1
bad_manual_result=[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION"),attempt("MANUAL_REQUIRED","FAIL",blocker_unresolved=False)]
assert m.fallback_decision(c,"NO_DIRECT_CARD",bad_manual_result)["code"]=="BLOCK_MANUAL_READINESS_RESULT_INVALID"; cases+=1

assert m.fallback_decision(c,"NO_DIRECT_CARD",[attempt("CONTRACT_SCHEMA","PASS")])["code"]=="RESOLVED_WITH_GOVERNED_FALLBACK"; cases+=1
assert m.fallback_decision(c,"NO_DIRECT_CARD",[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY","PASS")])["alternative"]=="GENERIC_CAPABILITY"; cases+=1
assert m.fallback_decision(c,"NO_DIRECT_CARD",[attempt("CONTRACT_SCHEMA"),attempt("GENERIC_CAPABILITY"),attempt("SAFE_COMPOSITION","PASS")])["alternative"]=="SAFE_COMPOSITION"; cases+=1

# Independent review regression: fallback is executable only from canonical NO_DIRECT_CARD.
for status in ["RESOLVED","AMBIGUOUS","BLOCKED"]:
    r=m.fallback_decision(c,status,[])
    assert r["code"]=="BLOCK_FALLBACK_ENTRY_STATUS_INVALID" and r["required_status"]=="NO_DIRECT_CARD", r
    cases+=1
r=m.fallback_decision(c,"UNKNOWN",[])
assert r["code"]=="BLOCK_FALLBACK_ENTRY_STATUS_UNKNOWN", r; cases+=1

# The declared entry rule itself cannot drift away from NO_DIRECT_CARD.
c3=json.loads(json.dumps(c)); c3["fallback_rules"]["start_only_when_status"]="RESOLVED"
assert m.validate_contract(c3)["code"]=="BLOCK_FALLBACK_ENTRY_POLICY_DRIFT"; cases+=1

print(f"PASS_S31_CANONICAL_CARD_RESOLUTION_V0_1_SELFTEST={cases}/{cases}")
