#!/usr/bin/env python3
"""L9: measure 154 ORIGINAL user-provided chat-export lines against the UNMODIFIED L7/L8 gate.
The export is NOT an #3682 native receipt or official owner Step70. No extra IG/judge/LLM.
Every scenario is PG18-only + ROLLBACK; mock Step70 never counts as real authority.
"""
import hashlib
import json
from collections import Counter
from pathlib import Path
import test_pg18_lote7_exact_citation_capture as l7
from test_pg18_lote7_exact_citation_capture import lit

HERE=Path(__file__).resolve().parent
EXPORT=HERE/"lote9_real_review_pass1_chat_export_model_unattested.txt"
META=HERE/"lote9_real_review_pass1_chat_export_model_unattested.json"
L6=HERE/"lote6_claude_blind_5pass_verdicts_not_native_ig_receipt_v1.json"
DB="lf_3779_l9_chat_export_measurement_pg18"

def check(name,yes,evidence):
    print("RAW_L9_"+name+" "+json.dumps(evidence,sort_keys=True,ensure_ascii=False,default=str),flush=True)
    if not yes:
        raise AssertionError("L9_FAIL_"+name+" "+json.dumps(evidence,ensure_ascii=False,default=str)[:3900])
    print("PASS_L9_"+name,flush=True)

def sql(text):return l7.base.sql(text,db=DB)

def verify_source():
    meta=json.loads(META.read_text(encoding="utf-8"))
    raw=EXPORT.read_bytes()
    actual_sha=hashlib.sha256(raw).hexdigest()
    lines=raw.decode("utf-8").splitlines(keepends=True)
    parsed=[]
    for x in lines:
        if not x.endswith("\n") or x.endswith("\r\n"):
            raise AssertionError("L9_LINE_ENDING_OR_TERMINAL_LF_INVALID")
        entry=x[:-1].split("|",2)
        if len(entry)!=3 or not entry[0].startswith("K") or entry[1] not in ("ALLOW","BLOCK"):
            raise AssertionError("L9_ROW_FORMAT_INVALID "+repr(x[:110]))
        if "|" in entry[2] or "\n" in entry[2] or "\r" in entry[2]:
            raise AssertionError("L9_QUOTE_LINE_INVALID "+entry[0])
        parsed.append(tuple(entry))
    ids=[r[0] for r in parsed]
    by_verdict=Counter(r[1] for r in parsed)
    l6=json.loads(L6.read_text(encoding="utf-8"))
    l6_map={x["id"]:x["verdict"] for x in l6["entries"]}
    check("EXPORT_SHA256_154_VERDICTS_AND_L6_MODEL_NEUTRAL",
      actual_sha==meta["expected_sha256"]
      and actual_sha=="d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc"
      and raw.endswith(b"\n") and raw.count(b"\n")==154 and b"\r\n" not in raw
      and len(parsed)==154 and len(set(ids))==154
      and by_verdict=={"ALLOW":24,"BLOCK":130}
      and all(l6_map.get(i)==v for i,v,q in parsed)
      and meta["fixture_label"]=="REAL_REVIEW_PASS1_CHAT_EXPORT_NOT_NATIVE_IG_RECEIPT"
      and meta["reviewer_provenance"]=="REVIEWER_CHAT_EXPORT_MODEL_UNATTESTED"
      and l6["fixture_label"]=="REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED"
      and l6.get("reviewer_model_attestation")=="UNATTESTED"
      and meta["native_ig_receipt"] is False
      and meta["owner_profile_authority_attested"] is False,
      {"sha_expected":meta["expected_sha256"],"sha_actual":actual_sha,
       "file_bytes":len(raw),"rows":len(parsed),"unique":len(set(ids)),
       "verdicts":dict(by_verdict),"all_match_l6":all(l6_map.get(i)==v for i,v,q in parsed),
       "terminal_lf":raw.endswith(b"\n"),"model":"UNATTESTED",
       "fixture_label":meta["fixture_label"],"native_ig":False})
    return parsed,meta

