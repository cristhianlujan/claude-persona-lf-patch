"""Real module composition with negative authority boundaries; no hosted effects."""
import copy
from test_pg02_classifier_v1 import s,m
from test_pg02_c4_evidence_adapter_v1 import e
from pg01_pg02_isolated_smoke_v1 import run_isolated_smoke
from pg02_classifier_v1 import PG02Blocked

fixture={"verified":False,"reason":"ISOLATED_TEST_FIXTURE_ONLY","candidate_frame":copy.deepcopy(e)}
out=run_isolated_smoke(copy.deepcopy(s),copy.deepcopy(m),copy.deepcopy(fixture))
assert out["authorized"] is False and out["deploy_allowed"] is False
assert out["pg01_authority"]=="UNVERIFIED_CANDIDATE_ONLY"
assert out["pg02"]["status"]=="CANDIDATE_NOT_ADMITTED"
assert out["pg02"]["context_id"]==e["context_id"]
assert out==run_isolated_smoke(copy.deepcopy(s),copy.deepcopy(m),copy.deepcopy(fixture))
negative=[(None,"PG01_C4_READBACK_REQUIRED"),
 ({"verified":True,"candidate_frame":e},"PG01_C4_TRUSTED_AUTHORITY_UNAVAILABLE"),
 ({"verified":False,"reason":"PG01_C4_FRAMEWORK_PROVENANCE_NOT_IMPLEMENTED"},"PG01_C4_REAL_READBACK_NOT_ADMITTED"),
 ({"verified":False,"reason":"ISOLATED_TEST_FIXTURE_ONLY"},"MISSING:PG01_C4_EVIDENCE"),
 ({"verified":False,"reason":"ISOLATED_TEST_FIXTURE_ONLY","candidate_frame":dict(e,context_sha256="forged")},"CONTRADICTION:PG01_C4_DIGEST_INVALID")]
for value,expected in negative:
 try:run_isolated_smoke(s,m,value)
 except PG02Blocked as ex: assert str(ex)==expected,(ex,expected)
 else:raise AssertionError(expected)
print("PG01_PG02_ISOLATED_SMOKE_PASS positives=1 negatives=5 no_authority=True")
