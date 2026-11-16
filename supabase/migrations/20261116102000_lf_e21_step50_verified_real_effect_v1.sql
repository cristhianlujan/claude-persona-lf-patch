BEGIN;
-- E21 Step50. Actual rule mutations remain in the existing governed PR/Merge Train.
-- These functions capture immutable DB snapshots before and after that mutation,
-- then verify real Train closure and the current rule before Step50 may be recorded.
CREATE TABLE public.lf_profile_step50_rule_effect_receipts_v1 (
  profile_execution_id text NOT NULL,
  train_execution_id text NOT NULL,
  rule_code text NOT NULL,
  before_snapshot jsonb NOT NULL,
  before_sha256 text NOT NULL CHECK (before_sha256 ~ '^[0-9a-f]{64}$'),
  after_snapshot jsonb,
  after_sha256 text CHECK (after_sha256 IS NULL OR after_sha256 ~ '^[0-9a-f]{64}$'),
  status text NOT NULL CHECK (status IN ('BEFORE_CAPTURED','EFFECT_CAPTURED')),
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (profile_execution_id,train_execution_id,rule_code),
  CHECK (
    (status='BEFORE_CAPTURED' AND after_snapshot IS NULL AND after_sha256 IS NULL AND completed_at IS NULL)
    OR (status='EFFECT_CAPTURED' AND after_snapshot IS NOT NULL AND after_sha256 IS NOT NULL
      AND before_sha256<>after_sha256 AND completed_at IS NOT NULL)
  )
);
ALTER TABLE public.lf_profile_step50_rule_effect_receipts_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_profile_step50_rule_effect_receipts_v1 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lf_profile_step50_rule_snapshot_v1(p_rule_code text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $snap$
SELECT coalesce(
 (SELECT to_jsonb(r)-'created_at'-'updated_at' FROM lf_ops.reglas r WHERE r.codigo=p_rule_code),
 jsonb_build_object('codigo',p_rule_code,'_state','ABSENT')
);
$snap$;
REVOKE ALL ON FUNCTION public.lf_profile_step50_rule_snapshot_v1(text)
  FROM PUBLIC,anon,authenticated,service_role;

-- Call BEFORE the actual rule DML in the governed migration, never from profile/LLM.
CREATE OR REPLACE FUNCTION public.lf_profile_step50_rule_effect_before_v1(
 p_profile_execution_id text,p_train_execution_id text,p_rule_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $before$
DECLARE p public.lf_operation_execution%rowtype;
        t public.lf_operation_execution%rowtype;
        v_snap jsonb;v_sha text;
BEGIN
 SELECT * INTO p FROM public.lf_operation_execution WHERE execution_id=p_profile_execution_id;
 SELECT * INTO t FROM public.lf_operation_execution WHERE execution_id=p_train_execution_id;
 IF p.execution_id IS NULL OR p.status<>'IN_PROGRESS'
 OR p.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
 OR coalesce((p.manifest->>'governed_repair_write')::boolean,false) IS NOT TRUE
 OR coalesce((p.manifest->>'promotion_allowed')::boolean,false) IS NOT TRUE
 OR coalesce((p.manifest#>>'{repair_execution_authority,promotion_allowed}')::boolean,false) IS NOT TRUE
 OR t.execution_id IS NULL OR t.operation_code<>'ACTUALIZACION_DB_LF'
 OR t.status<>'IN_PROGRESS'
 OR t.manifest->>'producer'<>'lf-migration-merge-train'
 OR coalesce((t.manifest->>'pr')::integer,0)<1
 OR t.manifest->>'train_run_id' !~ '^[0-9]+$'
 OR nullif(btrim(p_rule_code),'') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_CAPTURE_AUTHORITY_INVALID'); END IF;
 v_snap:=public.lf_profile_step50_rule_snapshot_v1(p_rule_code);
 v_sha:=encode(extensions.digest(convert_to(v_snap::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_profile_step50_rule_effect_receipts_v1(
   profile_execution_id,train_execution_id,rule_code,before_snapshot,before_sha256,status)
 VALUES(p_profile_execution_id,p_train_execution_id,p_rule_code,v_snap,v_sha,'BEFORE_CAPTURED');
 RETURN jsonb_build_object('status','BEFORE_CAPTURED','rule_code',p_rule_code,
   'before_sha256',v_sha,'train_execution_id',p_train_execution_id);
EXCEPTION WHEN unique_violation THEN
 RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_CAPTURE_DUPLICATE');
END $before$;
REVOKE ALL ON FUNCTION public.lf_profile_step50_rule_effect_before_v1(text,text,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Call AFTER the actual DML, in the same Train migration transaction.
CREATE OR REPLACE FUNCTION public.lf_profile_step50_rule_effect_after_v1(
 p_profile_execution_id text,p_train_execution_id text,p_rule_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $after$
DECLARE v_row public.lf_profile_step50_rule_effect_receipts_v1%rowtype;
        v_snap jsonb;v_sha text;v_train_status text;v_profile_status text;
BEGIN
 SELECT status INTO v_train_status FROM public.lf_operation_execution
 WHERE execution_id=p_train_execution_id AND operation_code='ACTUALIZACION_DB_LF';
 SELECT status INTO v_profile_status FROM public.lf_operation_execution
 WHERE execution_id=p_profile_execution_id AND operation_code='EJECUCION_PERFIL_LF';
 IF v_train_status IS DISTINCT FROM 'IN_PROGRESS'
    OR v_profile_status IS DISTINCT FROM 'IN_PROGRESS' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_CAPTURE_AUTHORITY_INVALID');
 END IF;
 SELECT * INTO v_row FROM public.lf_profile_step50_rule_effect_receipts_v1
 WHERE profile_execution_id=p_profile_execution_id AND train_execution_id=p_train_execution_id
 AND rule_code=p_rule_code FOR UPDATE;
 IF NOT FOUND OR v_row.status<>'BEFORE_CAPTURED' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_BEFORE_MISSING');
 END IF;
 v_snap:=public.lf_profile_step50_rule_snapshot_v1(p_rule_code);
 IF v_snap->>'_state'='ABSENT' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_AFTER_RULE_MISSING');
 END IF;
 v_sha:=encode(extensions.digest(convert_to(v_snap::text,'UTF8'),'sha256'),'hex');
 IF v_sha=v_row.before_sha256 THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_NO_CHANGE');
 END IF;
 UPDATE public.lf_profile_step50_rule_effect_receipts_v1
 SET after_snapshot=v_snap,after_sha256=v_sha,status='EFFECT_CAPTURED',completed_at=clock_timestamp()
 WHERE profile_execution_id=p_profile_execution_id AND train_execution_id=p_train_execution_id
 AND rule_code=p_rule_code;
 RETURN jsonb_build_object('status','EFFECT_CAPTURED','rule_code',p_rule_code,
   'source_ref','supabase://lf_ops.reglas/'||p_rule_code,
   'before_sha256',v_row.before_sha256,'after_sha256',v_sha,
   'train_execution_id',p_train_execution_id);
END $after$;
REVOKE ALL ON FUNCTION public.lf_profile_step50_rule_effect_after_v1(text,text,text)
 FROM PUBLIC,anon,authenticated,service_role;

-- Single DB authority gate: input model claims are never the proof.
CREATE OR REPLACE FUNCTION public.lf_profile_step50_rule_effect_guard_v1(
 p_execution_id text,p_output jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $guard$
DECLARE e public.lf_operation_execution%rowtype;
        v_mode text;v_promote boolean;v_write boolean;v_rows jsonb;
        item jsonb;v_rule text;v_source text;v_before text;v_after text;
        v_train public.lf_operation_execution%rowtype;
        v_receipt public.lf_profile_step50_rule_effect_receipts_v1%rowtype;
        v_current_sha text;v_current jsonb;v_count integer:=0;v_verified jsonb:='[]'::jsonb;
        v_scope text;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EXECUTION_NOT_IN_PROGRESS');
 END IF;
 v_mode:=p_output#>>'{repair_execution,mode}';
 v_promote:=coalesce((e.manifest->>'promotion_allowed')::boolean,false);
 v_write:=coalesce((e.manifest->>'governed_repair_write')::boolean,false);
 IF v_mode='AUTHORIZED_NOT_EXECUTED' AND v_promote THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_AUTHORIZED_NOT_EXECUTED_FORBIDDEN');
 END IF;
 IF NOT v_promote THEN
   RETURN jsonb_build_object('status','ALLOW_NO_PROMOTION','code','STEP50_NO_EFFECT_ALLOWED_NO_PROMOTION');
 END IF;
 IF NOT v_write OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR coalesce((e.manifest#>>'{repair_execution_authority,promotion_allowed}')::boolean,false) IS NOT TRUE THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_PROMOTION_REPAIR_AUTHORITY_MISMATCH');
 END IF;
 IF v_mode IS DISTINCT FROM 'EXECUTED_WITH_READBACK' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_VERIFIED_EFFECT_MODE_REQUIRED');
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
   WHERE s.execution_id=p_execution_id AND s.step_order=40
     AND s.step_id='input_validate' AND s.status='STEP_PASS_WITH_EVIDENCE'
     AND s.evidence_payload->>'scope_authority_packet_sha256' ~ '^sha256:[0-9a-f]{64}$') THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_STEP40_SCOPE_NOT_BOUND');
 END IF;
 v_rows:=p_output#>'{repair_execution,rule_receipts}';
 IF jsonb_typeof(v_rows) IS DISTINCT FROM 'array' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_RULE_RECEIPTS_REQUIRED');
 END IF;
 IF jsonb_array_length(v_rows)=0 THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_RULE_RECEIPTS_REQUIRED');
 END IF;
 IF jsonb_typeof(p_output#>'{repair_execution,changes}') IS DISTINCT FROM 'array' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_CHANGES_NOT_BOUND');
 END IF;
 IF jsonb_array_length(p_output#>'{repair_execution,changes}')<>jsonb_array_length(v_rows) THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_CHANGES_NOT_BOUND');
 END IF;
 v_scope:=e.manifest#>>'{screen_selection_result,selected_screen_code}';
 IF nullif(btrim(coalesce(v_scope,'')),'') IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP50_SELECTED_SCOPE_UNRESOLVED');
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(v_rows) LOOP
   v_rule:=item->>'rule_code';
   v_source:=item->>'source_ref';
   v_before:=item->>'before_sha256';v_after:=item->>'after_sha256';
   IF nullif(btrim(coalesce(v_rule,'')),'') IS NULL
   OR v_source IS DISTINCT FROM 'supabase://lf_ops.reglas/'||v_rule THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_RULE_RECEIPT_SOURCE_REF_MISMATCH');
   END IF;
   IF v_before !~ '^[0-9a-f]{64}$' OR v_after !~ '^[0-9a-f]{64}$'
   OR v_before IS NULL OR v_after IS NULL OR v_before=v_after THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_HASH_PAIR_REQUIRED');
   END IF;
   IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_rows) x WHERE x->>'rule_code'=v_rule
      GROUP BY x->>'rule_code' HAVING count(*)>1) THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_RULE_RECEIPT_DUPLICATE');
   END IF;
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_output#>'{repair_execution,changes}') c
        WHERE c->>'target_ref'=v_source
          AND c->>'after_ref' IS NOT NULL AND c->>'before_ref' IS NOT NULL) THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_CHANGES_NOT_BOUND');
   END IF;
   IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
       JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
       WHERE r.codigo=v_rule AND p.codigo=v_scope) THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_RULE_OUTSIDE_SELECTED_SCREEN');
   END IF;
   SELECT * INTO v_receipt FROM public.lf_profile_step50_rule_effect_receipts_v1
   WHERE profile_execution_id=p_execution_id AND train_execution_id=item->>'train_execution_id'
      AND rule_code=v_rule AND status='EFFECT_CAPTURED';
   IF NOT FOUND OR v_receipt.before_sha256 IS DISTINCT FROM v_before
      OR v_receipt.after_sha256 IS DISTINCT FROM v_after THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_NOT_ATTESTED');
   END IF;
   IF encode(extensions.digest(convert_to(v_receipt.before_snapshot::text,'UTF8'),'sha256'),'hex')
      IS DISTINCT FROM v_before
   OR encode(extensions.digest(convert_to(v_receipt.after_snapshot::text,'UTF8'),'sha256'),'hex')
      IS DISTINCT FROM v_after THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_SNAPSHOT_HASH_DRIFT');
   END IF;
   v_current:=public.lf_profile_step50_rule_snapshot_v1(v_rule);
   v_current_sha:=encode(extensions.digest(convert_to(v_current::text,'UTF8'),'sha256'),'hex');
   IF v_current_sha IS DISTINCT FROM v_after THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_EFFECT_AFTER_NOT_CURRENT');
   END IF;
   SELECT * INTO v_train FROM public.lf_operation_execution
    WHERE execution_id=item->>'train_execution_id';
   IF NOT FOUND OR v_train.operation_code<>'ACTUALIZACION_DB_LF'
      OR v_train.status<>'COMPLETED'
      OR v_train.manifest->>'producer'<>'lf-migration-merge-train'
      OR v_train.manifest->>'operation_closed'<>'true'
      OR v_train.manifest#>>'{closure_evidence,parity}'<>'PASS'
      OR v_train.manifest->>'pr' IS DISTINCT FROM item->>'train_pr'
      OR v_train.manifest->>'train_run_id' IS DISTINCT FROM item->>'train_run_id'
      OR v_train.manifest#>>'{closure_evidence,ledger,version}' IS DISTINCT FROM item->>'migration_version'
      OR v_train.manifest#>>'{closure_evidence,ledger,name}' IS DISTINCT FROM item->>'migration_name'
      OR v_train.manifest#>>'{closure_evidence,merge_sha}' IS DISTINCT FROM item->>'merge_sha'
      OR v_train.target_code
          IS DISTINCT FROM (item->>'migration_version')||'_'||(item->>'migration_name')
      OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations m
           WHERE m.version=item->>'migration_version' AND m.name=item->>'migration_name')
      OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps t
           WHERE t.execution_id=v_train.execution_id AND t.step_order=20
             AND t.step_id='patch' AND t.status='PASS_CLEAN'
             AND t.evidence_payload->>'train_run_id'=item->>'train_run_id')
      OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps t
           WHERE t.execution_id=v_train.execution_id AND t.step_order=30
             AND t.step_id='verify' AND t.status='PASS_CLEAN'
             AND t.evidence_payload#>>'{readback,in_main}'='true'
             AND t.evidence_payload->>'train_run_id'=item->>'train_run_id')
   THEN
     RETURN jsonb_build_object('status','BLOCKED','code','STEP50_TRAIN_RECEIPT_NOT_VERIFIED');
   END IF;
   v_count:=v_count+1;
   v_verified:=v_verified||jsonb_build_array(jsonb_build_object(
     'rule_code',v_rule,'source_ref',v_source,
     'before_sha256',v_before,'after_sha256',v_after,
     'train_execution_id',v_train.execution_id,
     'train_pr',v_train.manifest->'pr',
     'train_run_id',v_train.manifest->>'train_run_id',
     'migration_version',item->>'migration_version',
     'merge_sha',item->>'merge_sha'));
 END LOOP;
 RETURN jsonb_build_object('status','VERIFIED','code','STEP50_EFFECTS_VERIFIED',
   'verified_rule_count',v_count,'rule_receipts',v_verified,
   'step40_bound',true,'step50_raw_sha_bound_at_write',true,
   'step60_step70_status','PENDING_EXISTING_DIGEST_CHAIN');
END $guard$;

REVOKE ALL ON FUNCTION public.lf_profile_step50_rule_effect_guard_v1(text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_step50_rule_effect_guard_v1(text,jsonb)
 TO service_role;

-- Bind the authoritative guard inside the EXISTING Step50 writer before any step is persisted.
DO $patch$
DECLARE d text;old text;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure);
 IF md5(d)<>'944fd7e676e442e9dbe4e1a3303603b8' THEN
   RAISE EXCEPTION 'STEP50_SOURCE_STATE_DRIFT';
 END IF;
 old:=d;
 d:=replace(d,'  v_family_gate jsonb;',E'  v_family_gate jsonb;\n  v_step50_effect jsonb;');
 d:=replace(d,$oldactor$  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);$oldactor$,
   $replacement$  v_step50_effect:=public.lf_profile_step50_rule_effect_guard_v1(p_execution_id,p_profile_output);
  IF v_step50_effect->>'status'='BLOCKED' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code',v_step50_effect->>'code',
      'step','execute_profile','step50_recorded',false);
  END IF;
  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);$replacement$);
 d:=replace(d,
    $old$        'profile_output',p_profile_output,$old$,
    $new$        'profile_output',p_profile_output,
        'step50_effect_verification',v_step50_effect,$new$);
 IF d=old OR position('v_step50_effect:=public.lf_profile_step50_rule_effect_guard_v1' IN d)=0
   OR position($x$'step50_effect_verification',v_step50_effect$x$ IN d)=0 THEN
   RAISE EXCEPTION 'STEP50_WRITER_PATCH_NOT_APPLIED';
 END IF;
 EXECUTE d;
END $patch$;


-- The scorer must consume the server-verified SRCR Step50 receipt as a second
-- source-ref route, without changing its A, hard-block or 40/50/60/70 SHA gates.
DO $score_patch$
DECLARE d text;d0 text;
BEGIN
 d:=pg_get_functiondef('public.lf_rule_promotion_score_v1(text,text)'::regprocedure);
 IF md5(d)<>'38ce5aa5a36e70d44cf2c6d3cfd6c596' THEN
   RAISE EXCEPTION 'STEP50_SCORER_SOURCE_STATE_DRIFT';
 END IF;
 d0:=d;
 d:=replace(d,
   $old$  IF is_bound AND has_ref THEN b:=30; END IF;$old$,
   $new$  IF NOT has_ref
     AND p50.evidence_payload#>>'{step50_effect_verification,status}'='VERIFIED'
     AND jsonb_typeof(p50.evidence_payload#>'{step50_effect_verification,rule_receipts}')='array'
   THEN
     SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(
       p50.evidence_payload#>'{step50_effect_verification,rule_receipts}') x
       WHERE x->>'rule_code'=p_rule_code
         AND x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code
     ) INTO has_ref;
   END IF;
   IF is_bound AND has_ref THEN b:=30; END IF;$new$);
 IF d=d0 OR position('step50_effect_verification,rule_receipts' IN d)=0 THEN
   RAISE EXCEPTION 'STEP50_SCORER_PATCH_NOT_APPLIED';
 END IF;
 EXECUTE d;
END $score_patch$;

COMMIT;
