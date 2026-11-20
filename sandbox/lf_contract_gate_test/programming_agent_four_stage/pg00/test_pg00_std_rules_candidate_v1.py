import copy,json
from pathlib import Path
from validate_pg00_std_rules_candidate_v1 import validate,STDValidationError
p=Path(__file__).parent
src=json.loads((p/"pg00_std_adr_source_catalog_v1.json").read_text())
candidate=json.loads((p/"pg00_std_rules_candidate_v1.json").read_text())
assert validate(src,candidate)=={"state":"CANDIDATE_SHAPE_ONLY","rules":17,"release_authorized":False}
mutations=[]
def mutate(fn,reason):
 x=copy.deepcopy(candidate);fn(x);mutations.append((x,reason))
mutate(lambda x:x["rules"].pop(),"RULE_COUNT")
mutate(lambda x:x["rules"][0].update(adr="ADR-PROG-STD-099"),"ADR_PARITY")
mutate(lambda x:x["rules"][3].update(source_decision="fabricated"),"SOURCE_DRIFT")
mutate(lambda x:x["rules"][0].update(proposed_domain="UNKNOWN"),"POLICY_UNKNOWN")
mutate(lambda x:x["rules"][4].update(ok_example=""),"EXAMPLE_MISSING")
mutate(lambda x:x["rules"][6].update(no_example=x["rules"][6]["ok_example"]),"EXAMPLE_COLLISION")
mutate(lambda x:x["rules"][7].update(authority="ACTIVE"),"AUTHORITY_ESCALATION")
mutate(lambda x:x.update(state="ACTIVE_READBACK_VERIFIED"),"UNAUTHORIZED_RELEASE_STATE")
mutate(lambda x:x.update(precedence="L3 optional"),"L3_PRECEDENCE")
mutate(lambda x:x.update(stop_conditions=[]),"STOP_GUARDS")
for x,expected in mutations:
 try:validate(src,x)
 except STDValidationError as e:assert str(e)==expected,(str(e),expected)
 else:raise AssertionError(expected)
print("PG00_C3_RULES_PASS count=17 positive_shape=1 negatives=10 released=0")
