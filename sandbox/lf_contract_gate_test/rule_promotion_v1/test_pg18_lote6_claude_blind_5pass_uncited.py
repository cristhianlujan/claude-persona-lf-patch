#!/usr/bin/env python3
"""L6: auditor-supplied 154 real verdicts WITHOUT their verbatim citations.
PG18 fixture is NEVER an #3682 native receipt. No new production judge or IG.
All case manipulations within ROLLBACK; no historical RUN touched.
"""
import json
import hashlib
from pathlib import Path
import test_pg18_lote5_real_verdict_profile_return as l5
import test_pg18_lote4b_validator_reuse as base

ROOT=Path(__file__).resolve().parents[3]
FIXTURE=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1/lote6_claude_blind_5pass_verdicts_not_native_ig_receipt_v1.json"
BLIND=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1/lote4c_fresh_blind_v1.json"
KEY=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1/lote4c_fresh_answer_key_v1.json"
DB="lf_3779_l6_auditor_uncited_pg18"
N=0

def sql(query):return base.sql(query,db=DB)
def assert_case(name,condition,raw):
    global N
    print("RAW_L6_"+name+" "+json.dumps(raw,sort_keys=True,ensure_ascii=False),flush=True)
    if not condition:raise AssertionError("L6_FAIL_"+name+": "+json.dumps(raw,sort_keys=True))
    N+=1
    print("PASS_L6_"+name,flush=True)

