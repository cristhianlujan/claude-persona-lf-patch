"""PG-04_C5: bounded per-SOLUTION Definition of Done (candidate only).

Records explicit, scoped standards and validation/test plans; does not execute them
or assert that caller-supplied standards are authentic/current.
"""
import hashlib
import json
import re

class DoDBlocked(ValueError):
    pass

def _fail(code):
    raise DoDBlocked(code)

def _digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()).hexdigest()

def _ids(rows):
    return isinstance(rows,list) and len(rows)==len(set(rows)) and all(isinstance(x,str) and bool(x.strip()) for x in rows)

def prepare_dod(*,partition,standards_catalog_version,standards,solution_plans):
    """Freeze planned checks for every solution and material acceptance signal."""
    if not isinstance(partition,dict) or partition.get("schema_version")!="PG04_SEMANTIC_PARTITION_CANDIDATE_V1" or partition.get("status")!="CANDIDATE_NOT_ADMITTED" or partition.get("production_authority") is not False or partition.get("handoff_allowed") is not False:
        _fail("PARTITION_NOT_UNTRUSTED_CANDIDATE")
    sha=partition.get("candidate_sha256")
    if not isinstance(sha,str) or not re.fullmatch(r"[0-9a-f]{64}",sha):
        _fail("PARTITION_SHA_INVALID")
    if sha != _digest({k:v for k,v in partition.items() if k!="candidate_sha256"}):
        _fail("PARTITION_SHA_DRIFT")
    if not isinstance(standards_catalog_version,str) or not standards_catalog_version.strip():
        _fail("STANDARDS_CATALOG_VERSION_REQUIRED")
    if not isinstance(standards,list) or not standards:
        _fail("SCOPED_STANDARDS_REQUIRED")
    catalog={}
    for item in standards:
        if not isinstance(item,dict) or any(not isinstance(item.get(k),str) or not item[k].strip() for k in ("standard_code","source_ref","source_sha256")) or not re.fullmatch(r"[0-9a-f]{64}",item["source_sha256"]) or not _ids(item.get("applies_to_write_scopes")) or not item["applies_to_write_scopes"]:
            _fail("STANDARD_SCOPE_SOURCE_INVALID")
        code=item["standard_code"]
        if code in catalog:_fail("STANDARD_DUPLICATE")
        catalog[code]=item
    sols=partition.get("solutions")
    if not isinstance(sols,list) or not sols:
        _fail("PARTITION_SOLUTIONS_MISSING")
    if not isinstance(solution_plans,list) or len(solution_plans)!=len(sols):
        _fail("DOD_SOLUTION_PLAN_MISMATCH")
    plan_by_id={}
    for plan in solution_plans:
        if not isinstance(plan,dict) or not isinstance(plan.get("solution_id"),str) or not plan["solution_id"].strip() or plan["solution_id"] in plan_by_id:
            _fail("DOD_SOLUTION_PLAN_MISMATCH")
        plan_by_id[plan["solution_id"]]=plan
    solution_ids=[s.get("id") if isinstance(s,dict) else None for s in sols]
    if len(set(solution_ids))!=len(solution_ids) or set(plan_by_id)!=set(solution_ids):
        _fail("DOD_SOLUTION_PLAN_MISMATCH")
    output=[]
    for sol in sols:
        sid=sol["id"]
        plan=plan_by_id[sid]
        scopes=sol.get("write_scope")
        reqs=sol.get("requirement_ids")
        accs=sol.get("acceptance_ids")
        if not _ids(scopes) or not scopes or not _ids(reqs) or not _ids(accs) or (not reqs and not accs):
            _fail("DOD_SOLUTION_OBLIGATIONS_INVALID")
        selected=plan.get("standard_codes")
        if not _ids(selected) or not selected:
            _fail("DOD_STANDARDS_SELECTION_REQUIRED")
        if any(code not in catalog for code in selected):
            _fail("DOD_STANDARD_UNDECLARED")
        applicable={code for code,row in catalog.items() if set(row["applies_to_write_scopes"]) & set(scopes)}
        if set(selected)!=applicable:
            _fail("DOD_SCOPE_STANDARD_COVERAGE_MISMATCH")
        checks=plan.get("checks")
        if not isinstance(checks,list) or not checks:
            _fail("DOD_CHECKS_REQUIRED")
        observed=set()
        covered_acc=set()
        covered_req=set()
        std_checked=set()
        planned=[]
        for check in checks:
            if not isinstance(check,dict) or any(not isinstance(check.get(k),str) or not check[k].strip() for k in ("check_id","kind","validation_code","input_ref")):
                _fail("DOD_CHECK_INVALID")
            cid=check["check_id"]
            if cid in observed:_fail("DOD_CHECK_DUPLICATE")
            observed.add(cid)
            kind=check["kind"]
            if kind not in ("STANDARD","ACCEPTANCE","REQUIREMENT","DEPENDENCY"):
                _fail("DOD_CHECK_KIND_INVALID")
            if not _ids(check.get("requirement_ids")) or not _ids(check.get("acceptance_ids")):
                _fail("DOD_CHECK_BINDINGS_INVALID")
            rq=set(check["requirement_ids"]); ac=set(check["acceptance_ids"])
            if not rq.issubset(reqs) or not ac.issubset(accs):
                _fail("DOD_CHECK_FOREIGN_OBLIGATION")
            std=check.get("standard_code")
            if kind=="STANDARD":
                if std not in selected:_fail("DOD_CHECK_STANDARD_NOT_SELECTED")
                std_checked.add(std)
            elif std is not None:
                _fail("DOD_CHECK_NONSTANDARD_CODE_FORBIDDEN")
            if kind=="REQUIREMENT" and not rq:_fail("DOD_REQUIREMENT_CHECK_UNBOUND")
            if kind=="ACCEPTANCE" and not ac:_fail("DOD_ACCEPTANCE_CHECK_UNBOUND")
            if kind=="DEPENDENCY" and not sol.get("depends_on"):
                _fail("DOD_DEPENDENCY_CHECK_WITHOUT_DEPENDENCY")
            covered_req.update(rq if kind=="REQUIREMENT" else ())
            covered_acc.update(ac if kind=="ACCEPTANCE" else ())
            planned.append(dict(check,status="NOT_EXECUTED",receipt_id=None,pass_claim_allowed=False))
        if std_checked!=set(selected):
            _fail("DOD_STANDARD_WITHOUT_CHECK")
        if covered_req!=set(reqs) or covered_acc!=set(accs):
            _fail("DOD_OBLIGATION_CHECK_COVERAGE_MISMATCH")
        if sol.get("depends_on") and not any(x["kind"]=="DEPENDENCY" for x in checks):
            _fail("DOD_DEPENDENCY_CHECK_MISSING")
        output.append({
            "solution_id":sid,"partition_sha256":sha,
            "standard_codes":sorted(selected),
            "check_count":len(planned),
            "checks":sorted(planned,key=lambda c:c["check_id"]),
            "status":"PLANNED_NOT_EXECUTED",
            "done":False,
            "tests_passed":False,
            "receipts_verified":False
        })
    result={
        "schema_version":"PG04_SOLUTION_DOD_CANDIDATE_V1",
        "status":"CANDIDATE_NOT_ADMITTED",
        "partition_sha256":sha,
        "standards_catalog_version":standards_catalog_version,
        "standards_manifest_sha256":_digest(standards),
        "standards_authenticity":"CALLER_SUPPLIED_UNVERIFIED",
        "standard_resolution_mode":"WRITE_SCOPE_FILTERED",
        "solutions":sorted(output,key=lambda x:x["solution_id"]),
        "checks_executed":False,"independent_judge_executed":False,
        "receipts_verified":False,"production_authority":False,
        "handoff_allowed":False
    }
    result["candidate_sha256"]=_digest(result)
    return result
