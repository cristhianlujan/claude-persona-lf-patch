#!/usr/bin/env python3
"""Client REC_001 limited-access decision: PG17.6/18.7 SQL cases and policy INSERT SHA rollback.
Isolated Docker only; never connects to Supabase. Contract CANDIDATO, not production.
"""
from __future__ import annotations
import copy,json,shutil,subprocess,time,unittest,uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
DATA=HERE/"fixtures/lf_other_auth_screens_20261113_source_patch.json"
CODE="SEC-CLIENT-RECOVERY-LIMITED-ACCESS"
POLICY_HASH=("SELECT encode(pg_catalog.sha256(convert_to(coalesce((SELECT to_jsonb(p)::text "
             "FROM lf_ops.politicas_seguridad p WHERE p.policy_code='"+CODE+"'),'null'),'UTF8')),'hex');")
def q(v): return "'"+str(v).replace("'","''")+"'"
def j(v): return q(json.dumps(v,ensure_ascii=False,separators=(",",":")))+"::jsonb"
FUNC=r"""
CREATE FUNCTION lf_client.fn_recovery_limited_permission_test_v1(
 p_case jsonb,p_action text,p_now timestamptz
) RETURNS text LANGUAGE plpgsql STABLE AS $lf$
DECLARE cfg jsonb; expected_channel text; n int; distinct_n int;
 approval_at timestamptz; delivered_at timestamptz; starts_at timestamptz;
BEGIN
 SELECT policy_config INTO cfg FROM lf_ops.politicas_seguridad
 WHERE policy_code='SEC-CLIENT-RECOVERY-LIMITED-ACCESS' AND status='CANDIDATO';
 IF cfg IS NULL OR cfg->>'schema_version'<>'LF_CLIENT_RECOVERY_LIMITED_ACCESS_POLICY_V1' THEN RETURN 'BLOCKED'; END IF;
 IF p_case->>'owner_objection_verified'='true' THEN RETURN 'REVOKED'; END IF;
 IF p_case->>'case_state'<>'APPROVED' THEN RETURN 'BLOCKED'; END IF;
 IF p_case->>'scanned_dni_verified'<>'true' THEN RETURN 'BLOCKED'; END IF;
 IF p_case->>'delivery'<>'DELIVERED' OR p_case->>'previous_channel_verified'<>'true' THEN RETURN 'BLOCKED'; END IF;
 expected_channel := cfg->'notification_channel_for_change'->>(p_case->>'change_type');
 IF expected_channel IS NULL OR expected_channel<>p_case->>'notice_channel' THEN RETURN 'BLOCKED'; END IF;
 IF (cfg->>'approvers_required')::int NOT IN (1,2) THEN RETURN 'BLOCKED'; END IF;
 IF jsonb_typeof(p_case->'approvers')<>'array' THEN RETURN 'BLOCKED'; END IF;
 SELECT count(*),count(DISTINCT a.value)
 INTO n,distinct_n FROM jsonb_array_elements_text(p_case->'approvers') AS a(value);
 IF n <> distinct_n OR n < (cfg->>'approvers_required')::int THEN RETURN 'BLOCKED'; END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(p_case->'approvers') a(value)
            WHERE a.value=p_case->>'creator_id') THEN RETURN 'BLOCKED'; END IF;
 IF p_case->>'approval_completed_at' IS NULL OR p_case->>'delivered_at' IS NULL THEN RETURN 'BLOCKED'; END IF;
 approval_at := (p_case->>'approval_completed_at')::timestamptz;
 delivered_at := (p_case->>'delivered_at')::timestamptz;
 starts_at := greatest(approval_at,delivered_at);
 IF p_now < starts_at THEN RETURN 'BLOCKED'; END IF;
 IF p_action='SESSION_OPEN' THEN RETURN 'LIMITED_ACTIVE'; END IF;
 IF p_case->>'session_mode'<>'LIMITED_ACTIVE' THEN RETURN 'BLOCKED'; END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(cfg->'limited_allowed_actions') a(value)
            WHERE a.value=p_action) THEN
   IF p_action IN ('PAY_EXISTING_INSTALLMENT','PAY_EXISTING_DEBT_SINGLE')
      AND p_case->>'existing_debt'<>'true' THEN RETURN 'DENIED'; END IF;
   RETURN 'ALLOWED';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(cfg->'limited_blocked_actions') a(value)
            WHERE a.value=p_action) THEN
   IF p_now < starts_at + make_interval(hours=>(cfg->>'security_window_hours')::int) THEN
       RETURN 'DENIED_WINDOW';
   END IF;
   RETURN 'WINDOW_EXPIRED_REAUTH_REQUIRED';
 END IF;
 RETURN 'DENIED';
END;
$lf$;
"""
class ClientRecoveryLimitedPolicy(unittest.TestCase):
 def exercise(self,image,version):
    self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
    doc=json.loads(DATA.read_text(encoding="utf8"))
    proposal=doc["policy_proposal"]
    self.assertEqual(proposal["source_live_match_count"],0)
    self.assertTrue(proposal["source_live_absence_verified"])
    policy=proposal["record"]
    self.assertEqual(policy["status"],"CANDIDATO")
    cfg=policy["policy_config"]
    self.assertFalse(doc["owner_decision"]["identity_verified"])
    self.assertTrue(doc["owner_decision"]["supersedes_client_wait_48h_for_entry"])
    self.assertEqual(cfg["approvers_allowed"],[1,2])
    self.assertIn("SAVED_PAYMENT_METHOD_CHANGE",cfg["limited_blocked_actions"])
    self.assertTrue(cfg["alternate_contact_optional_for_onboarding"])
    cid="lf-rec2338-"+uuid.uuid4().hex[:10]
    start=subprocess.run(["docker","run","--rm","-d","--name",cid,"-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
      capture_output=True,text=True,timeout=240)
    self.assertEqual(start.returncode,0,start.stderr[-1600:])
    try:
     def sql(script,timeout=180):
      p=subprocess.run(["docker","exec","-i",cid,"psql","-X","-q","-t","-A",
         "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],input=script,text=True,
         capture_output=True,timeout=timeout)
      self.assertEqual(p.returncode,0,p.stderr[-2200:]+"\nSQL_HEAD:"+script[:400])
      return [v.strip() for v in p.stdout.splitlines() if v.strip()]
     for _ in range(60):
      if subprocess.run(["docker","exec",cid,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0: break
      time.sleep(1)
     else: self.fail("PG_NOT_READY")
     self.assertEqual(sql("SHOW server_version_num;"),[version])
     sql("CREATE SCHEMA lf_ops;CREATE SCHEMA lf_client;"+
      "CREATE TABLE lf_ops.politicas_seguridad("
      "security_policy_id bigint,policy_code text,category text,description text,"
      "policy_config jsonb,enforcement_level text,status text);"+FUNC)
     before=sql(POLICY_HASH)[0]
     source=policy.copy()
     fields=("security_policy_id","policy_code","category","description","policy_config","enforcement_level","status")
     insert=("INSERT INTO lf_ops.politicas_seguridad("+",".join(fields)+") VALUES ("+
        ",".join(j(source[k]) if k=="policy_config" else str(source[k]) if k=="security_policy_id"
                 else q(source[k]) for k in fields)+");")
     good={"case_state":"APPROVED","scanned_dni_verified":True,"change_type":"PHONE",
           "notice_channel":"PREVIOUS_VERIFIED_EMAIL","previous_channel_verified":True,
           "delivery":"DELIVERED","creator_id":"agentA","approvers":["agentB"],
           "approval_completed_at":"2026-11-14T04:00:00+00:00",
           "delivered_at":"2026-11-14T04:02:00+00:00",
           "owner_objection_verified":False,"session_mode":"LIMITED_ACTIVE","existing_debt":True}
     action_time="2026-11-14T04:03:00+00:00"
     cases=[]
     def add(label,payload,action,expected,when=action_time):
      cases.append((label,payload,action,expected,when))
     add("NOTICE_DELIVERED_LIMITED_OK",good,"SESSION_OPEN","LIMITED_ACTIVE")
     failed={**good,"delivery":"BOUNCED"}
     add("NOTICE_FAILED_BLOCKED",failed,"SESSION_OPEN","BLOCKED")
     add("BLOCKED_ACTION_WITHIN_WINDOW",good,"EMAIL_CHANGE","DENIED_WINDOW")
     add("ALLOW_PAYMENT_EXISTING_INSTALLMENT",good,"PAY_EXISTING_INSTALLMENT","ALLOWED")
     add("ALLOW_SINGLE_EXISTING_DEBT",good,"PAY_EXISTING_DEBT_SINGLE","ALLOWED")
     add("ALLOW_VIEW_DEBT",good,"DEBT_READ","ALLOWED")
     add("ALLOW_VIEW_INSTALLMENTS",good,"INSTALLMENTS_READ","ALLOWED")
     add("OWNER_OBJECTION_REVOKED",{**good,"owner_objection_verified":True},"SESSION_OPEN","REVOKED")
     add("WRONG_CHANNEL_BLOCKED",{**good,"notice_channel":"PREVIOUS_VERIFIED_PHONE"},"SESSION_OPEN","BLOCKED")
     add("NOT_VERIFIED_CHANNEL_BLOCKED",{**good,"previous_channel_verified":False},"SESSION_OPEN","BLOCKED")
     add("CONTACT_NOT_REQUIRED_ONBOARDING",good,"SESSION_OPEN","LIMITED_ACTIVE")
     add("NEW_OFFER_DENIED",good,"ACCEPT_NEW_OFFER","DENIED_WINDOW")
     add("NEW_PLAN_DENIED",good,"ACCEPT_NEW_INSTALLMENT_PLAN","DENIED_WINDOW")
     add("LETTER_REQUEST_DENIED",good,"NO_DEBT_LETTER_REQUEST","DENIED_WINDOW")
     add("LETTER_DELIVERY_DENIED",good,"NO_DEBT_LETTER_DELIVERY","DENIED_WINDOW")
     add("SAVED_PAYMENT_METHOD_CHANGE_DENIED",good,"SAVED_PAYMENT_METHOD_CHANGE","DENIED_WINDOW")
     add("PASSWORD_CHANGE_DENIED",good,"PASSWORD_CHANGE","DENIED_WINDOW")
     add("PHONE_CHANGE_DENIED",good,"PHONE_CHANGE","DENIED_WINDOW")
     add("UNKNOWN_ACTION_DENIED",good,"ADMIN_PRIVILEGE_ESCALATION","DENIED")
     add("UNAPPROVED_CASE_BLOCKED",{**good,"case_state":"PENDING"},"SESSION_OPEN","BLOCKED")
     add("SAME_CREATOR_AND_APPROVER_BLOCKED",{**good,"approvers":["agentA"]},"SESSION_OPEN","BLOCKED")
     add("WINDOW_FINISH_REQUIRES_REAUTH",good,"EMAIL_CHANGE","WINDOW_EXPIRED_REAUTH_REQUIRED",
         "2026-11-16T04:04:00+00:00")
     def stmt(label,case,action,when):
      return ("SELECT "+q(label)+"||'|'||lf_client.fn_recovery_limited_permission_test_v1("+
          j(case)+","+q(action)+","+q(when)+"::timestamptz);")
     tx=["BEGIN;",insert,"SELECT 'DURING_SHA|'||("+POLICY_HASH.rstrip(";")+");"]
     for name,case,action,expected,when in cases:
      tx.append(stmt(name,case,action,when))
     # The config must be honored if owner changes 1 to 2 approvers.
     tx.append("UPDATE lf_ops.politicas_seguridad SET policy_config=jsonb_set(policy_config,"+
        "'{approvers_required}','2'::jsonb) WHERE policy_code="+q(CODE)+";")
     tx.append(stmt("TWO_REQUIRED_ONE_GIVEN",good,"SESSION_OPEN",action_time))
     tx.append(stmt("TWO_REQUIRED_TWO_DISTINCT",{**good,"approvers":["agentB","agentC"]},"SESSION_OPEN",action_time))
     tx.append("ROLLBACK;")
     tx.append("SELECT 'AFTER_SHA|'||("+POLICY_HASH.rstrip(";")+");")
     tx.append("SELECT 'POLICY_ROWS_AFTER|'||count(*) FROM lf_ops.politicas_seguridad WHERE policy_code="+q(CODE)+";")
     rows=sql("\n".join(tx))
     during=[x.split("|",1)[1] for x in rows if x.startswith("DURING_SHA|")]
     after=[x.split("|",1)[1] for x in rows if x.startswith("AFTER_SHA|")]
     self.assertEqual(len(during),1)
     self.assertEqual(after,[before])
     self.assertNotEqual(during[0],before)
     self.assertEqual(len(during[0]),64)
     self.assertIn("POLICY_ROWS_AFTER|0",rows)
     outcomes=dict(x.split("|",1) for x in rows if "|" in x and not x.startswith(("DURING_SHA|","AFTER_SHA|","POLICY_ROWS_AFTER|")))
     self.assertEqual(len(outcomes),len(cases)+2)
     for name,payload,action,expected,when in cases:
      self.assertEqual(outcomes[name],expected,name)
      print("SCENARIO|"+image+"|"+name+"|"+expected+"|PASS",flush=True)
     self.assertEqual(outcomes["TWO_REQUIRED_ONE_GIVEN"],"BLOCKED")
     self.assertEqual(outcomes["TWO_REQUIRED_TWO_DISTINCT"],"LIMITED_ACTIVE")
     print("SHA_POLICY_INSERT|"+image+"|"+CODE+"|"+before+"|"+during[0]+"|"+after[0]+"|PASS",flush=True)
     print("PASS_CLIENT_RECOVERY_LIMITED_5_CORE_CASES_POLICY_ONLY_SHA_ROLLBACK_"+image.replace(":","_"),flush=True)
    finally:
     subprocess.run(["docker","rm","-f",cid],capture_output=True,text=True,timeout=60)
 def test_pg176(self):self.exercise("postgres:17.6","170006")
 def test_pg187(self):self.exercise("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
