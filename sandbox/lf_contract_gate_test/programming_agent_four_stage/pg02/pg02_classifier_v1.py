import json, hashlib
class PG02Blocked(ValueError): pass
def classify(snapshot, mapping):
    if snapshot.get("schema_version") != "PROGRAMMING_CONTEXT_SNAPSHOT_V1": raise PG02Blocked("SCHEMA")
    if mapping.get("state") != "SOURCE_ONLY_CANDIDATE" or not mapping.get("source_ref"): raise PG02Blocked("MAP_UNVERIFIED")
    scopes=snapshot.get("scope_readiness", [])
    fronts=snapshot.get("material_front_coverage",{}).get("material_fronts",[])
    matrix=snapshot.get("scope_front_matrix",[])
    if not scopes or not fronts or not matrix: raise PG02Blocked("MISSING_MATERIAL")
    if not isinstance(snapshot.get("target_granularity"), dict):
        raise PG02Blocked("A2_GRANULARITY_MISSING")
    allowed_status={"READY","BLOCKED","REQUIRES_DECISION","NEED_MORE_EVIDENCE","NOT_APPLICABLE"}
    if any(not isinstance(s,dict) or s.get("status") not in allowed_status for s in scopes):
        raise PG02Blocked("READINESS_INVALID")
    ss={s["scope_id"]:s for s in scopes}
    ff={f["front_id"]:f for f in fronts}
    if len(ss)!=len(scopes) or len(ff)!=len(fronts): raise PG02Blocked("DUPLICATE")
    expected={(sid,f["front_id"]) for f in fronts for sid in f["scope_refs"]}
    actual={(r["scope_id"],r["front_id"]) for r in matrix}
    if actual!=expected or len(actual)!=len(matrix): raise PG02Blocked("MATRIX_MISMATCH")
    for r in matrix:
        f=ff[r["front_id"]]
        if r["front_status"]!=f["status"] or r["front_closure"]!=f["closure"]: raise PG02Blocked("A7_RECLASSIFICATION")
    if any(s["status"] != "READY" for s in scopes):
        raise PG02Blocked("PG01_SCOPE_NOT_READY")
    rows=[]
    for sid in sorted(ss):
        links=sorted((ff[r["front_id"]] for r in matrix if r["scope_id"]==sid),key=lambda f:f["front_id"])
        domains=set()
        for f in links:
            d=mapping["front_kind_domains"].get(f["front_kind"])
            if not d: raise PG02Blocked("UNMAPPED_FRONT")
            domains.update(d)
        rows.append({"scope_id":sid,"input_status":ss[sid]["status"],"front_ids":[f["front_id"] for f in links],"candidate_domains":sorted(domains)})
    digest=hashlib.sha256(json.dumps(snapshot,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
    return {"schema_version":"PG02_CLASSIFICATION_CANDIDATE_V1","status":"CANDIDATE_NOT_ADMITTED","source_sha256":digest,"mapping_ref":mapping["source_ref"],"scopes":rows}