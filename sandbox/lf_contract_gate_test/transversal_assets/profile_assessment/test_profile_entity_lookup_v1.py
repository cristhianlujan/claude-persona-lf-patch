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

def exercise_variants():
    c=deepcopy(BASE);c["catalog"]=None
    expect(c,"DISCOVER_SOURCES")
    c=deepcopy(BASE);c["catalog"]={"state":"NO_SOURCE","receipt_ref":"fixture://catalog","sources":[]}
    assert "pantalla" in expect(c,"ASK_USER")["user_question"]
    c=deepcopy(BASE);assert expect(c,"QUERY_SOURCE")["window"]=="RECENT"
    c["lookups"]=[lookup("RECENT")]
    assert expect(c,"QUERY_SOURCE")["window"]=="HISTORICAL"
    c["lookups"].append(lookup("HISTORICAL"))
    assert "históricas" in expect(c,"ASK_USER")["user_question"]
    c["asked_question_ids"]=["entity_location"]
    expect(c,"LIMITED_RESPONSE")
    c=deepcopy(BASE);c["lookups"]=[lookup("RECENT",[row(1)])]
    assert expect(c,"INVESTIGATE_CANDIDATE")["identity_confirmed_by_user"] is False
    c["lookups"]=[lookup("RECENT",[row(1),row(2,"2026-10-08T11:30:00")])]
    q=expect(c,"ASK_USER")["user_question"]
    assert "cartera-1.xlsx" in q and "08-10-2026" in q and "código" not in q
    c["lookups"]=[lookup("RECENT",[row(i) for i in range(5)])]
    assert "aproximadamente" in expect(c,"ASK_USER")["user_question"]
    c["lookups"]=[lookup("RECENT"),lookup("HISTORICAL",[row(9,"2026-08-01T09:40:00")])]
    assert "01-08-2026" in expect(c,"INVESTIGATE_CANDIDATE")["human_description"]
    c["lookups"]=[lookup("RECENT",state="SOURCE_UNAVAILABLE"),lookup("HISTORICAL",state="SOURCE_UNAVAILABLE")]
    expect(c,"LIMITED_RESPONSE")
