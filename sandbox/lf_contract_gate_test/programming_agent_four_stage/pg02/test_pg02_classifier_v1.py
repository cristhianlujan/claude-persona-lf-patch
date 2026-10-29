import copy
from pg02_classifier_v1 import classify,PG02Blocked
s={"schema_version":"PROGRAMMING_CONTEXT_SNAPSHOT_V1","target_granularity":{"level":"SCREEN","target_ref":"B2B-AUTH-001"},"scope_readiness":[{"scope_id":"B2B_COPY","status":"READY"}],"material_front_coverage":{"material_fronts":[{"front_id":"F1","front_kind":"UI_RULE","status":"REQUIRED","closure":"CLOSED","scope_refs":["B2B_COPY"]}]},"scope_front_matrix":[{"scope_id":"B2B_COPY","front_id":"F1","front_status":"REQUIRED","front_closure":"CLOSED","effect_on_scope":"PRESERVE"}]}
m={"state":"SOURCE_ONLY_CANDIDATE","source_ref":"fixture://PG02-C1","front_kind_domains":{"UI_RULE":["STD-FE","NAV","MSG"]}}
a=classify(s,m)
assert a==classify(copy.deepcopy(s),m)
assert a["scopes"][0]["candidate_domains"]==["MSG","NAV","STD-FE"]
for fn,reason in [(lambda x:x["scope_front_matrix"][0].update(front_status="OPTIONAL"),"A7_RECLASSIFICATION"),(lambda x:x.update(scope_front_matrix=[]),"MISSING_MATERIAL"),(lambda x:x["material_front_coverage"]["material_fronts"][0].update(front_kind="UNKNOWN"),"UNMAPPED_FRONT")]:
 t=copy.deepcopy(s);fn(t)
 try:classify(t,m)
 except PG02Blocked as e:assert str(e)==reason
 else:raise AssertionError(reason)
for mutate,reason in [
 (lambda x:x.pop("target_granularity"),"A2_GRANULARITY_MISSING"),
 (lambda x:x["scope_readiness"][0].update(status="BLOCKED"),"PG01_SCOPE_NOT_READY"),
 (lambda x:x["scope_readiness"][0].update(status="UNKNOWN"),"READINESS_INVALID")]:
 b=copy.deepcopy(s);mutate(b)
 try:classify(b,m)
 except PG02Blocked as e:assert str(e)==reason
 else:raise AssertionError(reason)
print("PG02_CANDIDATE_SMOKE_PASS positives=1 negatives=6 deterministic=PASS")