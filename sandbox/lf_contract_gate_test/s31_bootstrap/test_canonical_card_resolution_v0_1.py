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
fail=lambda a:{"alternative":a,"result":"FAIL","typed_attempt":True,"reason":"not_applicable","evidence_ref":"receipt://x"}
r=m.fallback_decision(c,[fail("CONTRACT_SCHEMA"),fail("GENERIC_CAPABILITY"),fail("SAFE_COMPOSITION")]); assert r["code"]=="MANUAL_REQUIRED" and r["manual_allowed"] is True
bad=fail("CONTRACT_SCHEMA"); bad["evidence_ref"]=""; assert m.fallback_decision(c,[bad])["code"]=="BLOCK_FALLBACK_FAILURE_EVIDENCE_INCOMPLETE"
c2=json.loads(json.dumps(c)); c2["invariants"]["schema_invention_allowed"]=True; assert m.validate_contract(c2)["code"]=="BLOCK_SCHEMA_INVENTION_ALLOWED"
print("PASS_S31_CANONICAL_CARD_RESOLUTION_V0_1_SELFTEST=12/12")
