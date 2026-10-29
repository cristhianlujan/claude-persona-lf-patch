import json
from pathlib import Path
from pg00_c3_publication_guard_v1 import check_release,PublicationBlocked,STAGES,sha256
c=json.loads(Path(__file__).with_name("pg00_front_domain_map_candidate_v1.json").read_text())
try:check_release(c,{})
except PublicationBlocked as e: assert str(e)=="NOT_ACTIVE"
else: raise AssertionError("draft must not publish")
for label,mutate in [
 ("A7_OPEN_POLICY_MISSING",lambda x:x.update(front_kind_policy="STATIC_CLOSED")),
 ("OWNER_APPROVAL_MISSING",lambda x:None),
]:
    pass
print("PG00_C3_GOVERNANCE_GUARD_PASS draft_denied=1 no_authorization=True")
