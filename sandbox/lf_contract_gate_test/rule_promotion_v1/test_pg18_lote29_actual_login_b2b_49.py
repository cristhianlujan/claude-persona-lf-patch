#!/usr/bin/env python3
"""L29 amendment: ALL ACTUAL Login B2B rules from read-only Supabase snapshot,
copied into disposable PostgreSQL 18. Never writes/queries live Supabase.
No synthetic rules, approvals, identity or native production IG are fabricated.
"""
import json, hashlib, subprocess, os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DOC = ROOT / "docs/rule-quality-lote29"
SOURCE = DOC / "05_login_b2b_reglas_origen_49.json"
POLICY = DOC / "06_politicas_centrales_mfa_origen.json"
PROPOSALS = DOC / "07_login_b2b_matriz_diffs_51.json"
OUT = DOC / "l29_login_b2b_actual_runtime.json"
DB = "lf_3779_l29_actual_b2b_pg18"
STAGES = ["Router","Perfil","RUN","IG","Curator","Validator","Retorno perfil",
          "Ejecucion","Promocion","VIGENTE","Readback","Cierre"]
def quote(v):
    return "'" + str(v).replace("'","''") + "'"
def psql(query, db=DB, expect_fail=False):
    r=subprocess.run(["psql","-X","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
                     input=query,text=True,capture_output=True)
    if expect_fail:
        if r.returncode==0:
            raise AssertionError("EXPECTED_PG18_FAILURE_BUT_SUCCEEDED")
        return r.stderr
    if r.returncode:
        raise AssertionError("PG18_SQL_ERROR: " + r.stderr[-2500:])
    return r.stdout.strip()
def get_json(query):
    out=psql(query).splitlines()
    if not out:raise AssertionError("EMPTY_QUERY_JSON")
    return json.loads(out[-1])
def check(name,passed,detail):
    if not passed:raise AssertionError("L29_REAL_FAIL_"+name+" "+str(detail)[:1800])
    print("PASS_L29_REAL_"+name+" "+json.dumps(detail,sort_keys=True,ensure_ascii=False,default=str),flush=True)
def seed():
    src=json.loads(SOURCE.read_text(encoding="utf-8"))
    pol=json.loads(POLICY.read_text(encoding="utf-8"))
    prop=json.loads(PROPOSALS.read_text(encoding="utf-8"))
    codes=set(r["codigo"] for r in src["rows"])
    expected=set(src["requested_codes"])
    check("SOURCE_SET",len(codes)==49 and len(expected)==51 and set(src["missing_codes"])==expected-codes,
          {"found":len(codes),"requested":len(expected),"missing":src["missing_codes"]})
    check("STATUS_COUNTS",sum(r["estado"]=="VIGENTE" for r in src["rows"])==9
          and sum(r["estado"]=="CANDIDATO" for r in src["rows"])==40,
          {"vigente":9,"candidato":40})
    check("PROPOSAL_COUNTS",len(prop["rules"])==51
          and len(prop["central_policy_proposals"])==4
          and {r["codigo"] for r in prop["rules"]}==expected,
          {"all_rules":len(prop["rules"]),"policies":len(prop["central_policy_proposals"])})
    psql("DROP DATABASE IF EXISTS "+DB+" WITH (FORCE);",db="postgres")
    psql("CREATE DATABASE "+DB+";",db="postgres")
    schema="""CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA l29_actual;
CREATE TABLE l29_actual.source_rules(
 code text PRIMARY KEY, origin jsonb NOT NULL
);
CREATE TABLE l29_actual.policy_source(
 policy_id int PRIMARY KEY, origin jsonb NOT NULL
);
CREATE TABLE l29_actual.proposals(
 code text PRIMARY KEY, proposal jsonb NOT NULL
);
CREATE TABLE l29_actual.policy_draft(
 policy_id int PRIMARY KEY REFERENCES l29_actual.policy_source(policy_id),
 description text NOT NULL, policy_config jsonb NOT NULL,
 revisions int NOT NULL DEFAULT 0
);
CREATE TABLE l29_actual.draft(
 code text PRIMARY KEY REFERENCES l29_actual.source_rules(code),
 descripcion text NOT NULL, valor_config jsonb NOT NULL,
 revisions int NOT NULL DEFAULT 0
);
CREATE TABLE l29_actual.review_log(
 code text NOT NULL REFERENCES l29_actual.source_rules(code),
 vuelta int NOT NULL CHECK(vuelta IN (1,2)),
 verdict text NOT NULL CHECK(verdict IN ('DEVOLVER_CON_MOTIVO','ESCALAR_A_HUMANO','ACEPTAR_PRELIMINAR_SANDBOX')),
 reason text NOT NULL, source_sha256 text NOT NULL,
 readback_sha256 text NOT NULL,
 reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(code,vuelta)
);
CREATE FUNCTION l29_actual.deny_source_mutation_v1()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
 RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_REAL_SOURCE_IMMUTABLE';
END $f$;
CREATE TRIGGER l29_source_immutable BEFORE UPDATE OR DELETE ON l29_actual.source_rules
 FOR EACH ROW EXECUTE FUNCTION l29_actual.deny_source_mutation_v1();
CREATE TRIGGER l29_policy_immutable BEFORE UPDATE OR DELETE ON l29_actual.policy_source
 FOR EACH ROW EXECUTE FUNCTION l29_actual.deny_source_mutation_v1();
CREATE FUNCTION l29_actual.curator_v1(p_code text,p_vuelta integer)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE orig jsonb; proposal jsonb; current_d l29_actual.draft%ROWTYPE;
        v_verdict text; v_reason text; src_hash text; actual_hash text;
        n_dupe int;
BEGIN
 SELECT origin INTO orig FROM l29_actual.source_rules WHERE code=p_code;
 IF orig IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_REAL_RULE_SOURCE_MISSING';
 END IF;
 SELECT p.proposal INTO proposal FROM l29_actual.proposals p WHERE p.code=p_code;
 SELECT * INTO current_d FROM l29_actual.draft WHERE code=p_code;
 IF proposal IS NULL OR NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_REAL_PROPOSAL_OR_DRAFT_MISSING';
 END IF;
 SELECT count(*) INTO n_dupe FROM l29_actual.source_rules s
 WHERE s.code<>p_code
 AND lower(btrim(s.origin->>'descripcion'))=lower(btrim(orig->>'descripcion'))
 AND s.origin->'valor_config'=orig->'valor_config';
 src_hash:=orig->>'full_row_sha256';
 actual_hash:=encode(digest(convert_to(jsonb_build_object(
    'descripcion',current_d.descripcion,'valor_config',current_d.valor_config)::text,'UTF8'),'sha256'),'hex');
 IF n_dupe>0 THEN
   v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='DUPLICADO_LITERAL_ORIGEN';
 ELSIF current_d.descripcion IS DISTINCT FROM proposal->'despues'->>'descripcion'
    OR current_d.valor_config IS DISTINCT FROM proposal->'despues'->'valor_config' THEN
   v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='CORRECCION_PROPUESTA_NO_APLICADA_EN_SANDBOX';
 ELSIF coalesce((orig->>'pendiente_decision')::boolean,false)
    OR jsonb_array_length(proposal->'dueno_pendiente')>0 THEN
   v_verdict:='ESCALAR_A_HUMANO';v_reason:='DECISION_DUENO_FALTANTE';
 ELSIF jsonb_array_length(proposal->'externas_pendientes')>0 THEN
   v_verdict:='ESCALAR_A_HUMANO';v_reason:='DEPENDENCIA_EXTERNA_NO_VERIFICADA';
 ELSE
   v_verdict:='ACEPTAR_PRELIMINAR_SANDBOX';v_reason:='SIN_CONFLICTO_DETECTADO_PERO_SIN_FIRMA';
 END IF;
 INSERT INTO l29_actual.review_log(code,vuelta,verdict,reason,source_sha256,readback_sha256)
 VALUES(p_code,p_vuelta,v_verdict,v_reason,src_hash,actual_hash);
 RETURN jsonb_build_object('codigo',p_code,'vuelta',p_vuelta,'verdict',v_verdict,
   'razon',v_reason,'sha256_draft',actual_hash,'sha256_origen_fila',src_hash,
   'firmado',false,'aprobado',false,'promocion_autorizada',false);
END $f$;
CREATE FUNCTION l29_actual.apply_proposed_diff_v1(p_code text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE orig jsonb; prop jsonb; n int;
BEGIN
 SELECT origin INTO orig FROM l29_actual.source_rules WHERE code=p_code;
 SELECT proposal INTO prop FROM l29_actual.proposals WHERE code=p_code;
 IF orig IS NULL OR prop IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_REAL_SOURCE_OR_PROPOSAL_MISSING';
 END IF;
 IF prop->'antes'->>'descripcion' IS DISTINCT FROM orig->>'descripcion'
  OR prop->'antes'->'valor_config' IS DISTINCT FROM orig->'valor_config'
  OR jsonb_array_length(prop->'diff_literal')=0 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_REAL_PREIMAGE_OR_DIFF_INVALID';
 END IF;
 UPDATE l29_actual.draft SET descripcion=prop->'despues'->>'descripcion',
  valor_config=prop->'despues'->'valor_config',revisions=revisions+1
 WHERE code=p_code AND revisions=0;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L29_REAL_DUPLICATE_PATCH';
 END IF;
 RETURN jsonb_build_object('status','PATCHED_CANDIDATE_COPY_ONLY',
   'rule_code',p_code,'original_state',orig->>'estado',
   'original_written',false,'production_written',false);
END $f$;
CREATE FUNCTION l29_actual.promotion_gate_v1(p_code text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM l29_actual.source_rules WHERE code=p_code) THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_REAL_RULE_SOURCE_MISSING';
 END IF;
 RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L29_NO_FORMAL_OWNER_SIGNATURE';
END $f$;
"""
    psql(schema)
    rows_lit=quote(json.dumps(src["rows"],ensure_ascii=False,sort_keys=True))
    rule_lit=quote(json.dumps(prop["rules"],ensure_ascii=False,sort_keys=True))
    pol_lit=quote(json.dumps(pol["security_policies"],ensure_ascii=False,sort_keys=True))
    plit=quote(json.dumps(prop["central_policy_proposals"],ensure_ascii=False,sort_keys=True))
    psql("INSERT INTO l29_actual.source_rules(code,origin) "+
         "SELECT j->>'codigo',j FROM jsonb_array_elements("+rows_lit+"::jsonb) j;\n"+
         "INSERT INTO l29_actual.proposals(code,proposal) "+
         "SELECT j->>'codigo',j FROM jsonb_array_elements("+rule_lit+"::jsonb) j "+
         "WHERE j->>'estado_origen'<>'NO_ENCONTRADA';\n"+
         "INSERT INTO l29_actual.policy_source(policy_id,origin) "+
         "SELECT (j->>'security_policy_id')::int,j FROM jsonb_array_elements("+pol_lit+"::jsonb) j;\n"+
         "INSERT INTO l29_actual.draft(code,descripcion,valor_config) "+
         "SELECT code,origin->>'descripcion',origin->'valor_config' FROM l29_actual.source_rules;\n"+
         "INSERT INTO l29_actual.policy_draft(policy_id,description,policy_config) "+
         "SELECT policy_id,origin->>'description',origin->'policy_config' FROM l29_actual.policy_source;")
    actual_hash=psql("SELECT encode(digest(convert_to("+
        "coalesce(jsonb_agg(origin ORDER BY code),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex') "+
        "FROM l29_actual.source_rules;")
    check("SOURCE_SHA_MATCH",actual_hash==src["server_sha256"],
          {"live_SELECT_SHA256":src["server_sha256"],"pg18_loaded_SHA256":actual_hash})
    n=int(psql("SELECT count(*) FROM l29_actual.source_rules;"))
    check("SOURCE_CLONE_49",n==49,{"copied_real_rules":n})
    return src,pol,prop

def exercise(src,pol,prop):
    # First Curator turn on EVERY real code in one batch.
    get_json("SELECT jsonb_build_object('first_round',count(*)) FROM "+
      "(SELECT l29_actual.curator_v1(code,1) FROM l29_actual.source_rules ORDER BY code) x;")
    changed=[p["codigo"] for p in prop["rules"] if p["diff_literal"] and p["estado_origen"]!="NO_ENCONTRADA"]
    check("PATCH_COHORT",len(changed)==4,{"proposed_revision_codes":changed})
    for code in changed:
        p=get_json("SELECT l29_actual.apply_proposed_diff_v1("+quote(code)+")::text::jsonb;")
        check("PATCH_"+code,p["status"]=="PATCHED_CANDIDATE_COPY_ONLY",p)
    # Second Curator turn ONLY for actual candidates with a literal patch,
    # no redundant retry for external or owner decisions.
    get_json("SELECT jsonb_build_object('second_round',count(*)) FROM "+
      "(SELECT l29_actual.curator_v1(code,2) FROM l29_actual.draft "+
      "WHERE revisions=1 ORDER BY code) x;")
    log=get_json("SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY code,vuelta),'[]'::jsonb) FROM "+
      "(SELECT code,vuelta,verdict,reason,source_sha256,readback_sha256 FROM l29_actual.review_log) t;")
    assert len(log)==53,(len(log),len(changed))
    results=[]
    for entry in prop["rules"]:
        code=entry["codigo"];r=[x for x in log if x["code"]==code]
        final=r[-1] if r else None
        orig=entry["estado_origen"]
        results.append({
          "codigo":code,"estado_origen":orig,"hallazgo":entry["hallazgo"],
          "diff_count":len(entry["diff_literal"]),"vueltas":len(r),
          "devoluciones":sum(x["verdict"]=="DEVOLVER_CON_MOTIVO" for x in r),
          "verdictos":[{"vuelta":x["vuelta"],"verdict":x["verdict"],"razon":x["reason"]} for x in r],
          "final_curator":final["verdict"] if final else "NO_EVALUABLE_SIN_FUENTE",
          "cierra_sin_intervencion_humana_en_sandbox":bool(final and final["verdict"]=="ACEPTAR_PRELIMINAR_SANDBOX"),
          "dueno_pendiente":entry["dueno_pendiente"],
          "externas_pendientes":entry["externas_pendientes"],
          "promocion_autorizada":False,"firma_formal":False,
          "source_sha256":entry.get("source_full_row_sha256")
        })
    assert len(results)==51
    for x in results:
        if x["estado_origen"]!="NO_ENCONTRADA" and not (1<=x["vueltas"]<=2):
            raise AssertionError("UNMEASURED_RULE "+x["codigo"])
        if x["estado_origen"]=="NO_ENCONTRADA" and x["vueltas"]!=0:
            raise AssertionError("FAKE_RULE_CREATED")
    initial={v:sum(x["verdictos"][0]["verdict"]==v for x in results if x["vueltas"]) for v in
      ["ACEPTAR_PRELIMINAR_SANDBOX","DEVOLVER_CON_MOTIVO","ESCALAR_A_HUMANO"]}
    final={v:sum(x["final_curator"]==v for x in results) for v in
      ["ACEPTAR_PRELIMINAR_SANDBOX","DEVOLVER_CON_MOTIVO","ESCALAR_A_HUMANO","NO_EVALUABLE_SIN_FUENTE"]}
    check("CURATOR_ALL_49",sum(initial.values())==49,{"initial":initial,"final":final})
    check("NO_SPURIOUS_PATCH_ROUNDS",len(log)==49+len(changed),
          {"review_rounds":len(log),"rules":49,"revised":len(changed)})
    unmodified=int(psql("SELECT count(*) FROM l29_actual.source_rules s "+
      "JOIN l29_actual.proposals p ON p.code=s.code "+
      "WHERE p.proposal->'antes'->>'descripcion'=s.origin->>'descripcion' "+
      "AND p.proposal->'antes'->'valor_config'=s.origin->'valor_config';"))
    check("SOURCE_ORIGINAL_UNTOUCHED",unmodified==49,{"matching_live_preimage":unmodified})
    # Central policy proposals are tested as distinct drafts; no source policy writes.
    p_diff={p["policy_id"]:p for p in prop["central_policy_proposals"]}
    # Four REAL central policy source copies; apply only to policy_draft in PG18.
    for pid,p in sorted(p_diff.items()):
        d=p["despues"]
        sql_update=("UPDATE l29_actual.policy_draft SET description="+quote(d["description"])+
          ",policy_config="+quote(json.dumps(d["policy_config"],ensure_ascii=False,sort_keys=True))+
          "::jsonb,revisions=revisions+1 WHERE policy_id="+str(pid)+" AND revisions=0;")
        psql(sql_update)
    policy_read=get_json("SELECT jsonb_build_object("+
      "'draft_revised',count(*) FILTER(WHERE d.revisions=1),"+
      "'source_rows_unchanged',count(*) FILTER(WHERE s.origin->>'description'=p.proposal->'antes'->>'description'"+
      " AND s.origin->'policy_config'=p.proposal->'antes'->'policy_config'),"+
      "'draft_matches_proposal',count(*) FILTER(WHERE d.description=p.proposal->'despues'->>'description'"+
      " AND d.policy_config=p.proposal->'despues'->'policy_config'))"+
      " FROM l29_actual.policy_draft d JOIN l29_actual.policy_source s USING(policy_id)"+
      " JOIN (SELECT (j->>'policy_id')::int policy_id,j proposal"+
      " FROM jsonb_array_elements("+quote(json.dumps(prop["central_policy_proposals"],ensure_ascii=False,sort_keys=True))+
      "::jsonb) j) p USING(policy_id);")
    check("FOUR_POLICY_DRAFTS_ONLY",policy_read=={
      "draft_revised":4,"source_rows_unchanged":4,"draft_matches_proposal":4},policy_read)
    check("CENTRAL_POLICY_ONLY_THRESHOLDS",p_diff[3]["despues"]["policy_config"]["mfa_inactivity_trigger_days"]==30
      and p_diff[3]["despues"]["policy_config"]["mfa_password_unchanged_months"]==3
      and p_diff[20]["despues"]["policy_config"]["assisted_recovery_wait_hours"]==48
      and all("mfa_inactivity_trigger_days" not in json.dumps(r["despues"]["valor_config"]) and
        "mfa_password_unchanged_months" not in json.dumps(r["despues"]["valor_config"])
        for r in prop["rules"] if r["despues"] is not None),
      {"policy_id_3":{"inactivity_days":30,"password_unchanged_calendar_months":3},
       "policy_id_20":{"wait_hours":48},"rules_numeric_mfa_thresholds_embedded":0})
    # No duplicate literal among actual rules; arbitrary guesses are not counted.
    duplicate_count=int(psql("SELECT count(*) FROM l29_actual.source_rules a "+
      "JOIN l29_actual.source_rules b ON a.code<b.code AND "+
      "lower(btrim(a.origin->>'descripcion'))=lower(btrim(b.origin->>'descripcion')) "+
      "AND a.origin->'valor_config'=b.origin->'valor_config';"))
    check("NO_LITERAL_DUPLICATES",duplicate_count==0,{"exact_duplicate_pairs":duplicate_count})
    # Security negatives, no simulated formal approval.
    msg=psql("UPDATE l29_actual.source_rules SET origin='{}'::jsonb "+
      "WHERE code='B2B-RULE-AUTH-018';",expect_fail=True)
    check("IMMUTABLE_REAL_ORIGIN","BLOCK_L29_REAL_SOURCE_IMMUTABLE" in msg,
      {"error":"BLOCK_L29_REAL_SOURCE_IMMUTABLE"})
    msg=psql("SELECT l29_actual.promotion_gate_v1('B2B-RULE-AUTH-018');",expect_fail=True)
    check("NO_UNSIGNED_PROMOTION","BLOCK_L29_NO_FORMAL_OWNER_SIGNATURE" in msg,
      {"error":"BLOCK_L29_NO_FORMAL_OWNER_SIGNATURE"})
    msg=psql("SELECT l29_actual.promotion_gate_v1('B2B-RULE-AUTH-009');",expect_fail=True)
    check("MISSING_SOURCE_FAIL_CLOSED","BLOCK_L29_REAL_RULE_SOURCE_MISSING" in msg,
      {"error":"BLOCK_L29_REAL_RULE_SOURCE_MISSING"})
    msg=psql("SELECT l29_actual.apply_proposed_diff_v1('B2B-RULE-AUTH-018');",expect_fail=True)
    check("NO_DUPLICATE_APPLY","BLOCK_L29_REAL_DUPLICATE_PATCH" in msg,
      {"error":"BLOCK_L29_REAL_DUPLICATE_PATCH"})
    # 12-stage board for ALL 49 actual rule reviews, NOT the native Router E2E.
    board=[]
    for rule in results:
        if rule["estado_origen"]=="NO_ENCONTRADA":continue
        for stage in STAGES:
            status=("REAL_EN_SANDBOX" if stage in ("Curator","Validator","Readback") else
             "SINTETICO" if stage=="IG" or (stage=="Ejecucion" and rule["diff_count"]>0)
             else "NO_PROBADO")
            board.append({"codigo":rule["codigo"],"etapa":stage,"estado":status,
             "evidencia":"PG18 clone + deterministic Curator" if status=="REAL_EN_SANDBOX"
              else "Propuesta de revisión sin handoff nativo" if status=="SINTETICO"
              else "No se ejecutó fase oficial ni promoción/firma"})
    counts={st:sum(x["estado"]==st for x in board) for st in ["REAL_EN_SANDBOX","SINTETICO","NO_PROBADO"]}
    check("BOARD_49_BY_12",len(board)==588 and sum(counts.values())==588,
      {"cells":len(board),"status_counts":counts})
    checks={
      "first_pass":initial,"final":final,
      "total_returned":sum(x["devoluciones"] for x in results),
      "rules_with_one_revision":len(changed),
      "without_human_sandbox":sum(x["cierra_sin_intervencion_humana_en_sandbox"] for x in results),
      "owner_blocked":sum(bool(x["dueno_pendiente"]) for x in results),
      "external_blocked":sum(bool(x["externas_pendientes"]) for x in results),
      "missing":sum(x["estado_origen"]=="NO_ENCONTRADA" for x in results),
      "formal_approvals":0,"promoted":0,"native_ig_executed":False
    }
    report={"schema_version":"LF_L29_REAL_B2B_49_RULES_REVIEW_V1",
     "source_server_sha256":src["server_sha256"],"rules_requested":51,"rules_read":49,
     "policy_read":len(pol["security_policies"]),"policy_proposals":4,
     "source_immutable":True,"production_writes":0,"run_modifications":0,
     "curator_type":"DETERMINISTIC_SQL_SAME_GPT6_MODEL_NOT_INDEPENDENT",
     "jwt":"NOT_USED_FOR_REAL_IDENTITY_AUTH_HISTORICAL_L29_HMAC_FIXTURE_ONLY",
     "owner_signatures":0,"production":"NO_GO_UNVERIFIED","blockers_closed":0,"blockers_total":14,
     "results":results,"metrics":checks,"board":board,"board_counts":counts,
     "historical_l26":{"real":21,"total":36,"comparability":"DIFFERENT_COHORT_NOT_DIRECTLY_COMPARABLE"},
     "frozen_gates":{"source_files_untouched":True,
      "historical_l29_pg18_md5":{"apply":"86b0494984edf95cf0f9c0a0df67000b",
       "capture_record":"89cbfac4162dbc9f8ecca59f2c3ab4c3",
       "citation_verify":"773a62783baa5edbe967200cac66b8c3",
       "l8_guard":"522d12f0843be1da3c785cef3c0bf3fc"},
      "md5_reexecuted_in_actual_rules_review":False},
     "policy_change_only_sandbox":True,"policy_draft_patched":4,
     "scope":"CURATOR_AND_DIFF_COPY_PG18_NOT_NATIVE_IG_E2E",
     "readback_status":"ORIGINAL_49_PRESERVED"}
    OUT.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2,default=str)+"\n",encoding="utf-8")
    print("L29_ACTUAL_REPORT_SHA256 "+hashlib.sha256(OUT.read_bytes()).hexdigest(),flush=True)
    print("L29_ACTUAL_COMPLETE "+json.dumps(checks,sort_keys=True),flush=True)
    return report

def main():
    src,pol,prop=seed()
    exercise(src,pol,prop)
    psql("DROP DATABASE IF EXISTS "+DB+" WITH (FORCE);",db="postgres")
if __name__=="__main__":main()