def preflight(rows):
    # Frozen source: ONLY original fields; preserve actual proposal.operation,
    # rule_code, configuration; no patching source or quote to fit L7.
    cat=Counter()
    reasons={}
    full_literal=0
    for case_id,verdict,quote in rows:
        c=l7.CASES[case_id]
        frozen=json.dumps({"base_rule":c["base_rule"],"proposal":c["proposal"]},
                          sort_keys=True,ensure_ascii=False)
        if quote in frozen:full_literal+=1
        in_desc=(quote in c["base_rule"]["description"]
                 or quote in c["proposal"]["description"])
        long_enough=(len(quote)>=40 and quote==quote.strip()
                     and len(quote.split())>=6)
        # DIAGNOSTIC priority: out-of-description first, then length.
        # This is NOT L7 execution order: existing L7 checks length FIRST.
        reason=("L7_QUOTE_NOT_LITERAL_IN_FROZEN_TEXT" if not in_desc
                else "L7_QUOTE_EMPTY_OR_TRIVIAL" if not long_enough
                else "CAPTURABLE")
        reasons[case_id]=reason
        cat[reason]+=1
    return full_literal,reasons,cat

def route_one(case_id,verdict,quote):
    line=case_id+"|"+verdict+"|"+quote
    case=l7.CASES[case_id]
    source_sql=l7.seed(case_id,verdict=verdict,quote=quote)
    test_sql=f"""BEGIN;
    {source_sql}
    SELECT 'LINE|'||public.lf_rule_promotion_citation_line_check_v1(
       'PROM-L7',{lit(line)})::text;
    SET LOCAL ROLE lf_rule_citation_step70_bridge;
    SELECT 'CAPTURE|'||public.lf_rule_promotion_citation_record_v1(
       'PROM-L7',{lit(line)},'EXEC-PARENT-TEST-001')::text;
    RESET ROLE;
    SELECT 'GATE|'||public.lf_rule_promotion_citation_verify_v1('PROM-L7')::text;
    SELECT 'APPLY|'||public.lf_rule_promotion_apply_v1('PROM-L7')::text;
    SELECT 'TX|'||jsonb_build_object(
      'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
      'rule_state',(SELECT estado FROM lf_ops.reglas WHERE codigo={lit(case["base_rule"]["code"])}),
      'promotion_status',(SELECT status FROM public.lf_rule_promotion_v1
          WHERE promotion_id='PROM-L7'))::text;
    ROLLBACK;
    SELECT 'RB|'||jsonb_build_object(
      'captures',(SELECT count(*) FROM public.lf_rule_promotion_citation_capture_v1),
      'sources',(SELECT count(*) FROM public.lf_rule_promotion_citation_source_v1),
      'promotion_rows',(SELECT count(*) FROM public.lf_rule_promotion_v1
          WHERE promotion_id='PROM-L7'))::text;
    """
    return sql(test_sql)

