from profile_entity_lookup_v1 import plan_entity_lookup

def run():
    result = plan_entity_lookup({})
    assert result['action'] == 'BLOCKED'
    print('PASS_ENTITY_LOOKUP_MINIMUM')


def synthetic_verifier(kind, record):
    field={"scope":"scope_receipt_ref","catalog":"receipt_ref","lookup":"receipt_ref"}[kind]
    return str(record.get(field,"")).startswith("fixture://")

from copy import deepcopy
from profile_conversational_context_v1 import route_context_turn
SRC={"source_ref":"supabase://lf_ops.cargas_lotes","available":True}
BASE={"schema":"PROFILE_ENTITY_LOOKUP_V1","subject":"cargas","access_scope":"AUTHORIZED_READ_ONLY",
      "scope_receipt_ref":"fixture://scope","catalog":{"state":"RESOLVED",
      "receipt_ref":"fixture://catalog","sources":[SRC]},"lookups":[],"asked_question_ids":[]}
def row(i,t="2026-10-09T10:00:00"):
    return {"record_ref":"fixture-"+str(i),"source_ref":SRC["source_ref"],
            "occurred_at":t,"file_name":"cartera-"+str(i)+".xlsx"}
def lookup(window,rows=None,state="SUCCESS"):
    return {"source_ref":SRC["source_ref"],"window":window,"state":state,
            "rows":rows or [],"receipt_ref":"fixture://"+window}
def expect(task,action):
    out=plan_entity_lookup(task,synthetic_verifier)
    assert out["action"]==action,(action,out)
    assert out["write_authorized"] is False
    return out
