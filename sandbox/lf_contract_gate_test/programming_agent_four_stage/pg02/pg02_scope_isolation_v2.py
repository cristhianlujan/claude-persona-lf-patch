"""PG-02 scope-isolated A7 classifier candidate. No PG-01 authority or official catalog release."""
from pg02_classifier_v1 import PG02Blocked, digest

VALID_STATUSES={"REQUIRED","REUSE_AS_IS","NOT_APPLICABLE"}
VALID_CLOSURES={"CLOSED","BLOCKED"}

def classify_scopes(snapshot, mapping):
    if snapshot.get("schema_version")!="PROGRAMMING_CONTEXT_SNAPSHOT_V1":
        raise PG02Blocked("SNAPSHOT_SCHEMA_INVALID")
    cov=snapshot.get("material_front_coverage")
    if not isinstance(cov,dict) or cov.get("all_material_fronts_accounted") is not True or cov.get("unmapped_material_signals") != []:
        raise PG02Blocked("CONTRADICTION:A7_UNACCOUNTED_MATERIAL_SIGNAL")
    scopes=snapshot.get("scope_readiness")
    matrix=snapshot.get("scope_front_matrix")
    fronts=cov.get("material_fronts")
    if not all(isinstance(x,list) for x in (scopes,matrix,fronts)) or not scopes or not fronts:
        raise PG02Blocked("CONTRADICTION:INVALID_SCOPE_MATRIX")
    if not isinstance(snapshot.get("target_granularity"),dict) or not snapshot["target_granularity"]:
        raise PG02Blocked("CONTRADICTION:A2_MISSING")
    sidx={x["scope_id"]:x for x in scopes}
    fidx={x["front_id"]:x for x in fronts}
    if len(sidx)!=len(scopes) or len(fidx)!=len(fronts):
        raise PG02Blocked("CONTRADICTION:DUPLICATE")
    expected={(sid,fid) for fid,f in fidx.items() for sid in f["scope_refs"]}
    observed={(r["scope_id"],r["front_id"]) for r in matrix}
    if observed!=expected or len(observed)!=len(matrix):
        raise PG02Blocked("CONTRADICTION:MATRIX_MISMATCH")
    for r in matrix:
        f=fidx[r["front_id"]]
        if f.get("status") not in VALID_STATUSES or f.get("closure") not in VALID_CLOSURES:
            raise PG02Blocked("CONTRADICTION:A7_ENUM")
        if (r.get("front_status"),r.get("front_closure"))!=(f["status"],f["closure"]):
            raise PG02Blocked("CONTRADICTION:A7_PARITY")
    rules=mapping.get("front_kind_domains") if isinstance(mapping,dict) else None
    if mapping.get("state")!="SOURCE_ONLY_CANDIDATE" or not isinstance(rules,dict):
        raise PG02Blocked("CATALOG_NOT_AUTHORIZED")
    rows=[]
    for s in sorted(scopes,key=lambda x:x["scope_id"]):
        sid=s["scope_id"]
        links=sorted((r for r in matrix if r["scope_id"]==sid),key=lambda x:x["front_id"])
        if {r["front_id"] for r in links}!=set(s.get("material_front_refs",[])):
            raise PG02Blocked("CONTRADICTION:BIDIRECTIONAL_MAPPING")
        reasons=[]
        domains=set()
        for r in links:
            f=fidx[r["front_id"]]
            status=f["status"]
            effect=r.get("effect_on_scope")
            if status=="NOT_APPLICABLE":
                if effect!="NOT_APPLICABLE": raise PG02Blocked("CONTRADICTION:NA_EFFECT")
                continue
            if f["closure"]=="BLOCKED" or effect=="BLOCKS":
                reasons.append(f["front_id"]+":BLOCKED")
                continue
            if effect!="PRESERVE": raise PG02Blocked("CONTRADICTION:EFFECT")
            kinds=rules.get(f.get("front_kind"))
            if not kinds: reasons.append(f["front_id"]+":UNMAPPED")
            else: domains.update(kinds)
        ready=s.get("status")=="READY" and not reasons
        rows.append({"scope_id":sid,"state":"READY_FOR_CLASSIFICATION" if ready else "BLOCKED",
                     "candidate_domains":sorted(domains) if ready else [],"blockers":sorted(reasons)})
    return {"schema_version":"PG02_CLASSIFICATION_CANDIDATE_V2",
            "status":"CANDIDATE_NOT_ADMITTED","source_digest":digest(snapshot),
            "scopes":rows}
