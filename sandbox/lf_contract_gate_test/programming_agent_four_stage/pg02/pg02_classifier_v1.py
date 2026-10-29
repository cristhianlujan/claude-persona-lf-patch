"""PG-02 candidate classifier; pure function; NO admission authority."""
import hashlib
import json
import re

class PG02Blocked(ValueError):
    pass

def canonical(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

def digest(obj):
    return hashlib.sha256(canonical(obj).encode("utf-8")).hexdigest()

def verify_catalog_binding(mapping, expected_ref=None, expected_sha256=None):
    """Optional readback pin. An assertion of CURRENT by a caller is never authority."""
    if not isinstance(mapping, dict):
        raise PG02Blocked("CATALOG_INVALID")
    if expected_ref is not None and mapping.get("source_ref") != expected_ref:
        raise PG02Blocked("CATALOG_SOURCE_DRIFT")
    if expected_sha256 is not None and digest(mapping) != expected_sha256:
        raise PG02Blocked("CATALOG_DIGEST_DRIFT")
    return digest(mapping)

def classify(snapshot, mapping, *, expected_catalog_ref=None, expected_catalog_sha256=None):
    if not isinstance(snapshot, dict) or snapshot.get("schema_version") != "PROGRAMMING_CONTEXT_SNAPSHOT_V1":
        raise PG02Blocked("SNAPSHOT_SCHEMA_INVALID")
    if not isinstance(mapping, dict) or mapping.get("state") != "SOURCE_ONLY_CANDIDATE":
        raise PG02Blocked("CATALOG_NOT_AUTHORIZED")
    if not isinstance(mapping.get("source_ref"), str) or not mapping["source_ref"] or not isinstance(mapping.get("version"), str) or not mapping["version"]:
        raise PG02Blocked("CATALOG_PROVENANCE_MISSING")
    catalog_digest = verify_catalog_binding(mapping, expected_catalog_ref, expected_catalog_sha256)
    rule_set = mapping.get("front_kind_domains")
    if not isinstance(rule_set, dict) or not rule_set:
        raise PG02Blocked("CATALOG_RULES_MISSING")
    for front_kind, domains in rule_set.items():
        if not isinstance(front_kind, str) or not isinstance(domains, list) or not domains or any(not isinstance(d, str) or not re.fullmatch(r"[A-Z][A-Z0-9-]{1,63}", d) for d in domains):
            raise PG02Blocked("CATALOG_RULES_INVALID")
    granularity = snapshot.get("target_granularity")
    if not isinstance(granularity, dict) or not granularity:
        raise PG02Blocked("A2_GRANULARITY_MISSING")
    scopes = snapshot.get("scope_readiness")
    coverage = snapshot.get("material_front_coverage")
    matrix = snapshot.get("scope_front_matrix")
    if not isinstance(scopes, list) or not scopes or not isinstance(coverage, dict) or not isinstance(matrix, list) or not matrix:
        raise PG02Blocked("MATERIAL_INPUT_MISSING")
    fronts = coverage.get("material_fronts")
    if not isinstance(fronts, list) or not fronts:
        raise PG02Blocked("A7_FRONTS_MISSING")
    if any(not isinstance(s, dict) or not isinstance(s.get("scope_id"), str) or not s["scope_id"] for s in scopes):
        raise PG02Blocked("SCOPE_INVALID")
    if any(not isinstance(f, dict) or not isinstance(f.get("front_id"), str) or not f["front_id"] or not isinstance(f.get("scope_refs"), list) or not f["scope_refs"] for f in fronts):
        raise PG02Blocked("FRONT_INVALID")
    ss = {s["scope_id"]: s for s in scopes}
    ff = {f["front_id"]: f for f in fronts}
    if len(ss) != len(scopes) or len(ff) != len(fronts):
        raise PG02Blocked("DUPLICATE_ID")
    statuses = {"READY", "BLOCKED", "REQUIRES_DECISION", "NEED_MORE_EVIDENCE", "NOT_APPLICABLE"}
    if any(s.get("status") not in statuses for s in scopes):
        raise PG02Blocked("READINESS_INVALID")
    expected = {(sid, f["front_id"]) for f in fronts for sid in f["scope_refs"]}
    if any(sid not in ss for sid, _ in expected):
        raise PG02Blocked("A7_UNKNOWN_SCOPE")
    if any(not isinstance(r, dict) or not isinstance(r.get("scope_id"), str) or not isinstance(r.get("front_id"), str) for r in matrix):
        raise PG02Blocked("MATRIX_INVALID")
    observed = {(r["scope_id"], r["front_id"]) for r in matrix}
    if observed != expected or len(observed) != len(matrix):
        raise PG02Blocked("MATRIX_CONTRADICTION")
    for row in matrix:
        front = ff[row["front_id"]]
        if row.get("front_status") != front.get("status") or row.get("front_closure") != front.get("closure"):
            raise PG02Blocked("A7_RECLASSIFICATION_FORBIDDEN")
        closure = row.get("front_closure")
        if closure != "CLOSED" or row.get("effect_on_scope") != "PRESERVE":
            raise PG02Blocked("MATERIAL_FRONT_UNRESOLVED")
    if any(s["status"] != "READY" for s in scopes):
        raise PG02Blocked("PG01_SCOPE_NOT_READY")
    rows = []
    for sid in sorted(ss):
        links = sorted((ff[r["front_id"]] for r in matrix if r["scope_id"] == sid), key=lambda f: f["front_id"])
        domains = set()
        for front in links:
            kind = front.get("front_kind")
            mapped = rule_set.get(kind)
            if not mapped:
                raise PG02Blocked("DOMAIN_MAPPING_UNRESOLVED")
            domains.update(mapped)
        rows.append({"scope_id": sid, "input_readiness": ss[sid]["status"],
                     "front_ids": [f["front_id"] for f in links],
                     "candidate_domains": sorted(domains)})
    return {"schema_version": "PG02_CLASSIFICATION_CANDIDATE_V1",
            "status": "CANDIDATE_NOT_ADMITTED", "source_snapshot_sha256": digest(snapshot),
            "catalog_source_ref": mapping["source_ref"], "catalog_version": mapping["version"],
            "catalog_sha256": catalog_digest, "classification": rows}
