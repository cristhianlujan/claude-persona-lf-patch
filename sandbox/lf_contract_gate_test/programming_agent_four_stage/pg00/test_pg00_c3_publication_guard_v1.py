import copy
import json
from pathlib import Path
from pg00_c3_publication_guard_v1 import check_release, PublicationBlocked, STAGES, sha256

candidate=json.loads(Path(__file__).with_name("pg00_front_domain_map_candidate_v1.json").read_text())
def blocked(c,e,code):
    try: check_release(c,e)
    except PublicationBlocked as exc: assert str(exc)==code,(str(exc),code)
    else:raise AssertionError(code)
blocked(candidate,{},"NOT_ACTIVE")
c=copy.deepcopy(candidate);c["state"]="ACTIVE_READBACK_VERIFIED"
e={"transition_history":list(STAGES),"owner_approval_ref":"approval://owner",
   "independent_review_ref":"review://different-reviewer",
   "pase_status":"PASS","pase_receipt":"pase://fixture",
   "train_status":"APPLIED","train_receipt":"train://fixture",
   "head_sha":"a"*40,"reviewed_head_sha":"a"*40,
   "repo_digest":sha256(c),"transversal_digest":sha256(c),
   "catalog_std_full":True,"machine_format_ref":"repo://fixture",
   "llm_format_ref":"repo://fixture","aud02_decision_ref":"decision://fixture"}
# Caller supplied fixture must NEVER be treated as authentic authority.
assert check_release(c,e)["state"]=="EVIDENCE_SHAPE_VALID_ONLY_NOT_AUTHORIZED"
negative=[
  ("A7_OPEN_POLICY_MISSING",lambda x,y:x.update(front_kind_policy="STATIC_CLOSED")),
  ("INVALID_TRANSITION_HISTORY",lambda x,y:y.update(transition_history=list(STAGES)[1:])),
  ("OWNER_APPROVAL_MISSING",lambda x,y:y.pop("owner_approval_ref")),
  ("INDEPENDENT_REVIEW_MISSING",lambda x,y:y.pop("independent_review_ref")),
  ("SELF_REVIEW",lambda x,y:y.update(independent_review_ref=y["owner_approval_ref"])),
  ("PASE_MISSING",lambda x,y:y.pop("pase_receipt")),
  ("TRAIN_RECEIPT_MISSING",lambda x,y:y.pop("train_receipt")),
  ("HEAD_DRIFT",lambda x,y:y.update(reviewed_head_sha="b"*40)),
  ("READBACK_DRIFT",lambda x,y:y.update(transversal_digest="0"*64)),
  ("STD_CATALOG_INCOMPLETE",lambda x,y:y.update(catalog_std_full=False)),
  ("AUD02_UNRESOLVED",lambda x,y:y.pop("aud02_decision_ref")),
]
for reason,mutation in negative:
    x,y=copy.deepcopy(c),copy.deepcopy(e)
    if reason=="AUD02_UNRESOLVED": y.pop("aud02_decision_ref")
    else:mutation(x,y)
    blocked(x,y,reason)
print(f"PG00_C3_GOVERNANCE_GUARD_PASS negatives={len(negative)+1} fixture_shape=PASS no_authorization=True")
