-- LF IG GUARDED OWNER WRITER v3 (one migration), rebased on deployed PR #3803
-- Source Git merge 44c2638937cfcea16dbdb9d4476b84c87fecb2b0; original source PR head c9c4066e82a595c53a7ed761a94548b43db58133.
-- Decision model: Cristhian Luján DOCUMENTARY, identity_verified=false.
-- All assets new/updated owner_name = LF_GOVERNANCE; 11 archived via separately
-- approved archived function. NO historical backfill data in this migration.
-- ACT-0001 pinned writer contract requires re-pin of the scope POLICY hash.
-- This is done here only after checking deployed preimage md5+policy sha.
BEGIN;
DO $preflight$
DECLARE v_sha text; v_policy public.lf_router_scope_policy_v1%ROWTYPE;
BEGIN
 IF to_regclass('public.lf_ig_asset_owner_receipt_v2') IS NULL
 OR to_regprocedure('public.lf_ig_asset_owner_approve_v2(text,text,text,text,jsonb)') IS NULL
 OR to_regprocedure('public.lf_ig_asset_owner_apply_v2(uuid)') IS NULL
 OR to_regprocedure('public.lf_router_scope_bind_v1(text)') IS NULL
 OR to_regclass('public.lf_router_scope_policy_v1') IS NULL
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_DEPLOYED_3803_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.lf_activos'::regclass AND
 tgname IN ('trg_lf_asset_owner_one_name_insert_v1','trg_lf_asset_owner_one_name_update_v1'))
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_ALREADY_PRESENT'; END IF;
 IF (SELECT column_default FROM information_schema.columns WHERE table_schema='public'
    AND table_name='lf_activos' AND column_name='owner_name') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_EXISTING_DEFAULT_UNEXPECTED'; END IF;
 SELECT * INTO v_policy FROM public.lf_router_scope_policy_v1
 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1';
 v_sha:=md5(pg_get_functiondef('public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure));
 IF NOT FOUND OR v_sha IS DISTINCT FROM 'cc5c36bf2ae0686bd46192b97956cbb2'
 OR v_policy.writer_source_md5 IS DISTINCT FROM v_sha
 OR v_policy.policy_sha256 IS DISTINCT FROM
   '443c837276c0a5a9cece681489d96cfa11b1a51a531bead50fa1dfd1c9ecf672'
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_LIVE_ROUTER_SCOPE_PREIMAGE_DRIFT'; END IF;
END $preflight$;
ALTER TABLE public.lf_activos ALTER COLUMN owner_name SET DEFAULT 'LF_GOVERNANCE';
CREATE FUNCTION public.lf_asset_owner_one_name_insert_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $fn$
BEGIN
 NEW.owner_name := 'LF_GOVERNANCE';
 RETURN NEW;
END $fn$;
CREATE TRIGGER trg_lf_asset_owner_one_name_insert_v1
BEFORE INSERT ON public.lf_activos
FOR EACH ROW EXECUTE FUNCTION public.lf_asset_owner_one_name_insert_v1();
CREATE FUNCTION public.lf_asset_owner_one_name_update_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $fn$
BEGIN
 IF NEW.owner_name IS DISTINCT FROM OLD.owner_name
   AND NEW.owner_name IS DISTINCT FROM 'LF_GOVERNANCE'
 THEN RAISE EXCEPTION 'LF_OWNER_ONLY_LF_GOVERNANCE_ALLOWED'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER trg_lf_asset_owner_one_name_update_v1
BEFORE UPDATE OF owner_name ON public.lf_activos
FOR EACH ROW EXECUTE FUNCTION public.lf_asset_owner_one_name_update_v1();
-- Keep deployed decision and ACT-0001 scope checks; narrow only target owner.
CREATE OR REPLACE FUNCTION public.lf_ig_asset_owner_approve_v2(
 p_train_execution text,p_asset_code text,p_preimage_sha256 text,
 p_new_owner text,p_decision jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE a public.lf_activos%ROWTYPE; v_sha text; v_id uuid; v_sub uuid;
 v_train public.lf_operation_execution%ROWTYPE;
 v_proposer text; v_date timestamptz; v_dec_sha text; v_scope jsonb;
BEGIN
 IF p_decision IS NULL OR jsonb_typeof(p_decision)<>'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_decision))<>6
    OR NOT (p_decision ?& ARRAY['codigo_activo','preimagen_sha256',
      'veredicto','decisor','fecha','frase_literal'])
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_RECORD_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(p_decision) e
   WHERE jsonb_typeof(e.value)<>'string')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_FIELD_TYPE_INVALID'; END IF;
 IF p_decision->>'codigo_activo' IS DISTINCT FROM p_asset_code
   OR p_decision->>'preimagen_sha256' IS DISTINCT FROM p_preimage_sha256
   OR p_decision->>'veredicto' IS DISTINCT FROM 'APROBAR'
   OR p_decision->>'decisor' IS DISTINCT FROM 'Cristhian Luján'
   OR length(btrim(coalesce(p_decision->>'frase_literal','')))<6
   OR coalesce(p_decision->>'fecha','') !~
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_INPUT_INVALID'; END IF;
 v_date:=(p_decision->>'fecha')::timestamptz;
 SELECT owner_sub INTO v_sub FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF' AND owner_name='Cristhian Luján'
   AND status='TEMP_DOCUMENTARY_ACTIVE';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_DECLARATION_MISSING'; END IF;
 SELECT * INTO v_train FROM public.lf_operation_execution
 WHERE execution_id=p_train_execution AND operation_code='ACTUALIZACION_DB_LF'
   AND status='IN_PROGRESS';
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=p_train_execution AND step_id='preflight' AND status='PASS_CLEAN')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_MERGE_TRAIN_PRECHECK_MISSING'; END IF;
 -- ACT-0001 server-bound scope receipt is issued from canonical catalog
 -- and Train provenance; no human-defined positive/negative JSON is accepted.
 v_scope:=public.lf_router_scope_bind_v1(p_train_execution);
 IF v_scope->>'status'<>'SCOPE_ATTESTED_ROUTE_ONLY'
    OR v_scope->>'execution_id' IS DISTINCT FROM p_train_execution
    OR v_scope->'positive_scope' IS DISTINCT FROM
       '[{"table":"public.lf_activos","columns":["owner_name","updated_at","updated_by_execution_id"],"business_field":"owner_name","audit_columns":["updated_at","updated_by_execution_id"],"entrypoint":"public.lf_ig_asset_owner_apply_v2(uuid)"}]'::jsonb
    OR v_scope->>'effect_authority'<>'false'
    OR v_scope->>'downstream_execution_allowed'<>'false'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SCOPE_RECEIPT_NOT_GOVERNED'; END IF;
 v_proposer:=nullif(btrim(v_train.manifest->>'proposer_actor'),'');
 IF v_proposer IS NULL OR v_proposer='Cristhian Luján'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SELF_APPROVAL_FORBIDDEN'; END IF;
 IF v_date < v_train.started_at-interval '5 minutes'
    OR v_date > now()+interval '5 minutes'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_DATE_OUT_OF_SCOPE'; END IF;
 SELECT * INTO a FROM public.lf_activos
 WHERE codigo_activo=p_asset_code AND archived_at IS NULL FOR SHARE;
 IF NOT FOUND OR p_new_owner IS DISTINCT FROM 'LF_GOVERNANCE' OR a.owner_name IS NOT DISTINCT FROM 'LF_GOVERNANCE'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SCOPE_INVALID'; END IF;
 v_sha:=encode(extensions.digest(convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex');
 IF v_sha IS DISTINCT FROM p_preimage_sha256
 THEN RAISE EXCEPTION 'LF_IG_ASSET_PREIMAGE_STALE'; END IF;
 v_dec_sha:=encode(extensions.digest(convert_to(p_decision::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_asset_owner_receipt_v2(
   asset_code,owner_sub,decisor,proponente,decision_record,decision_record_sha256,
   proposed_owner,train_execution_id,preimage_sha256,before_row)
 VALUES(p_asset_code,v_sub,'Cristhian Luján',v_proposer,p_decision,v_dec_sha,
   p_new_owner,p_train_execution,v_sha,to_jsonb(a))
 RETURNING receipt_id INTO v_id;
 RETURN jsonb_build_object('status','APPROVED','receipt_id',v_id,
   'preimage_sha256',v_sha,'decisor','Cristhian Luján',
   'decision_record',p_decision,'decision_record_sha256',v_dec_sha,
   'identity_verified',false);
END
$fn$;
-- Archived approval still goes through the SAME scope-bound documentary receipt.
CREATE FUNCTION public.lf_ig_asset_owner_approve_archived_v3(
 p_train_execution text,p_asset_code text,p_preimage_sha256 text,
 p_new_owner text,p_decision jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE a public.lf_activos%ROWTYPE; v_sha text; v_id uuid; v_sub uuid;
 v_train public.lf_operation_execution%ROWTYPE;
 v_proposer text; v_date timestamptz; v_dec_sha text; v_scope jsonb;
BEGIN
 IF p_decision IS NULL OR jsonb_typeof(p_decision)<>'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_decision))<>6
    OR NOT (p_decision ?& ARRAY['codigo_activo','preimagen_sha256',
      'veredicto','decisor','fecha','frase_literal'])
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_RECORD_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(p_decision) e
   WHERE jsonb_typeof(e.value)<>'string')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_FIELD_TYPE_INVALID'; END IF;
 IF p_decision->>'codigo_activo' IS DISTINCT FROM p_asset_code
   OR p_decision->>'preimagen_sha256' IS DISTINCT FROM p_preimage_sha256
   OR p_decision->>'veredicto' IS DISTINCT FROM 'APROBAR'
   OR p_decision->>'decisor' IS DISTINCT FROM 'Cristhian Luján'
   OR length(btrim(coalesce(p_decision->>'frase_literal','')))<6
   OR coalesce(p_decision->>'fecha','') !~
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_INPUT_INVALID'; END IF;
 v_date:=(p_decision->>'fecha')::timestamptz;
 SELECT owner_sub INTO v_sub FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF' AND owner_name='Cristhian Luján'
   AND status='TEMP_DOCUMENTARY_ACTIVE';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_DECLARATION_MISSING'; END IF;
 SELECT * INTO v_train FROM public.lf_operation_execution
 WHERE execution_id=p_train_execution AND operation_code='ACTUALIZACION_DB_LF'
   AND status='IN_PROGRESS';
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=p_train_execution AND step_id='preflight' AND status='PASS_CLEAN')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_MERGE_TRAIN_PRECHECK_MISSING'; END IF;
 -- ACT-0001 server-bound scope receipt is issued from canonical catalog
 -- and Train provenance; no human-defined positive/negative JSON is accepted.
 v_scope:=public.lf_router_scope_bind_v1(p_train_execution);
 IF v_scope->>'status'<>'SCOPE_ATTESTED_ROUTE_ONLY'
    OR v_scope->>'execution_id' IS DISTINCT FROM p_train_execution
    OR v_scope->'positive_scope' IS DISTINCT FROM
       '[{"table":"public.lf_activos","columns":["owner_name","updated_at","updated_by_execution_id"],"business_field":"owner_name","audit_columns":["updated_at","updated_by_execution_id"],"entrypoint":"public.lf_ig_asset_owner_apply_v2(uuid)"}]'::jsonb
    OR v_scope->>'effect_authority'<>'false'
    OR v_scope->>'downstream_execution_allowed'<>'false'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SCOPE_RECEIPT_NOT_GOVERNED'; END IF;
 v_proposer:=nullif(btrim(v_train.manifest->>'proposer_actor'),'');
 IF v_proposer IS NULL OR v_proposer='Cristhian Luján'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SELF_APPROVAL_FORBIDDEN'; END IF;
 IF v_date < v_train.started_at-interval '5 minutes'
    OR v_date > now()+interval '5 minutes'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_DATE_OUT_OF_SCOPE'; END IF;
 SELECT * INTO a FROM public.lf_activos
 WHERE codigo_activo=p_asset_code AND archived_at IS NOT NULL FOR SHARE;
 IF NOT FOUND OR p_new_owner IS DISTINCT FROM 'LF_GOVERNANCE' OR a.owner_name IS NOT DISTINCT FROM 'LF_GOVERNANCE'
 THEN RAISE EXCEPTION 'LF_IG_ARCHIVED_SCOPE_INVALID'; END IF;
 v_sha:=encode(extensions.digest(convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex');
 IF v_sha IS DISTINCT FROM p_preimage_sha256
 THEN RAISE EXCEPTION 'LF_IG_ASSET_PREIMAGE_STALE'; END IF;
 v_dec_sha:=encode(extensions.digest(convert_to(p_decision::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_asset_owner_receipt_v2(
   asset_code,owner_sub,decisor,proponente,decision_record,decision_record_sha256,
   proposed_owner,train_execution_id,preimage_sha256,before_row)
 VALUES(p_asset_code,v_sub,'Cristhian Luján',v_proposer,p_decision,v_dec_sha,
   p_new_owner,p_train_execution,v_sha,to_jsonb(a))
 RETURNING receipt_id INTO v_id;
 RETURN jsonb_build_object('status','APPROVED','receipt_id',v_id,
   'preimage_sha256',v_sha,'decisor','Cristhian Luján',
   'decision_record',p_decision,'decision_record_sha256',v_dec_sha,
   'identity_verified',false);
END
$fn$;
-- Same source attestation; only active/archived targeting becomes explicit.
CREATE OR REPLACE FUNCTION public.lf_ig_asset_owner_apply_v2(p_receipt uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE t public.lf_ig_asset_owner_receipt_v2%ROWTYPE;a public.lf_activos%ROWTYPE;v_sha text;v_after text; v_scope jsonb;
BEGIN
 SELECT * INTO t FROM public.lf_ig_asset_owner_receipt_v2 WHERE receipt_id=p_receipt FOR UPDATE;
 IF NOT FOUND OR t.state<>'APPROVED' OR t.proposed_owner IS DISTINCT FROM 'LF_GOVERNANCE'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_RECEIPT_NOT_APPROVED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_ig_project_owner_v2
    WHERE project_code='LF' AND owner_sub=t.owner_sub
    AND owner_name=t.decisor AND status='TEMP_DOCUMENTARY_ACTIVE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id=t.train_execution_id AND operation_code='ACTUALIZACION_DB_LF'
    AND status='IN_PROGRESS')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=t.train_execution_id AND step_id='preflight' AND status='PASS_CLEAN')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_TRAIN_OR_DECLARATION_STALE'; END IF;
 IF encode(extensions.digest(convert_to(t.decision_record::text,'UTF8'),'sha256'),'hex')
    IS DISTINCT FROM t.decision_record_sha256
    OR t.decision_record->>'decisor' IS DISTINCT FROM t.decisor
    OR t.decision_record->>'veredicto' IS DISTINCT FROM 'APROBAR'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_RECEIPT_CORRUPT'; END IF;
 -- This mandatory readback blocks a direct service_role apply without
 -- the canonical ACT-0001 scope. One stable run => one idempotent receipt.
 v_scope:=public.lf_router_scope_bind_v1(t.train_execution_id);
 IF v_scope->>'status'<>'SCOPE_ATTESTED_ROUTE_ONLY'
    OR v_scope->>'execution_id' IS DISTINCT FROM t.train_execution_id
    OR v_scope->>'scope_code'<>'LF_ACTIVOS_OWNER_NAME_WRITE_V1'
    OR v_scope->>'effect_authority'<>'false'
    OR NOT EXISTS(SELECT 1 FROM public.lf_router_scope_receipt_v1 sr
      WHERE sr.execution_id=t.train_execution_id
        AND sr.receipt_sha256=v_scope->>'receipt_sha256')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SCOPE_RECEIPT_NOT_CURRENT'; END IF;
 SELECT * INTO a FROM public.lf_activos WHERE codigo_activo=t.asset_code
 AND archived_at IS NOT DISTINCT FROM (t.before_row->>'archived_at')::timestamptz FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_TARGET_MISSING'; END IF;
 v_sha:=encode(extensions.digest(convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex');
 IF v_sha IS DISTINCT FROM t.preimage_sha256 OR to_jsonb(a) IS DISTINCT FROM t.before_row
 THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_PREIMAGE_MISMATCH'; END IF;
 UPDATE public.lf_activos SET owner_name=t.proposed_owner,
    updated_by_execution_id=t.train_execution_id,updated_at=now()
 WHERE id=a.id AND codigo_activo=t.asset_code AND archived_at IS NOT DISTINCT FROM (t.before_row->>'archived_at')::timestamptz;
 SELECT * INTO a FROM public.lf_activos WHERE id=a.id;
 v_after:=encode(extensions.digest(convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex');
 IF a.owner_name IS DISTINCT FROM 'LF_GOVERNANCE' OR v_after=v_sha OR
 (to_jsonb(a)-'owner_name'-'updated_at'-'updated_by_execution_id') IS DISTINCT FROM
 (t.before_row-'owner_name'-'updated_at'-'updated_by_execution_id')
 THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_READBACK_FAILED'; END IF;
 UPDATE public.lf_ig_asset_owner_receipt_v2 SET state='APPLIED',after_sha256=v_after
 WHERE receipt_id=p_receipt AND state='APPROVED';
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','asset_code',t.asset_code,
 'old_sha256',v_sha,'new_sha256',v_after,
 'decision_record',t.decision_record,'decision_record_sha256',t.decision_record_sha256,
 'identity_verified',false,'train_execution_id',t.train_execution_id);
END
$fn$;
REVOKE ALL ON FUNCTION public.lf_ig_asset_owner_approve_archived_v3(text,text,text,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_asset_owner_approve_archived_v3(text,text,text,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.lf_ig_asset_owner_approve_v2(text,text,text,text,jsonb)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_ig_asset_owner_apply_v2(uuid)
 FROM PUBLIC,anon,authenticated;
-- POLICY re-pin: preserve pinned canonical schema & forbidden columns.
-- Source MD5 changes because apply_v2 is replaced to include archived owner.
-- Protect preimage SHA, compute and persist exact policy SHA for new writer.
DO $repin$
DECLARE p public.lf_router_scope_policy_v1%ROWTYPE; newmd5 text;
  newsha text; body jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_router_scope_policy_v1
 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1' FOR UPDATE;
 IF NOT FOUND
 OR p.writer_source_md5 IS DISTINCT FROM 'cc5c36bf2ae0686bd46192b97956cbb2'
 OR p.policy_sha256 IS DISTINCT FROM
   '443c837276c0a5a9cece681489d96cfa11b1a51a531bead50fa1dfd1c9ecf672'
 OR p.operation_code IS DISTINCT FROM 'ACTUALIZACION_DB_LF'
 OR p.effect_entrypoint IS DISTINCT FROM 'public.lf_ig_asset_owner_apply_v2(uuid)'
 OR p.allowed_table IS DISTINCT FROM 'public.lf_activos'
 OR p.allowed_columns IS DISTINCT FROM
    '["owner_name","updated_at","updated_by_execution_id"]'::jsonb
 OR p.schema_columns_sha256 IS DISTINCT FROM
   '97d4da62c5c96031532a8bd6c4dc913c897759a54f7cec3015925408ccc72cbb'
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_POLICY_SOURCE_NOT_PINNED'; END IF;
 newmd5:=md5(pg_get_functiondef('public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure));
 IF newmd5 IS NOT DISTINCT FROM p.writer_source_md5
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_WRITER_NOT_CHANGED'; END IF;
 body:=jsonb_build_object(
  'scope_code',p.scope_code,'operation_code',p.operation_code,
  'entrypoint',p.effect_entrypoint,'allowed_table',p.allowed_table,
  'allowed_columns',p.allowed_columns,'forbidden_columns',p.forbidden_columns,
  'schema_columns_sha256',p.schema_columns_sha256,'writer_source_md5',newmd5);
 newsha:=encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_router_scope_policy_v1
 SET writer_source_md5=newmd5,policy_sha256=newsha
 WHERE scope_code=p.scope_code AND writer_source_md5=p.writer_source_md5
   AND policy_sha256=p.policy_sha256;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_OWNER_GUARD_POLICY_REPIN_CAS_FAILED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_router_scope_policy_v1
    WHERE scope_code=p.scope_code AND writer_source_md5=newmd5 AND policy_sha256=newsha)
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_POLICY_REPIN_READBACK_FAILED'; END IF;
END $repin$;
DO $verify$
DECLARE p public.lf_router_scope_policy_v1%ROWTYPE; vsha text;
BEGIN
 SELECT * INTO p FROM public.lf_router_scope_policy_v1
 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1';
 IF NOT FOUND OR p.writer_source_md5 IS DISTINCT FROM
     md5(pg_get_functiondef('public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure))
 OR to_regprocedure('public.lf_ig_asset_owner_approve_archived_v3(text,text,text,text,jsonb)') IS NULL
 OR (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.lf_activos'::regclass
     AND NOT tgisinternal AND tgname IN
     ('trg_lf_asset_owner_one_name_insert_v1','trg_lf_asset_owner_one_name_update_v1'))<>2
 OR (SELECT column_default FROM information_schema.columns WHERE table_schema='public'
     AND table_name='lf_activos' AND column_name='owner_name')
     IS DISTINCT FROM '''LF_GOVERNANCE''::text'
 THEN RAISE EXCEPTION 'LF_OWNER_GUARD_MIGRATION_READBACK_FAILED'; END IF;
END $verify$;
COMMIT;
