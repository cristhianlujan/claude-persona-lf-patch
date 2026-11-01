#!/usr/bin/env python3
"""N1/N2 quality-guard regression. Isolated; no external system writes."""
import copy, hashlib, json, runpy, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
guard = runpy.run_path(str(ROOT/"validators"/"validate_semantic_judge_result.py"))["_validate_n1_n2_audit"]
def data(level):
    name = "example_view" if level=="N1" else "example_table"
    d = {"source":name,"source_kind":"VIEW" if level=="N1" else "BASE_TABLE","query":"SELECT x FROM public."+name,"result_kind":"ROWS","row_count":1,"sample_records":[{"x":0}],"observed_at":"2026-10-30T12:00:00Z","snapshot":"S1"}
    eid="EV-"+level
    ev={"evidence_id":eid,"state":"CURRENT","source_locator":d["query"],"digest":"sha256:"+hashlib.sha256(json.dumps(d,sort_keys=True,ensure_ascii=False,separators=(",",":")).encode()).hexdigest()}
    q={"level":level,"datum_id":"U","evidence_id":eid,"readback":d}
    a={"level":level,"datum_id":"U","evidence_id":eid,"source_locator":d["query"],"result_kind":"ROWS","row_count":1,"sample_records":[{"x":0}],"comparison":"MATCH","independent_source_ref":"readback://"+eid,"independent_observed_at":"2026-10-30T12:01:00Z"}
    return q,ev,a
q1,p1,a1=data("N1");q2,p2,a2=data("N2")
c={"profile_pack_id":"SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6","current_uncertainties":[{"impact":"DESIGN_BLOCKING","uncertainty_id":"U","cascade":{"catalog_queries":[q1,q2]}}]}
p={"evidence":[p1,p2]}
j={"verdict":"PASS_INDEPENDENT_SEMANTIC","n1_n2_verdict":"PASS","n1_n2_audit":[a1,a2],"candidate_sha256":"a"*64}
t={"EV-N1":{**a1,"verified":True,"source_digest":p1["digest"],"candidate_sha256":j["candidate_sha256"]},"EV-N2":{**a2,"verified":True,"source_digest":p2["digest"],"candidate_sha256":j["candidate_sha256"]}}
def trusted(eid,query,datum,level): return t.get(eid)
def codes(jj=j,cc=c,pp=p,reader=trusted): return set(guard(jj,cc,pp,reader))
tests={"valid_pair":not codes()}
x=copy.deepcopy(j);x.pop("n1_n2_audit");tests["missing_judge_records"]="N1_N2_AUDIT_MISSING" in codes(jj=x)
x=copy.deepcopy(j);x["n1_n2_audit"]=[a1];tests["missing_N2"]="N1_N2_AUDIT_INCOMPLETE" in codes(jj=x)
x=copy.deepcopy(j);x["n1_n2_audit"][0]["sample_records"]=[{"x":3}];tests["altered_values"]="N1_N2_AUDIT_VALUE_MISMATCH" in codes(jj=x)
x=copy.deepcopy(j);x["n1_n2_audit"][0]["datum_id"]="OTHER";tests["wrong_datum"]="N1_N2_AUDIT_DUPLICATE_OR_UNEXPECTED" in codes(jj=x)
x=copy.deepcopy(j);x["n1_n2_verdict"]="UNVERIFIABLE";tests["false_pass"]="N1_N2_PASS_NOT_ISSUED" in codes(jj=x)
x=copy.deepcopy(c);x["current_uncertainties"][0]["cascade"]={};tests["omitted_queries"]="N1_N2_REQUIRED_QUERIES_MISSING" in codes(cc=x)
x=copy.deepcopy(c);x["current_uncertainties"][0]["cascade"]["catalog_queries"]=[q1];tests["omitted_level"]="N1_N2_QUALITY_LEVEL_MISSING" in codes(cc=x)
x=copy.deepcopy(p);x["evidence"][0]["digest"]="sha256:wrong";tests["wrong_sha"]="N1_N2_SOURCE_DIGEST_MISMATCH" in codes(pp=x)
x=copy.deepcopy(j);x["n1_n2_audit"][0]["independent_source_ref"]="";tests["no_independent_readback"]="N1_N2_INDEPENDENT_READBACK_NOT_PROVEN" in codes(jj=x)
tests["missing_trusted_reader"]="N1_N2_TRUSTED_READER_NOT_WIRED" in codes(reader=None)
evolved=copy.deepcopy(c);evolved["profile_pack_id"]="SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_7"
tests["evolved_profile_still_requires_trusted_reader"]="N1_N2_TRUSTED_READER_NOT_WIRED" in codes(cc=evolved,reader=None)
tests["fabricated_independent_ref"]="N1_N2_INDEPENDENT_READBACK_NOT_PROVEN" in codes(reader=lambda *_: {"verified":True})
bad=copy.deepcopy(t);bad["EV-N2"]["sample_records"]=[{"x":99}]
tests["tampered_backend_values"]="N1_N2_INDEPENDENT_READBACK_NOT_PROVEN" in codes(reader=lambda eid,*_:bad.get(eid))

# Integration boundary: the quality verifier and materializer must propagate
# an externally injected trusted reader, never silently invent one.
import importlib.util
def _load_module(name, path):
    spec=importlib.util.spec_from_file_location(name, str(path))
    mod=importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod
quality=_load_module("srcr_quality_wire_test", ROOT/"validators"/"validate_quality_receipt.py")
materializer=_load_module("srcr_materialize_wire_test", ROOT/"validators"/"materialize_quality_receipt.py")
reader_marker=object()
quality_seen=[]
orig_quality_evaluate=quality.semantic_validator.evaluate
def _quality_probe(payload, **kwargs):
    quality_seen.append(kwargs.get("trusted_reader"))
    return {"status":"FAIL","blocking_codes":["TEST_CONTROLLED_REJECTION"]}
quality.semantic_validator.evaluate=_quality_probe
try:
    quality.validate_quality_receipt({}, {}, {}, {}, trusted_reader=reader_marker)
finally:
    quality.semantic_validator.evaluate=orig_quality_evaluate
tests["quality_reader_forwarded"]=quality_seen==[reader_marker]

materializer_seen=[]
orig_materializer_evaluate=materializer.semantic_validator.evaluate
def _materializer_probe(payload, **kwargs):
    materializer_seen.append(kwargs.get("trusted_reader"))
    return {"status":"FAIL","blocking_codes":["TEST_CONTROLLED_REJECTION"]}
materializer.semantic_validator.evaluate=_materializer_probe
try:
    try:
        materializer.materialize_quality_receipt(
            {}, {}, {}, candidate_revision="test", semantic_execution_receipt_ref="test",
            issued_at="2026-10-30T00:00:00Z",trusted_reader=reader_marker
        )
    except materializer.QualityReceiptMaterializationError as exc:
        tests["materializer_reader_forwarded"]=materializer_seen==[reader_marker] and "SEMANTIC_RESULT_INVALID" in str(exc)
    else:
        tests["materializer_reader_forwarded"]=False
finally:
    materializer.semantic_validator.evaluate=orig_materializer_evaluate

for k,v in tests.items(): print(("PASS " if v else "FAIL ")+k)
print(f"N1_N2_QUALITY_CASES={sum(tests.values())}/{len(tests)}")
sys.exit(0 if all(tests.values()) else 1)