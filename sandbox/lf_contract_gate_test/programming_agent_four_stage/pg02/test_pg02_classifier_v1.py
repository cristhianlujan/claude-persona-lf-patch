import copy
from pg02_classifier_v1 import classify, PG02Blocked
s = {"schema_version":"PROGRAMMING_CONTEXT_SNAPSHOT_V1",
     "target_granularity":{"level":"SCREEN","target_ref":"B2B-AUTH-001"},
     "scope_readiness":[{"scope_id":"B2B_COPY","status":"READY"}],
     "material_front_coverage":{"material_fronts":[{"front_id":"F1","front_kind":"UI_RULE",
          "status":"REQUIRED","closure":"CLOSED","scope_refs":["B2B_COPY"]}]},
     "scope_front_matrix":[{"scope_id":"B2B_COPY","front_id":"F1","front_status":"REQUIRED",
                            "front_closure":"CLOSED","effect_on_scope":"PRESERVE"}]}
m = {"state":"SOURCE_ONLY_CANDIDATE","source_ref":"fixture://PG02-C1",
     "version":"fixture-v1","front_kind_domains":{"UI_RULE":["STD-FE","NAV","MSG"]}}
original = copy.deepcopy(s)
result = classify(s,m)
assert s == original
assert result == classify(copy.deepcopy(s),copy.deepcopy(m))
assert result["status"] == "CANDIDATE_NOT_ADMITTED"
assert result["classification"][0]["candidate_domains"] == ["MSG","NAV","STD-FE"]
negative_cases = [
    (lambda s,m:s.pop("target_granularity"),"A2_GRANULARITY_MISSING"),
    (lambda s,m:s["scope_readiness"][0].update(status="BLOCKED"),"PG01_SCOPE_NOT_READY"),
    (lambda s,m:s["scope_readiness"][0].update(status="UNKNOWN"),"READINESS_INVALID"),
    (lambda s,m:s["scope_front_matrix"][0].update(front_status="OPTIONAL"),"A7_RECLASSIFICATION_FORBIDDEN"),
    (lambda s,m:s.update(scope_front_matrix=[]),"MATERIAL_INPUT_MISSING"),
    (lambda s,m:s["material_front_coverage"]["material_fronts"][0].update(front_kind="UNKNOWN"),"DOMAIN_MAPPING_UNRESOLVED"),
    (lambda s,m:s["scope_front_matrix"][0].update(effect_on_scope="BLOCKS"),"MATERIAL_FRONT_UNRESOLVED"),
    (lambda s,m:s["material_front_coverage"]["material_fronts"][0].update(scope_refs=["UNKNOWN"]),"A7_UNKNOWN_SCOPE"),
    (lambda s,m:m.pop("version"),"CATALOG_PROVENANCE_MISSING"),
    (lambda s,m:m.update(state="CURRENT_RELEASED"),"CATALOG_NOT_AUTHORIZED"),
    (lambda s,m:m["front_kind_domains"].update(UI_RULE=[]),"CATALOG_RULES_INVALID"),
]
for mutate, expected in negative_cases:
    ss,mm=copy.deepcopy(s),copy.deepcopy(m)
    mutate(ss,mm)
    try:
        classify(ss,mm)
    except PG02Blocked as e:
        assert str(e)==expected, (expected,str(e))
    else:
        raise AssertionError(expected)
print(f"PG02_CANDIDATE_SMOKE_PASS positive=1 negatives={len(negative_cases)} deterministic=PASS")
