import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "validators"))
from terminality_gate_v1 import decide_terminal
CL = ["DIRECT","DECLARED","ANALOGY","RELATED","HISTORY"]
full = [{"datum":"X","classes":[{"class":c,"source":"s","locator":"l","result":"NO_SOURCE_ACCESSIBLE"} for c in CL]}]
LEVELS=["N1","N2","N3","N4","N5"]
full[0]["levels"]=[{"level":v,"evidence_id":"EV-"+v,"locator":"source://"+v,
                     "result":"NO_EVIDENCE"} for v in LEVELS]
def trusted_levels(datum, level, locator, evidence_id):
    if datum=="X" and level in LEVELS and locator=="source://"+level and evidence_id=="EV-"+level:
        return {"verified":True,"datum":datum,"level":level,"source_locator":locator,
                "evidence_id":evidence_id,"result":"NO_EVIDENCE"}
    return None

part = [{"datum":"X","classes":[{"class":c,"source":"s","locator":"l","result":"r"} for c in CL[:3]]}]
item = [{"code":"X","status":"GAP"}]
checks = {
 "EXHAUSTED_SEARCH_REPORTED": decide_terminal({"material_items":item,"search_records":full},trusted_level_reader=trusted_levels).get("evidence_state")=="EXPLORED_NO_EVIDENCE_FOUND",
 "EXHAUSTED_LISTS_WHAT_WAS_SEARCHED": len(decide_terminal({"material_items":item,"search_records":full},trusted_level_reader=trusted_levels).get("explored",[]))==1,
 "PARTIAL_SEARCH_IS_INCOMPLETE": decide_terminal({"material_items":item,"search_records":part}).get("evidence_state")=="SEARCH_INCOMPLETE",
 "NO_RECORD_IS_INCOMPLETE": decide_terminal({"material_items":item}).get("evidence_state")=="SEARCH_INCOMPLETE",
 "STATUS_VALUE_UNCHANGED": decide_terminal({"material_items":item,"search_records":full},trusted_level_reader=trusted_levels)["status"]=="NEEDS_MORE_EVIDENCE",
 "CLOSED_CASE_UNAFFECTED": decide_terminal({"repair_required":False,"no_repair_positive_evidence":True})=={"status":"NO_REPAIR_REQUIRED","reasons":[]},
 "PIPELINE_BLOCK_UNAFFECTED": decide_terminal({"pipeline_blocking_codes":["Z"]})["status"]=="BLOCK_PIPELINE",
}
found = [{"datum": "X", "classes": [{**r, "result": "ROWS"} if r["class"] == "DIRECT" else r for r in full[0]["classes"]]}]
wrong_datum = [{"datum": "OTHER", "classes": full[0]["classes"]}]
duplicate = [{"datum": "X", "classes": [full[0]["classes"][0]] * 5}]
two_open = item + [{"code": "Y", "status": "GAP"}]
checks.update({
 "FOUND_ROWS_CANNOT_CLAIM_ABSENCE": decide_terminal({"material_items": item, "search_records": found}).get("evidence_state") == "SEARCH_INCOMPLETE",
 "OTHER_DATUM_CANNOT_CLOSE": decide_terminal({"material_items": item, "search_records": wrong_datum}).get("evidence_state") == "SEARCH_INCOMPLETE",
 "DUPLICATE_CLASS_CANNOT_CLOSE": decide_terminal({"material_items": item, "search_records": duplicate}).get("evidence_state") == "SEARCH_INCOMPLETE",
 "TWO_DATUMS_REQUIRE_TWO_RECORDS": decide_terminal({"material_items": two_open, "search_records": full}).get("evidence_state") == "SEARCH_INCOMPLETE",
})


