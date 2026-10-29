import copy
from pg02_classification_outcome_v1 import classify_with_outcome
from test_pg02_classifier_v1 import s,m
ok=classify_with_outcome(s,m)
assert ok["decision"]=="CANDIDATE_ONLY" and ok["dispatch_allowed"] is False
broken=copy.deepcopy(s);broken["scope_front_matrix"][0]["front_status"]="OPTIONAL"
out=classify_with_outcome(broken,m)
assert out["decision"]=="CONTRADICTION" and out["return_to"]=="ANALYSIS_PHASE_1"
assert out["dispatch_allowed"] is False and out["reason_code"]=="A7_PARITY"
missing=copy.deepcopy(s);missing.pop("stack_profile")
out=classify_with_outcome(missing,m)
assert out["decision"]=="BLOCK" and out["return_to"] is None
assert out["reason_code"]=="MISSING:STACK_PROFILE_NOT_BOUND"
print("PG02_OUTCOME_PASS candidate=1 contradiction=1 missing=1")