def main():
    rows,meta=verify_source()
    full_literal,reasons,diag=preflight(rows)
    bad_allow=[case_id for case_id,v,q in rows if v=="ALLOW"
               and reasons[case_id]!="CAPTURABLE"]
    check("SOURCE_154_FULL_LITERAL_DIAGNOSTIC_106_22_26",
        full_literal==154
        and diag=={"CAPTURABLE":106,
                    "L7_QUOTE_NOT_LITERAL_IN_FROZEN_TEXT":22,
                    "L7_QUOTE_EMPTY_OR_TRIVIAL":26}
        and len(bad_allow)==2 and sorted(bad_allow)==["K00C8E827","K00CF241C"],
        {"literal_in_complete_frozen_json":full_literal,"diagnostic":dict(diag),
         "allow_needing_human_actual":bad_allow,
         "user_reported_allow_ids":["K00C8E827","K0113B7A3"],
         "ids_discrepancy":"K0113B7A3 is 40 chars and six words; K00CF241C is five words",
         "diagnostic_is_not_the_actual_gate_return_code":True})

    l7.DB=DB
    l7.l5.DB=DB
    l7.l5.l4d.DB=DB
    l7.l5.bootstrap()
    sql(l7.M7.read_text(encoding="utf-8"))
    sql(l7.M8.read_text(encoding="utf-8"))
    fn=sql("""SELECT 'MD5|'||jsonb_build_object(
      'l7_line_check',md5(pg_get_functiondef(
        'public.lf_rule_promotion_citation_line_check_v1(text,text)'::regprocedure)),
      'l7_capture_record',md5(pg_get_functiondef(
        'public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure)),
      'l7_capture_verify',md5(pg_get_functiondef(
        'public.lf_rule_promotion_citation_verify_v1(text)'::regprocedure)),
      'l7_blind_verify',md5(pg_get_functiondef(
        'public.lf_rule_promotion_blind_verdict_verify_v1(text)'::regprocedure)),
      'l7_apply',md5(pg_get_functiondef(
        'public.lf_rule_promotion_apply_v1(text)'::regprocedure)),
      'existing_ig_citations',md5(pg_get_functiondef(
        'public.lf_rule_promotion_ig_citation_verify_v1(text,jsonb,bigint,text,text,text,text,text)'::regprocedure)),
      'l8_reuse_guard',md5(pg_get_functiondef(
        'public.lf_rule_promotion_citation_scope_guard_v2()'::regprocedure)))::text;""")["MD5"]
    expected_md5={
      "l7_line_check":"f7bc0cf0564696a5ac6088fe85b0e957",
      "l7_capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
      "l7_capture_verify":"773a62783baa5edbe967200cac66b8c3",
      "l7_blind_verify":"f0aa0ae6130929d258266269def45bf9",
      "l7_apply":"86b0494984edf95cf0f9c0a0df67000b",
      "existing_ig_citations":"e76896fdbd36490ecbd6f20c64857a1c",
      "l8_reuse_guard":"522d12f0843be1da3c785cef3c0bf3fc"}
    check("EXISTING_L7_L8_GATE_MD5_UNCHANGED",fn==expected_md5,
      {"actual":fn,"expected":expected_md5,"migration_l9_applied":False})

    stats=Counter()
    captured_ids=[]
    human_ids=[]
    details=[]
    for index,(case_id,verdict,quote) in enumerate(rows,1):
        r=route_one(case_id,verdict,quote)
        source=r["SOURCE_PROM-L7"]
        line=r["LINE"]
        cap=r["CAPTURE"]
        gate=r["GATE"]
        apply=r["APPLY"]
        is_ready=reasons[case_id]=="CAPTURABLE"
        # Defensive gate facts (not semantic adequacy of the quoted assertion).
        if is_ready:
            assert source["status"]=="SOURCE_FROZEN",(case_id,source)
            assert line["status"]=="LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE",(case_id,line)
            assert cap["status"]=="CAPTURED_FOR_GATE_VERIFICATION",(case_id,cap)
            assert r["TX"]["captures"]==1,(case_id,r["TX"])
            captured_ids.append(case_id)
            stats["capturable"]+=1
            if verdict=="ALLOW":
                assert gate["status"]=="PROFILE_OWNER_REVIEW_ONLY",(case_id,gate)
                assert gate["next_actor"]=="PROFILE_OWNER",(case_id,gate)
                assert gate["promotable"] is False,(case_id,gate)
                stats["allow_profile_review_only"]+=1
            else:
                assert gate["status"]=="HUMAN_DECISION_REQUIRED",(case_id,gate)
                assert gate["blocking_code"]=="L7_BLOCK_QUOTE_VERIFIED_NO_PROMOTION",(case_id,gate)
                stats["block_with_valid_quote_human"]+=1
        else:
            # L7 checks minimum length BEFORE it checks source literalness;
            # all 48 are also short, including 22 config/CREATE excerpts.
            assert line["status"]=="HUMAN_DECISION_REQUIRED",(case_id,line)
            assert line["blocking_code"]=="L7_QUOTE_EMPTY_OR_TRIVIAL",(case_id,line)
            assert cap["status"]=="HUMAN_DECISION_REQUIRED",(case_id,cap)
            assert gate["status"]=="HUMAN_DECISION_REQUIRED",(case_id,gate)
            assert r["TX"]["captures"]==0,(case_id,r["TX"])
            human_ids.append(case_id)
            stats["uncapturable"]+=1
            stats["actual_gate_L7_QUOTE_EMPTY_OR_TRIVIAL"]+=1
            if verdict=="ALLOW":
                stats["allow_quote_blocked_to_human"]+=1
            else:
                stats["block_quote_blocked_to_human"]+=1
        assert apply["status"]=="BLOCKED",(case_id,apply)
        assert apply["blocking_code"]=="L7_EXACT_CITATION_NOT_CURRENT",(case_id,apply)
        assert r["TX"]["rule_state"]=="CANDIDATO",(case_id,r["TX"])
        assert r["RB"]=={"captures":0,"sources":0,"promotion_rows":0},(case_id,r["RB"])
        stats["rollback_unchanged"]+=1
        stats["no_auto_promotion"]+=1
        details.append({"i":index,"id":case_id,"verdict":verdict,
         "diagnostic":reasons[case_id],
         "source":source["status"],
         "line_code":line.get("blocking_code","LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE"),
         "capture":cap["status"],"gate":gate["status"],
         "gate_code":gate.get("blocking_code"),
         "apply":apply["blocking_code"],
         "rb":r["RB"]})
    want={"capturable":106,"uncapturable":48,"allow_profile_review_only":22,
          "block_with_valid_quote_human":84,"allow_quote_blocked_to_human":2,
          "block_quote_blocked_to_human":46,
          "actual_gate_L7_QUOTE_EMPTY_OR_TRIVIAL":48,
          "rollback_unchanged":154,"no_auto_promotion":154}
    check("REAL_EXPORT_154_NATIVE_L7_L8_STRUCTURAL_ROLLBACK",
      stats==want and len(details)==154 and len(set(captured_ids))==106
      and len(set(human_ids))==48,
      {"actual":dict(stats),"expected":want,
       "profile_owner_real_approval_attested":False,
       "model_identity":"UNATTESTED",
       "mock_step70_used":True,
       "native_ig_3682_receipt":False,
       "production_promotions":0,
       "all_cases_raw_sha256":hashlib.sha256(json.dumps(
            details,ensure_ascii=False,sort_keys=True).encode("utf-8")).hexdigest(),
       "details_first":details[:3],
       "details_allow_short": [d for d in details if d["id"] in ("K00C8E827","K00CF241C","K0113B7A3")],
       "details_create": [d for d in details if d["id"] in ("K00D56011","K01216EBE")],
       "details_last":details[-3:]})
    print("RAW_L9_ALL_154_CASE_RESULTS "+json.dumps(details,ensure_ascii=False,sort_keys=True),flush=True)
    print("LF_L9_CHAT_EXPORT_PG18_PASS checks=4 cases=154",flush=True)
    print("REVIEWER_CHAT_EXPORT_MODEL_UNATTESTED=true REAL_REVIEW_PASS1_CHAT_EXPORT_NOT_NATIVE_IG_RECEIPT=true",flush=True)
    print("REAL_OWNER_APPROVAL=UNVERIFIED NATIVE_IG_RECEIPT=UNVERIFIED APPLY_AUTOMATIC=0",flush=True)
    print("L9_DIAGNOSTIC_NOT_LITERAL=22 SHORT_LITERAL=26; L7_ACTUAL_PRIORITIZED_TRIVIAL=48; L7_GATE_UNCHANGED=true",flush=True)
if __name__=="__main__":
    main()
