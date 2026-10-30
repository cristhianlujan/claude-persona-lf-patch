import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "validators"))
from terminality_gate_v1 import decide_terminal
CL = ["DIRECT","DECLARED","ANALOGY","RELATED","HISTORY"]
full = [{"datum":"X","classes":[{"class":c,"source":"s","locator":"l","result":"NO_SOURCE_ACCESSIBLE"} for c in CL]}]
part = [{"datum":"X","classes":[{"class":c,"source":"s","locator":"l","result":"r"} for c in CL[:3]]}]
item = [{"code":"X","status":"GAP"}]
checks = {
 "EXHAUSTED_SEARCH_REPORTED": decide_terminal({"material_items":item,"search_records":full}).get("evidence_state")=="EXPLORED_NO_EVIDENCE_FOUND",
 "EXHAUSTED_LISTS_WHAT_WAS_SEARCHED": len(decide_terminal({"material_items":item,"search_records":full}).get("explored",[]))==1,
 "PARTIAL_SEARCH_IS_INCOMPLETE": decide_terminal({"material_items":item,"search_records":part}).get("evidence_state")=="SEARCH_INCOMPLETE",
 "NO_RECORD_IS_INCOMPLETE": decide_terminal({"material_items":item}).get("evidence_state")=="SEARCH_INCOMPLETE",
 "STATUS_VALUE_UNCHANGED": decide_terminal({"material_items":item,"search_records":full})["status"]=="NEEDS_MORE_EVIDENCE",
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

for k,v in checks.items(): print("ok  " if v else "FAIL", k)
print(f"EXHAUSTED_SEARCH_CASES={sum(checks.values())}/{len(checks)}")
sys.exit(0 if all(checks.values()) else 1)