checks.update({
 "NO_TRUSTED_N6_READER_IS_INCOMPLETE":
    decide_terminal({"material_items":item,"search_records":full}).get("evidence_state")=="SEARCH_INCOMPLETE",
 "N5_OMITTED_CANNOT_CLOSE":
    decide_terminal({"material_items":item,"search_records":[dict(full[0],levels=full[0]["levels"][:4])]},
                    trusted_level_reader=trusted_levels).get("evidence_state")=="SEARCH_INCOMPLETE",
 "N4_READBACK_MISSING_CANNOT_CLOSE":
    decide_terminal({"material_items":item,"search_records":full},
                    trusted_level_reader=lambda datum,level,locator,eid:
                    None if level=="N4" else trusted_levels(datum,level,locator,eid)).get("evidence_state")=="SEARCH_INCOMPLETE",
 "N5_FALSE_UNAVAILABLE_CANNOT_CLOSE":
    decide_terminal({"material_items":item,"search_records":[dict(full[0],levels=[
                    dict(x,result="NO_SOURCE_ACCESSIBLE",error_detail="ACCESS_DENIED")
                    if x["level"]=="N5" else x for x in full[0]["levels"]])]},
                    trusted_level_reader=trusted_levels).get("evidence_state")=="SEARCH_INCOMPLETE",
 "N6_INDEPENDENT_SOURCE_MISMATCH_REJECTED":
    decide_terminal({"material_items":item,"search_records":full},
                    trusted_level_reader=lambda datum,level,locator,eid:
                    dict(trusted_levels(datum,level,locator,eid),source_locator="forged://other")
                    if level=="N3" else trusted_levels(datum,level,locator,eid)).get("evidence_state")=="SEARCH_INCOMPLETE",
})

from producer_depth import _catalog_receipt_errors
import copy, hashlib, json
def _error(code, path): return {"code": code, "path": path}
def _receipt(level, source, count, rows):
    d = {"source":source,"source_kind":"VIEW" if level=="N1" else "BASE_TABLE","query":f"SELECT codigo_activo FROM public.{source} WHERE codigo_activo = $1","result_kind":"ROWS" if count else "EMPTY","row_count":count,"sample_records":rows,"observed_at":"2026-10-30T12:00:00Z","snapshot":"SOURCE_FIRST_READBACK"}
    ev = {"source_locator":d["query"],"digest":"sha256:"+hashlib.sha256(json.dumps(d,sort_keys=True,ensure_ascii=False,separators=(",",":")).encode()).hexdigest()}
    return {"level":level,"datum_id":"U-1","evidence_id":"EV-"+level,"readback":d},ev
q1,e1=_receipt("N1","v_lf_fuente_operativa_busqueda",1,[{"codigo_activo":"A"}])
q2,e2=_receipt("N2","lf_activos",1,[{"codigo_activo":"A"}])
good={"catalog_queries":[q1,q2]}
ev={"EV-N1":e1,"EV-N2":e2}
def _codes(c,e=ev): return {x["code"] for x in _catalog_receipt_errors(c,e,"U-1","$.cascade",_error)}
checks.update({
 "N1_N2_RECEIPT_VERIFIED":not _codes(good),
 "MISSING_N2_REJECTED":"GAP_CATALOG_N1_N2_MISSING" in _codes({"catalog_queries":[q1]}),
 "FALSE_VALUE_REJECTED":"GAP_CATALOG_READBACK_DIGEST_MISMATCH" in _codes({"catalog_queries":[dict(q1,readback=dict(q1["readback"],sample_records=[{"codigo_activo":"FALSE"}])),q2]}),
 "OTHER_DATUM_REJECTED":"GAP_CATALOG_DATUM_MISMATCH" in _codes({"catalog_queries":[dict(q1,datum_id="U-OTHER"),q2]}),
 "EVIDENCE_REUSE_REJECTED":"GAP_CATALOG_EVIDENCE_REUSED" in _codes({"catalog_queries":[q1,dict(q2,evidence_id="EV-N1")]}),
 "FALSE_EMPTY_REJECTED":"GAP_CATALOG_RESULT_INCONSISTENT" in _codes({"catalog_queries":[dict(q1,readback=dict(q1["readback"],result_kind="EMPTY")),q2]}),
 "MISSING_PROOF_REJECTED":"GAP_CATALOG_MANIFEST_EVIDENCE_MISSING" in _codes(good,{"EV-N2":e2}),
 "NON_SELECT_REJECTED":"GAP_CATALOG_NON_SELECT_QUERY" in _codes({"catalog_queries":[dict(q1,readback=dict(q1["readback"],query="DELETE FROM lf_activos")),q2]}),
})