def main():
    fixture_sha256=hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
    print("RAW_L6_USER_VERDICT_FIXTURE_SHA256 "+fixture_sha256,flush=True)
    fixture=json.loads(FIXTURE.read_text(encoding="utf-8"))
    blind=json.loads(BLIND.read_text(encoding="utf-8"))
    key=json.loads(KEY.read_text(encoding="utf-8"))
    entries=fixture["entries"]
    ids=[x["id"] for x in entries]
    counts={v:sum(c["verdict"]==v for c in entries) for v in ("ALLOW","BLOCK")}
    expected={c["id"]:c["expected"] for c in key["cases"]}
    ids_match=set(ids)=={c["id"] for c in blind["cases"]}
    labels_match=all(expected.get(c["id"])==c["verdict"] for c in entries)
    exact_quotes_captured=sum(c["exact_excerpt"] is not None for c in entries)
    fixture_is_user_supplied=fixture["fixture_label"]=="REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED"
    assert_case("REAL_USER_VERDICTS_MATCH_BLIND_SET_NOT_INDEPENDENCE",
      len(entries)==154 and len(set(ids))==154 and ids_match and labels_match
      and counts=={"ALLOW":24,"BLOCK":130}
      and all(x["citation_status"]=="UNVERIFIED_NOT_CAPTURED" for x in entries)
      and exact_quotes_captured==0 and fixture_is_user_supplied,
      {"total":len(entries),"unique":len(set(ids)),"counts":counts,
       "no_citations_captured":exact_quotes_captured==0,
       "source_label":fixture["fixture_label"],"reported_passes":fixture["reported_passes"],
       "five_passes_independently_replayed_in_ci":False,
       "set_match":ids_match,"verdict_vs_expected_match":labels_match})

    l5.DB=DB
    l5.l4d.DB=DB
    l5.bootstrap()

    # This table/function are built ONLY in disposable PG18 TEST DATABASE.
    # They are NOT installed as production migration, nor existing IG receipt.
    sql("""CREATE TABLE public.l6_auditor_only_fixture (
      id text primary key,verdict text not null,
      provenance text not null,citation_status text not null,
      exact_excerpt text,observed_hash text not null
    );
    CREATE OR REPLACE FUNCTION public.l6_advisory_measurement_route(
      p_case_id text,p_expected_hash text)
    RETURNS jsonb LANGUAGE plpgsql STABLE AS $l6$
    DECLARE x public.l6_auditor_only_fixture%ROWTYPE; v text;
    BEGIN
      SELECT * INTO x FROM public.l6_auditor_only_fixture WHERE id=p_case_id;
      IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','code','CASE_NOT_FOUND'); END IF;
      v:=encode(extensions.digest(convert_to(jsonb_build_object(
         'id',x.id,'verdict',x.verdict,'provenance',x.provenance,
         'citation_status',x.citation_status,'exact_excerpt',x.exact_excerpt
       )::text,'UTF8'),'sha256'),'hex');
      IF x.observed_hash IS DISTINCT FROM v OR v IS DISTINCT FROM p_expected_hash THEN
        RETURN jsonb_build_object('status','BLOCKED','code','CLAUDE_AUDITOR_FIXTURE_HASH_DRIFT',
          'promotable',false); END IF;
      IF x.provenance IS DISTINCT FROM 'REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED'
       OR x.exact_excerpt IS NOT NULL OR x.citation_status IS DISTINCT FROM 'UNVERIFIED_NOT_CAPTURED' THEN
        RETURN jsonb_build_object('status','BLOCKED','code','L6_FIXTURE_PROVENANCE_INVALID',
          'promotable',false); END IF;
      IF x.verdict='BLOCK' THEN
        RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','case_id',x.id,
          'reason','CLAUDE_BLIND_BLOCK_NO_AUTHORITY','promotable',false,
          'evidence_type','AUDITOR_FIXTURE_NOT_NATIVE_IG_RECEIPT'); END IF;
      IF x.verdict='ALLOW' THEN
        RETURN jsonb_build_object('status','PROFILE_OWNER_CITATION_CAPTURE_REQUIRED',
          'case_id',x.id,'next_actor','PROFILE_OWNER',
          'citation_status','UNVERIFIED_NOT_CAPTURED',
          'promotable',false,'owner_may_approve',false,
          'evidence_type','AUDITOR_FIXTURE_NOT_NATIVE_IG_RECEIPT'); END IF;
      RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
          'reason','L6_VERDICT_UNSUPPORTED','promotable',false);
    END $l6$;""")

    # Actual user case verdicts, WITHOUT citations. Each SQL case rolls back.
    chosen_allow=next(c for c in entries if c["verdict"]=="ALLOW")
    chosen_block=next(c for c in entries if c["verdict"]=="BLOCK")
    def route(c,alter_hash=False):
        payload={"id":c["id"],"verdict":c["verdict"],
                 "provenance":fixture["fixture_label"],
                 "citation_status":c["citation_status"],"exact_excerpt":c["exact_excerpt"]}
        q="""BEGIN;
        INSERT INTO public.l6_auditor_only_fixture(
          id,verdict,provenance,citation_status,exact_excerpt,observed_hash)
        SELECT j->>'id',j->>'verdict',j->>'provenance',
           j->>'citation_status',j->>'exact_excerpt',
           encode(extensions.digest(convert_to(j::text,'UTF8'),'sha256'),'hex')
        FROM (SELECT """+base.lit(json.dumps(payload,sort_keys=True))+"""::jsonb AS j) s;
        """+(("UPDATE public.l6_auditor_only_fixture SET observed_hash=repeat('a',64);") if alter_hash else "")+"""
        SELECT 'ROUTE|'||public.l6_advisory_measurement_route("""+base.lit(c["id"])+""",
          (SELECT encode(extensions.digest(convert_to(jsonb_build_object(
           'id',id,'verdict',verdict,'provenance',provenance,
           'citation_status',citation_status,'exact_excerpt',exact_excerpt
          )::text,'UTF8'),'sha256'),'hex') FROM public.l6_auditor_only_fixture
          WHERE id="""+base.lit(c["id"])+"""))::text;
        ROLLBACK;
        SELECT 'ROLLBACK_READBACK|'||jsonb_build_object(
         'fixture_rows',(SELECT count(*) FROM public.l6_auditor_only_fixture),
         'rule_state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'))::text;
        """
        return sql(q)
    allowed=route(chosen_allow)
    assert_case("ALLOW_REAL_USER_VERDICT_TO_PROFILE_REVIEW_ONLY",
       allowed["ROUTE"]["status"]=="PROFILE_OWNER_CITATION_CAPTURE_REQUIRED"
       and allowed["ROUTE"]["owner_may_approve"] is False
       and allowed["ROUTE"]["promotable"] is False
       and allowed["ROUTE"]["next_actor"]=="PROFILE_OWNER"
       and allowed["ROLLBACK_READBACK"]["fixture_rows"]==0,
       {"id":chosen_allow["id"],"verdict":"ALLOW","raw":allowed,
        "profile_owner_approval_attested":False})

    blocked=route(chosen_block)
    assert_case("BLOCK_REAL_USER_VERDICT_TO_HUMAN_NEVER_PROMOTE",
       blocked["ROUTE"]["status"]=="HUMAN_DECISION_REQUIRED"
       and blocked["ROUTE"]["promotable"] is False
       and blocked["ROLLBACK_READBACK"]["fixture_rows"]==0,
       {"id":chosen_block["id"],"verdict":"BLOCK","raw":blocked})

    tampered=route(chosen_allow,alter_hash=True)
    assert_case("AUDITOR_FIXTURE_HASH_TAMPER_REJECTED",
       tampered["ROUTE"]["status"]=="BLOCKED"
       and tampered["ROUTE"]["code"]=="CLAUDE_AUDITOR_FIXTURE_HASH_DRIFT",
       {"id":chosen_allow["id"],"raw":tampered})

    # CRUCIAL: A real user ALLOW without a source quote must NOT enter the
    # existing #3682 receipt or the owner authorizer. Missing #3682 evidence
    # denies ALL promotions. This remains distinct from the advisory route.
    absent=l5.run_case(missing_case=True)
    assert_case("NO_LITERAL_QUOTE_OR_NATIVE_IG_RECEIPT_NO_AUTO_PROMOTION",
      absent["CASEPIN"]["status"]=="RETRY_REQUIRED"
      and absent["CASEPIN"]["blocking_code"]=="L5_REAL_BLIND_CASE_RECEIPT_NOT_PROVIDED"
      and absent["OWNER_APPROVAL"]["status"]!="APPROVED"
      and absent["APPLY"]["status"]=="BLOCKED"
      and absent["WITHIN_TX"]["candidate_state"]=="CANDIDATO"
      and absent["ROLLBACK"]["promotions"]==0,
      {"case_id":chosen_allow["id"],"gate":absent["CASEPIN"],
       "owner":absent["OWNER_APPROVAL"],"apply":absent["APPLY"],
       "readback":absent["WITHIN_TX"],"rollback":absent["ROLLBACK"]})

    # This is a DIFFERENT legacy synthetic positive control. It verifies the
    # actual apply() hash guard; it does not assert the user fixture can approve.
    control=l5.run_case(tamper_case=True)
    assert_case("APPLY_REVALIDATES_CASE_HASH_FAIL_CLOSED_SYNTHETIC_CONTROL",
      control["OWNER_APPROVAL"]["status"]=="APPROVED"
      and control["APPLY"]["status"]=="BLOCKED"
      and control["WITHIN_TX"]["candidate_state"]=="CANDIDATO",
      {"source":"L5_SYNTHETIC_POSITIVE_CONTROL_NOT_USER_REVIEW",
       "apply":control["APPLY"],"state":control["WITHIN_TX"],
       "user_case_promotion_attested":False})

    triage_path=ROOT/"docs/input-governance/L6_RUNTIME_ORPHANS_21_AND_PROFILE3_READONLY_TRIAGE_V1.json"
    triage=json.loads(triage_path.read_text(encoding="utf-8"))
    runtime=triage["runtime_execution_rows"]
    assert_case("READONLY_RUNTIME_21_DISCREPANCY_NEVER_COLLAPSE_TO_20",
       len(runtime)==21
       and triage["declared_by_auditor_runtime_count"]==20
       and triage["live_actual_runtime_count"]==21
       and triage["confirmed_active_leases"]==0
       and triage["checkpoint_positive"]==0
       and triage["no_mutations"] is True
       and len({r["execution_id"] for r in runtime})==21,
       {"auditor_reported":20,"live_readback":len(runtime),"active_leases":triage["confirmed_active_leases"],
        "checkpoint_positive":triage["checkpoint_positive"],"no_mutations":triage["no_mutations"]})

    early=triage["previous_three_profile_runs_reclassified"]
    assert_case("THREE_EARLY_PROFILE_RUNS_NOT_PROVEN_STEP40_FAILURE",
       len(early)==3
       and all(r["step40_executed"] is False and int(r["last_step"])<40
               and r["classification"]=="RECOVERY_REQUIRES_CONTEXT_VALIDATION_NOT_DISCARDABLE"
               for r in early)
       and {r["scope_target_type"] for r in early}=={"PANTALLA","REGLA","INPUT_GOVERNANCE"},
       {"three": [{"id":r["execution_id"],"last_step":r["last_step"],
                   "scope":r["scope_target_type"],"classification":r["classification"]}
                  for r in early],
        "step40_causality":"UNVERIFIED_NO_STEP40_INVOCATION"})

    print("LF_L6_UNCITED_USER_VERDICT_FIXTURE_PG18_PASS checks="+str(N),flush=True)
    print("REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED=true REAL_CITATIONS=UNVERIFIED_NOT_CAPTURED",flush=True)
    print("USER_FIXTURE_AUTO_PROMOTIONS=0 NATIVE_MODEL_CALLS=0 JUDGE_ADDED=0 READONLY_HISTORIC_RUNS=true",flush=True)

if __name__=="__main__":
    main()
