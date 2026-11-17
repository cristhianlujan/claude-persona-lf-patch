"""PG17.6 / PG18.7 isolated transaction; Docker, no LF credentials."""
import re,shutil,subprocess,time,unittest,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261117000100_lf_owner_chat_verified_receipt_guard_v1.sql"
SETUP=r"""
CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA private; CREATE SCHEMA programacion; CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE FUNCTION programacion.fn_v09_canonical_jsonb_text(j jsonb)
RETURNS text LANGUAGE SQL IMMUTABLE AS $$ SELECT j::text $$;
CREATE FUNCTION programacion.fn_v09_sha256_jsonb(j jsonb)
RETURNS text LANGUAGE SQL IMMUTABLE AS $$
 SELECT encode(extensions.digest(convert_to(programacion.fn_v09_canonical_jsonb_text(j),'UTF8'),'sha256'),'hex') $$;
CREATE TABLE public.lf_rule_promotion_v1(
 promotion_id text PRIMARY KEY,rule_code text,request_execution_id text,
 request_snapshot_sha256 text,status text DEFAULT 'PENDING',decided_by text);
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(p_type text,p_code text)
RETURNS text LANGUAGE SQL STABLE AS $$ SELECT repeat('a',64) $$;
CREATE FUNCTION public.lf_rule_promotion_decide_v1(p_id text,p_decision text,p_by text,p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.lf_owner_chat_promotion_leases_v1 l
 JOIN private.lf_owner_chat_orders_v1 o ON o.order_id=l.order_id
 WHERE l.promotion_id=p_id AND l.tx_id=pg_current_xact_id()::text
 AND o.consumed_by='PROMOTION_BATCH_TX:'||pg_current_xact_id()::text)
 THEN RETURN jsonb_build_object('status','BLOCKED'); END IF;
 UPDATE public.lf_rule_promotion_v1 SET status='APPROVED',decided_by=p_by
 WHERE promotion_id=p_id AND status='PENDING';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED'); END IF;
 RETURN jsonb_build_object('status','APPROVED');
END $f$;
CREATE FUNCTION public.lf_rule_promotion_apply_v1(p_id text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
BEGIN
 UPDATE public.lf_rule_promotion_v1 SET status='APPLIED'
 WHERE promotion_id=p_id AND status='APPROVED';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED'); END IF;
 RETURN jsonb_build_object('status','APPLIED');
END $f$;
"""
ASSERTIONS=r"""
DO $test$
DECLARE sc jsonb;r jsonb;oid uuid;v_codes jsonb;v_snap text;v_n integer;lit text;
BEGIN
 sc:=jsonb_build_object('action','MERGE_GOVERNANCE_PR',
 'repository','cristhianlujan/claude-persona-lf-patch',
 'pr_number',4063,'head_sha',repeat('f',40));
 r:=private.fn_lf_owner_chat_consume_v1(gen_random_uuid(),
  'MERGE_GOVERNANCE_PR',sc,'fixture-owner-123','TRAIN-TEST-00000001');
 IF r->>'code'<>'NO_OWNER_CHAT_ORDER' THEN RAISE EXCEPTION 'NEG_ABSENT:%',r; END IF;
 lit:='APRUEBO '||left(programacion.fn_v09_sha256_jsonb(sc),12)||' '||programacion.fn_v09_canonical_jsonb_text(sc);
 r:=private.fn_lf_owner_chat_register_v1('fixture-chat-123456','fixture-msg-merge-01',
 'CHAT_ORCHESTRATOR_USER_TURN','fixture-owner-123','fixture-proposer-123',
 'fixture-recorder-123',clock_timestamp(),lit,sc);
 oid:=(r->>'order_id')::uuid;
 r:=private.fn_lf_owner_chat_train_merge_gate_v1(oid,
 'cristhianlujan/claude-persona-lf-patch',4063,repeat('e',40),
 'fixture-owner-123','TRAIN-TEST-00000001');
 IF r->>'status'<>'BLOCKED' THEN RAISE EXCEPTION 'NEG_HEAD:%',r; END IF;
 r:=private.fn_lf_owner_chat_train_merge_gate_v1(oid,
 'cristhianlujan/claude-persona-lf-patch',4063,repeat('f',40),
 'fixture-owner-123','TRAIN-TEST-00000001');
 IF r->>'status'<>'AUTHORIZED_FOR_TRAIN_ONLY' THEN RAISE EXCEPTION 'POS_MERGE:%',r; END IF;
 r:=private.fn_lf_owner_chat_train_merge_gate_v1(oid,
 'cristhianlujan/claude-persona-lf-patch',4063,repeat('f',40),
 'fixture-owner-123','TRAIN-TEST-00000001');
 IF r->>'status'<>'BLOCKED' THEN RAISE EXCEPTION 'NEG_REPLAY:%',r; END IF;
 r:=private.fn_lf_owner_chat_register_v1('fixture-chat-123456','fixture-msg-revoke-01',
 'CHAT_ORCHESTRATOR_USER_TURN','fixture-owner-123','fixture-proposer-123',
 'fixture-recorder-123',clock_timestamp(),lit,sc);
 oid:=(r->>'order_id')::uuid;
 r:=private.fn_lf_owner_chat_revoke_v1(oid,'fixture-msg-revoke-02',
 'fixture-owner-123','fixture-only');
 IF r->>'status'<>'REVOKED' THEN RAISE EXCEPTION 'NEG_REVOKE_SETUP:%',r; END IF;
 r:=private.fn_lf_owner_chat_consume_v1(oid,'MERGE_GOVERNANCE_PR',sc,
 'fixture-owner-123','TRAIN-TEST-00000001');
 IF r->>'code'<>'CHAT_ORDER_REVOKED' THEN RAISE EXCEPTION 'NEG_REVOKED:%',r; END IF;
 r:=private.fn_lf_owner_chat_register_v1('fixture-chat-123456','fixture-msg-expired01',
 'CHAT_ORCHESTRATOR_USER_TURN','fixture-owner-123','fixture-proposer-123',
 'fixture-recorder-123',clock_timestamp(),lit,sc);
 oid:=(r->>'order_id')::uuid;
 UPDATE private.lf_owner_chat_orders_v1 SET sent_at=transaction_timestamp()-interval '20 minutes',
 expires_at=transaction_timestamp()-interval '5 minutes' WHERE order_id=oid;
 r:=private.fn_lf_owner_chat_consume_v1(oid,'MERGE_GOVERNANCE_PR',sc,
 'fixture-owner-123','TRAIN-TEST-00000001');
 IF r->>'code'<>'CHAT_ORDER_EXPIRED' THEN RAISE EXCEPTION 'NEG_EXPIRED:%',r; END IF;
 BEGIN
  PERFORM private.fn_lf_owner_chat_register_v1('fixture-chat-123456','fixture-msg-model-0001',
   'CHAT_ORCHESTRATOR_USER_TURN','fixture-owner-123','same-proposer-123',
   'same-proposer-123',clock_timestamp(),lit,sc);
  RAISE EXCEPTION 'NEG_SELF_APPROVAL_NOT_REJECTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='NEG_SELF_APPROVAL_NOT_REJECTED' THEN RAISE; END IF;
  IF SQLERRM NOT LIKE 'CHAT_OWNER_ORCHESTRATOR_EVENT_OR_SEPARATION_INVALID%'
   THEN RAISE EXCEPTION 'NEG_SELF_APPROVAL_WRONG_BLOCK:%',SQLERRM; END IF;
 END;
 INSERT INTO public.lf_rule_promotion_v1(promotion_id,rule_code,request_execution_id,request_snapshot_sha256)
 SELECT 'FIXTURE-PROM-'||lpad(n::text,3,'0'),'RULE-'||lpad(n::text,3,'0'),
 'EXEC-FIXTURE-1234567890',repeat('a',64) FROM generate_series(1,22)n;
 SELECT to_jsonb(array_agg(rule_code ORDER BY rule_code)),
  programacion.fn_v09_sha256_jsonb(jsonb_agg(jsonb_build_object(
   'rule_code',rule_code,'snapshot_sha256',request_snapshot_sha256) ORDER BY rule_code))
 INTO v_codes,v_snap FROM public.lf_rule_promotion_v1;
 sc:=jsonb_build_object('action','PROMOTE_RULE_BATCH',
  'repository','cristhianlujan/claude-persona-lf-patch',
  'execution_id','EXEC-FIXTURE-1234567890',
  'rule_codes',v_codes,'rule_snapshots_sha256',v_snap);
 lit:='APRUEBO '||left(programacion.fn_v09_sha256_jsonb(sc),12)||' '||programacion.fn_v09_canonical_jsonb_text(sc);
 r:=private.fn_lf_owner_chat_register_v1('fixture-chat-123456','fixture-msg-batch-0001',
 'CHAT_ORCHESTRATOR_USER_TURN','fixture-owner-123','fixture-proposer-123',
 'fixture-recorder-123',clock_timestamp(),lit,sc);
 oid:=(r->>'order_id')::uuid;
 r:=private.fn_lf_owner_chat_promote_batch_v1(oid,
  ARRAY(SELECT promotion_id FROM public.lf_rule_promotion_v1 ORDER BY promotion_id),
  'fixture-owner-123','fixture-only');
 IF r->>'status'<>'APPLIED' OR (r->>'count')::integer<>22
  THEN RAISE EXCEPTION 'POS_22:%',r; END IF;
 SELECT count(*) INTO v_n FROM public.lf_rule_promotion_v1 WHERE status='APPLIED';
 IF v_n<>22 THEN RAISE EXCEPTION 'POS_READBACK_NOT_22:%',v_n; END IF;
 r:=private.fn_lf_owner_chat_consume_v1(oid,'PROMOTE_RULE_BATCH',sc,
  'fixture-owner-123','PROMOTION_BATCH_TX:fixture');
 IF r->>'code'<>'CHAT_ORDER_REUSED' THEN RAISE EXCEPTION 'NEG_BATCH_REPLAY:%',r; END IF;
 RAISE NOTICE 'LF_CHAT_PGDUAL_FIXTURE_SUCCESS cases=8 promotion=22 merge=HEAD';
END $test$;
"""
class OwnerChatPGDualRollback(unittest.TestCase):
    def test_real_pg17_pg18(self):
        self.assertTrue(shutil.which('docker'),'DOCKER_REQUIRED_TO_CLAIM_PG17_PG18')
        sql=MIGRATION.read_text(encoding='utf-8')
        # Patch decide_v1 preimage requires the real canonical function; the fixture
        # tests the actual one-use ledger, batch and merge functions with an explicit stub.
        left=sql.index('-- Guard the exact live HUMAN consumer')
        right=sql.index('-- Train consumer',left)
        sql=sql[:left]+sql[right:]
        sql=sql.replace('BEGIN;','',1)
        sql=re.sub(r'\bCOMMIT;\s*$','',sql)
        for version in ('17.6','18.7'):
            with self.subTest(pg=version):
                name='lf-owner-chat-'+uuid.uuid4().hex[:10]
                start=subprocess.run(['docker','run','-d','--rm','--name',name,
                  '-e','POSTGRES_PASSWORD=fixture','postgres:'+version],
                  capture_output=True,text=True,timeout=180)
                self.assertEqual(start.returncode,0,start.stderr)
                try:
                    for _ in range(90):
                        ping=subprocess.run(['docker','exec',name,'pg_isready','-U','postgres'],
                          capture_output=True,text=True,timeout=15)
                        if ping.returncode==0:
                            logs=subprocess.run(['docker','logs',name],
                                capture_output=True,text=True,timeout=15)
                            if 'PostgreSQL init process complete; ready for start up.' in (logs.stdout+logs.stderr):
                                break
                        time.sleep(.5)
                    self.assertEqual(ping.returncode,0)
                    script=SETUP+'\nBEGIN;\n'+sql+'\n'+ASSERTIONS+'\nROLLBACK;\n'+"""
SELECT CASE WHEN to_regclass('private.lf_owner_chat_orders_v1') IS NULL
 THEN 'ROLLBACK_CLEAN' ELSE 'ROLLBACK_DIRTY' END;
"""
                    process=subprocess.run(['docker','exec','-i',name,'psql','-X',
                        '-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],
                        input=script,capture_output=True,text=True,timeout=240)
                    self.assertEqual(process.returncode,0,process.stderr[-6000:])
                    self.assertIn('LF_CHAT_PGDUAL_FIXTURE_SUCCESS',process.stderr)
                    self.assertIn('ROLLBACK_CLEAN',process.stdout)
                finally:
                    subprocess.run(['docker','rm','-f',name],capture_output=True,timeout=30)
if __name__=='__main__':unittest.main()