from producer_depth import _level_trace_errors
def _trace(level, source, locator, revision, kind="NO_EVIDENCE", error_detail=None):
    digest="sha256:"+("a" if level=="N3" else "b" if level=="N4" else "c")*64
    record={"level":level,"datum_id":"U-1","source":source,"locator":locator,
            "evidence_id":"EV-"+level,"result_kind":kind,
            "source_revision":revision,"observed_at":"2026-10-30T19:00:00Z",
            "digest":digest}
    if error_detail is not None: record["error_detail"]=error_detail
    return record,{"source_locator":locator,"digest":digest}
n3,r3=_trace("N3","pg_description","SELECT obj_description(oid) FROM pg_class","DB_SNAPSHOT_20261030")
n4,r4=_trace("N4","GITHUB","github://repo@"+("a"*40)+"/path","a"*40)
n5,r5=_trace("N5","PROJECT_MEMORY","project://memory/owner","PROJECT_SNAPSHOT",kind="NO_SOURCE_ACCESSIBLE",error_detail="NO_AUTHORIZED_PROJECT_DOCUMENT_READER")
levels=[n3,n4,n5]
level_manifest={"EV-N3":r3,"EV-N4":r4,"EV-N5":r5}
def _level_codes(ls, proofs=level_manifest):
    return {v["code"] for v in _level_trace_errors({"level_trace":ls},proofs,"U-1","$.cascade",_error)}
checks.update({
 "N3_N4_N5_LEVEL_TRACE_ACCEPTED":not _level_codes(levels),
 "N5_SKIPPED_REJECTED":"GAP_LEVEL_TRACE_ORDER_OR_COVERAGE" in _level_codes(levels[:2]),
 "N3_SKIPPED_REJECTED":"GAP_LEVEL_TRACE_ORDER_OR_COVERAGE" in _level_codes(levels[1:]),
 "N4_UNPINNED_REJECTED":"GAP_LEVEL_TRACE_GITHUB_REVISION_UNPINNED" in _level_codes([n3,dict(n4,source_revision="main"),n5]),
 "N5_INACCESSIBLE_REQUIRES_ERROR":"GAP_LEVEL_TRACE_ACCESS_ERROR_MISSING" in _level_codes([n3,n4,dict(n5,error_detail="")]),
 "N5_FAKE_DIGEST_REJECTED":"GAP_LEVEL_TRACE_PROVENANCE_MISMATCH" in _level_codes([n3,n4,dict(n5,digest="sha256:"+("d"*64))]),
 "N4_MISSING_EXTERNAL_MANIFEST_REJECTED":"GAP_LEVEL_TRACE_EVIDENCE_MISSING" in _level_codes(levels,{"EV-N3":r3,"EV-N5":r5}),
 "WRONG_LEVEL_DATUM_REJECTED":"GAP_LEVEL_TRACE_DATUM_MISMATCH" in _level_codes([n3,dict(n4,datum_id="OTHER"),n5]),
})


# Regression: the previous GPT-native WEB-001 partial N1/N2 probe must NOT
# qualify as an exhausted N1-N6 search after this change.
import runpy
packet_path=pathlib.Path(__file__).resolve().parents[3]/"docs/profile_updater/handoffs/WEB001_GPT_NATIVE_CURRENT_CHAT_N1N2_READBACK_20261030.json"
packet=json.loads(packet_path.read_text(encoding="utf-8"))
from runtime_validate import validate as validate_runtime
historical_result=validate_runtime(packet["raw_output"],packet["evidence_manifest"])
historical_codes={r.get("code") for r in historical_result.get("errors",[]) if isinstance(r,dict)}
checks["WEB001_PARTIAL_N1_N2_CANNOT_CLOSE_N6"]="GAP_LEVEL_TRACE_REQUIRED" in historical_codes

for k,v in checks.items(): print("ok  " if v else "FAIL", k)
print(f"EXHAUSTED_SEARCH_CASES={sum(checks.values())}/{len(checks)}")
sys.exit(0 if all(checks.values()) else 1)