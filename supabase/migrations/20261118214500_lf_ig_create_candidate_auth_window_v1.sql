-- IG CHAT 8: one atomic migration, generic CREATE route and AUTH window30.
-- One governed Train PR; no direct canonical rule insert, no promotion for CREATE.
-- AUTH parameter +1 dynamic guarded, function MD5 exact, CORRECT_VIGENTE unchanged.
BEGIN;
DO $ig_window$
DECLARE
 v_config_before text;
 v_config_old_after text;
 v_rules_before text;
 v_rules_after text;
 v_auth_before jsonb;
 v_auth_after jsonb;
 v_new public.lf_global_config%ROWTYPE;
 v_rls boolean;
 v_force boolean;
 v_policies integer;
 v_config_count_before integer;
 v_auth_count_before integer;
BEGIN
 IF to_regclass('public.lf_global_config') IS NULL
    OR to_regclass('lf_ops.reglas') IS NULL
 THEN RAISE EXCEPTION 'IG_WINDOW_CANONICAL_SOURCE_MISSING'; END IF;

 SELECT relrowsecurity,relforcerowsecurity INTO v_rls,v_force
 FROM pg_class WHERE oid='public.lf_global_config'::regclass;
 SELECT count(*) INTO v_policies FROM pg_policies
 WHERE schemaname='public' AND tablename='lf_global_config';
 IF NOT v_rls OR NOT v_force OR v_policies<>0
    OR has_table_privilege('anon','public.lf_global_config','SELECT')
    OR has_table_privilege('authenticated','public.lf_global_config','SELECT')
    OR has_table_privilege('anon','public.lf_global_config','INSERT')
    OR has_table_privilege('authenticated','public.lf_global_config','INSERT')
 THEN RAISE EXCEPTION 'IG_WINDOW_GLOBAL_CONFIG_AUTHORITY_DRIFT'; END IF;

 SELECT count(*) INTO v_config_count_before FROM public.lf_global_config;
 SELECT count(*) INTO v_auth_count_before FROM public.lf_global_config WHERE scope='AUTH';
 IF v_config_count_before < 12 OR v_auth_count_before < 10
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
    OR EXISTS(SELECT 1 FROM public.lf_global_config
       WHERE scope='AUTH' AND config_key='LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES')
    OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo IN (
      'PROP-B2B-AUTH-MFA-CONDITIONAL-001',
      'PROP-B2B-AUTH-TRUSTED-DEVICE-C-001',
      'PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001',
      'PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001'))
 THEN RAISE EXCEPTION 'IG_WINDOW_PREIMAGE_DRIFT'; END IF;

 IF NOT EXISTS(SELECT 1 FROM public.lf_global_config
   WHERE scope='AUTH' AND config_key='LOGIN_LOCKOUT_RESET_MINUTES'
     AND config_value='1440' AND value_type='INTEGER' AND value_status='REAL')
 OR EXISTS(
   WITH required(k,v) AS (VALUES
    ('LOGIN_LOCKOUT_ATTEMPTS_1','5'),('LOGIN_LOCKOUT_ATTEMPTS_2','3'),
    ('LOGIN_LOCKOUT_ATTEMPTS_3','3'),('LOGIN_LOCKOUT_MINUTES_1','15'),
    ('LOGIN_LOCKOUT_MINUTES_2','60'),('LOGIN_LOCKOUT_MINUTES_3','1440'),
    ('MFA_DEVICE_IDLE_DAYS','30'),('MFA_PASSWORD_AGE_MONTHS','3'))
   SELECT 1 FROM required w LEFT JOIN public.lf_global_config g
      ON g.scope='AUTH' AND g.config_key=w.k
   WHERE g.config_value IS DISTINCT FROM w.v OR g.value_type IS DISTINCT FROM 'INTEGER'
      OR g.value_status IS DISTINCT FROM 'REAL'
 )
 THEN RAISE EXCEPTION 'IG_WINDOW_AUTH_PARAMETER_SOURCE_DRIFT'; END IF;

 SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.scope,g.config_key)::text,'[]'))
 INTO v_config_before FROM public.lf_global_config g;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
 INTO v_rules_before FROM lf_ops.reglas r;
 SELECT jsonb_object_agg(codigo,to_jsonb(r)) INTO v_auth_before
 FROM lf_ops.reglas r
 WHERE codigo IN ('B2B-RULE-AUTH-018','B2B-RULE-AUTH-019','B2B-RULE-AUTH-020');
 IF (SELECT count(*) FROM jsonb_object_keys(coalesce(v_auth_before,'{}'::jsonb)))<>3
 THEN RAISE EXCEPTION 'IG_WINDOW_PROTECTED_AUTH_SOURCE_MISSING'; END IF;

 INSERT INTO public.lf_global_config
   (scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES(
   'AUTH','LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES','30','INTEGER','REAL',
   'Ventana movil de 30 minutos por cuenta de usuario, con tiempo servidor, para acumular los primeros 5 intentos fallidos de contrasena previos al primer bloqueo. Excluye OTP, MFA, rate limit y fallos de servicio. Los siguientes tramos usan 3 fallos adicionales, con bloqueo de 15/60/1440 minutos; reset escalonado de 1440 minutos desde el ultimo bloqueo es un reloj separado. Solo parametro: no activa enforcement ni autoriza produccion.',
   now()
 ) RETURNING * INTO v_new;
 IF v_new.scope IS DISTINCT FROM 'AUTH'
    OR v_new.config_key IS DISTINCT FROM 'LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES'
    OR v_new.config_value IS DISTINCT FROM '30'
    OR v_new.value_type IS DISTINCT FROM 'INTEGER'
    OR v_new.value_status IS DISTINCT FROM 'REAL'
 THEN RAISE EXCEPTION 'IG_WINDOW_INSERT_READBACK_FAILED'; END IF;

 IF (SELECT count(*) FROM public.lf_global_config)<>v_config_count_before+1
    OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>v_auth_count_before+1
    OR (SELECT count(*) FROM public.lf_global_config
      WHERE scope='AUTH' AND config_key='LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES')<>1
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
 THEN RAISE EXCEPTION 'IG_WINDOW_POSTIMAGE_COUNT_DRIFT'; END IF;

 SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.scope,g.config_key)::text,'[]'))
 INTO v_config_old_after FROM public.lf_global_config g
 WHERE NOT (g.scope='AUTH' AND g.config_key='LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES');
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
 INTO v_rules_after FROM lf_ops.reglas r;
 SELECT jsonb_object_agg(codigo,to_jsonb(r)) INTO v_auth_after
 FROM lf_ops.reglas r
 WHERE codigo IN ('B2B-RULE-AUTH-018','B2B-RULE-AUTH-019','B2B-RULE-AUTH-020');
 IF v_config_old_after IS DISTINCT FROM v_config_before
    OR v_rules_after IS DISTINCT FROM v_rules_before
    OR v_auth_after IS DISTINCT FROM v_auth_before
 THEN RAISE EXCEPTION 'IG_WINDOW_UNAUTHORIZED_EXISTING_ROW_MUTATION'; END IF;

 RAISE NOTICE 'IG_WINDOW_PARAMETER_OK config_before=% config_after=% auth_before=% auth_after=% rules_579 value_30',v_config_count_before,v_config_count_before+1,v_auth_count_before,v_auth_count_before+1;
END $ig_window$;
DO $ig_create_pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_ig_step70_functional_train_auto_v1(text)'::regprocedure))
   IS DISTINCT FROM '4828f5f746b414944fd32fd3d47d4510'
    OR md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
   IS DISTINCT FROM '1bbfff48a2780358fe84d982bfeca19f'
 THEN RAISE EXCEPTION 'IG_CREATE_DEPLOYED_SOURCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>579
    OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo IN (
      'PROP-B2B-AUTH-MFA-CONDITIONAL-001',
      'PROP-B2B-AUTH-TRUSTED-DEVICE-C-001',
      'PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001',
      'PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001'))
 THEN RAISE EXCEPTION 'IG_CREATE_RULE_PREIMAGE_DRIFT'; END IF;
 PERFORM pg_catalog.set_config('ig_chat8.rules_before',
   (SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r),true);
 RAISE NOTICE 'IG_CREATE_PREIMAGE_PASS rules_579 md5_current';
END $ig_create_pre$;

CREATE OR REPLACE FUNCTION public.lf_ig_step70_functional_train_auto_v1(p_parent text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'lf_ops', 'extensions'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;
        inp jsonb; prod jsonb; valid jsonb; profile jsonb; patch jsonb;
        rule text; source_sha text; patch_sha text; scope_digest text; candidate_digest text;
        train public.lf_ig_functional_train_evidence_v1%ROWTYPE;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
   AND target_type='PERFIL' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
   AND status='IN_PROGRESS'
   AND manifest->>'read_only'='true' AND manifest->>'no_write'='true'
   AND manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_PARENT_INVALID'); END IF;
 SELECT evidence_payload INTO inp FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO prod FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO valid FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 profile:=prod->'profile_output';
 patch:=profile#>'{deliverable_created,governed_rule_patch}';
 rule:=patch->>'rule_code';
 scope_digest:=inp->>'scope_authority_packet_sha256';
 candidate_digest:=prod->>'candidate_digest';
 IF inp IS NULL OR prod IS NULL OR valid->>'output_contract_result' IS DISTINCT FROM 'PASS'
    OR profile->>'worker' IS DISTINCT FROM 'product_director_lf'
    OR profile->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
    OR profile->>'self_verdict' IS DISTINCT FROM 'PASS'
    OR coalesce(patch->>'change_kind','') NOT IN ('FUNCTIONAL','CREATE')
    OR jsonb_typeof(patch->'changes')<>'object'
    OR coalesce(rule,'') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
    OR coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_PROFILE_OR_STEP_INVALID'); END IF;
 IF patch->>'change_kind'='CREATE' THEN
   -- A new rule must be absent; its declared screen must still be real.
   IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=rule)
      OR NOT EXISTS(
       SELECT 1 FROM lf_ops.pantallas s
       WHERE s.codigo=(e.manifest#>>'{screen_selection_result,selected_screen_code}')
      )
   THEN RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','AUTO_TRAIN_CREATE_ABSENCE_OR_SCREEN_INVALID'); END IF;
   source_sha:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||rule,'UTF8'),'sha256'),'hex');
 ELSE
  IF NOT EXISTS(
    SELECT 1 FROM lf_ops.reglas r
    JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
    JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id
    WHERE r.codigo=rule AND r.estado='VIGENTE'
      AND s.codigo=(e.manifest#>>'{screen_selection_result,selected_screen_code}')
  ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_VIGENTE_SCOPE_INVALID'); END IF;
  source_sha:=public.lf_asset_snapshot_sha_v1('REGLA',rule);
 END IF;
 patch_sha:=encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO train FROM public.lf_ig_functional_train_evidence_v1 t
 WHERE t.rule_code=rule AND t.source_snapshot_sha256=source_sha
   AND t.proposal_sha256=patch_sha
   AND t.pg_rollback_status='PASS'
   AND t.independent_readback_status='PASS'
   AND t.functional_checks_status='PASS'
   AND t.negative_checks_status='PASS'
   AND (patch->>'change_kind'='FUNCTIONAL' OR t.report_ref LIKE '%#RULE_CONTRACT_LEVEL')
   AND t.candidate_snapshot_sha256 ~ '^[0-9a-f]{64}$'
   AND t.pg_report_sha256 ~ '^[0-9a-f]{64}$'
   AND t.readback_sha256 ~ '^[0-9a-f]{64}$'
   AND t.check_manifest_sha256 ~ '^[0-9a-f]{64}$';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_EXACT_SHA_OR_PASS_MISSING'); END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.id=train.train_event_id
     AND evt.entidad_codigo=te.execution_id
     AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
     AND evt.origen='lf-migration-merge-train'
   WHERE te.execution_id=train.train_execution_id
     AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
     AND te.manifest->>'train_run_id'=train.train_run_id
     AND te.manifest->>'head_sha'=train.train_head_sha
     AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train.train_run_id
     AND evt.payload#>>'{receipt,train_run_id}'=train.train_run_id
     AND evt.payload#>>'{receipt,heads,final_head}'=train.train_head_sha
     AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
     AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
     AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
     AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
     AND evt.payload->>'receipt_sha256' ~ '^[0-9a-f]{64}$'
     AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
          =evt.payload->>'receipt_sha256'
 ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_SIGNED_RECEIPT_INVALID'); END IF;
 RETURN jsonb_build_object(
   'status','PASS','validator_status','PASS',
   'verdict','PASS_TRAIN_EVIDENCE_AUTOMATICO',
   'review_mode','TRAIN_EVIDENCE_AUTOMATICO','evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'judge_independence_status','NOT_ASSERTED','semantic_judge_performed',false,
   'reviewer_is_producer',false,'producer_independence_proven',false,'model_call_count',0,
   'candidate_sha256',substring(candidate_digest from 8),
   'scope_packet_sha256',substring(scope_digest from 8),
   'train_evidence',jsonb_build_object(
     'rule_code',rule,'change_kind',patch->>'change_kind',
     'evidence_scope',case when patch->>'change_kind'='CREATE' then 'RULE_CONTRACT_LEVEL' else 'FUNCTIONAL' end,
     'source_snapshot_sha256',source_sha,'proposal_sha256',patch_sha,
     'candidate_snapshot_sha256',train.candidate_snapshot_sha256,
     'train_run_id',train.train_run_id,'train_head_sha',train.train_head_sha,
     'train_execution_id',train.train_execution_id,
     'pg_rollback_status','PASS','independent_readback_status','PASS',
     'functional_checks_status','PASS','negative_checks_status','PASS',
     'pg_report_sha256',train.pg_report_sha256,'readback_sha256',train.readback_sha256,
     'check_manifest_sha256',train.check_manifest_sha256,'report_ref',train.report_ref),
   'result',jsonb_build_object(
     'verdict','PASS_TRAIN_EVIDENCE_AUTOMATICO',
     'candidate_sha256',substring(candidate_digest from 8),
     'scope_packet_sha256',substring(scope_digest from 8),
     'unsupported_claims','[]'::jsonb,'blocking_codes','[]'::jsonb)
 );
END
$function$;


CREATE OR REPLACE FUNCTION public.lf_ig_rule_owner_decide_v2(p_parent text, p_rule text, p_source_sha256 text, p_decision jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'lf_ops', 'extensions'
AS $function$
DECLARE
 v_uid uuid; v_owner record; v_parent public.lf_operation_execution%ROWTYPE;
 v_output jsonb; v_patch jsonb; v_kind text; v_source text; v_sha text;
 v_judge jsonb; v_state text; v_id uuid; v_screen text;
 v_skill text; v_skill_input jsonb; v_invoked jsonb; v_final jsonb;
 v_verdict text; v_decisor text; v_proponente text; v_phrase text;
 v_decision_date timestamptz; v_decision_sha text; v_decision_record jsonb;
BEGIN

 IF p_decision IS NULL OR jsonb_typeof(p_decision)<>'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_decision))<>2
    OR NOT (p_decision ?& ARRAY['usuario','veredicto'])
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_RECORD_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(p_decision) e
   WHERE jsonb_typeof(e.value)<>'string')
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_FIELD_TYPE_INVALID'; END IF;
 v_verdict:=p_decision->>'veredicto';
 v_decisor:=CASE WHEN p_decision->>'usuario'='Cristhian Lujan' THEN 'Cristhian Luján' ELSE p_decision->>'usuario' END;
 v_phrase:='OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE';
 IF v_decisor IS DISTINCT FROM 'Cristhian Luján'
    OR v_verdict NOT IN ('APROBAR','RECHAZAR')
    OR p_rule !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR p_source_sha256 !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_INPUT_INVALID'; END IF;
 v_decision_date:=clock_timestamp();
 SELECT * INTO v_owner FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF' AND owner_name=v_decisor
   AND status='TEMP_DOCUMENTARY_ACTIVE'
   AND identity_mode='UNVERIFIED_CHAT_DECLARATION';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_OWNER_DECLARATION_MISSING'; END IF;
 v_uid:=v_owner.owner_sub; -- internal placeholder, NOT an authenticated UID
 SELECT * INTO v_parent FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
   AND status='IN_PROGRESS' AND target_type='PERFIL'
   AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
   AND manifest->>'read_only'='true'
   AND manifest->>'no_write'='true'
   AND manifest->'router_profile_handoff'->'router_authorization_receipt'
       ->>'profile_execution_allowed'='true';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_OWNER_PARENT_NOT_ADMITTED'; END IF;
 IF v_decision_date < v_parent.started_at-interval '5 minutes'
    OR v_decision_date > now()+interval '5 minutes'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_DATE_OUT_OF_SCOPE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
   WHERE execution_id=p_parent AND step_id='input_validate'
     AND status='STEP_PASS_WITH_EVIDENCE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
   WHERE execution_id=p_parent AND step_id='output_validate'
     AND status='STEP_PASS_WITH_EVIDENCE'
     AND evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'LF_IG_OWNER_PROFILE_IG_OR_OUTPUT_UNVERIFIED'; END IF;
 SELECT evidence_payload->'semantic_judge_result' INTO v_judge
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='semantic_judge'
  AND status='STEP_PASS_WITH_EVIDENCE'
  AND evidence_payload->'blocking_codes'='[]'::jsonb;
 IF coalesce(v_judge->>'verdict','') <> 'PASS_INDEPENDENT_SEMANTIC'
    AND NOT (
      v_judge->>'verdict'='PASS_TRAIN_EVIDENCE_AUTOMATICO'
      AND v_judge->>'review_mode'='TRAIN_EVIDENCE_AUTOMATICO'
      AND v_judge IS NOT DISTINCT FROM public.lf_ig_step70_functional_train_auto_v1(p_parent)
    )
 THEN RAISE EXCEPTION 'LF_IG_OWNER_VERIFIED_SEMANTIC_OR_FUNCTIONAL_TRAIN_REQUIRED'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_output
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile'
   AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_output->'deliverable_created'->'governed_rule_patch';
 IF v_output->>'worker' <> 'product_director_lf'
    OR v_output->>'output_type' <> 'PRODUCT_DIRECTION_SPEC'
    OR v_output->>'self_verdict' <> 'PASS'
    OR v_patch->>'rule_code' IS DISTINCT FROM p_rule
    OR jsonb_typeof(v_patch->'changes') <> 'object'
    OR (SELECT count(*) FROM jsonb_object_keys(v_patch->'changes'))=0
 THEN RAISE EXCEPTION 'LF_IG_OWNER_EXACT_PROFILE_PATCH_REQUIRED'; END IF;
 v_proponente:=nullif(btrim(v_output#>>'{deliverable_created,product_decision,proposed_by}'),'');
 -- Mandatory origin-bound proposer declaration from the RAW profile output.
 -- This prevents one recorded actor from filling both roles in the evidence.
 -- Without Auth this is documentary separation, not physical-person proof.
 IF v_proponente IS NULL OR v_proponente=v_decisor
 THEN RAISE EXCEPTION 'LF_IG_OWNER_SELF_APPROVAL_FORBIDDEN'; END IF;
 v_screen:=v_parent.manifest->'screen_selection_result'->>'selected_screen_code';
 IF nullif(v_screen,'') IS NULL
 THEN RAISE EXCEPTION 'LF_IG_OWNER_SCREEN_SCOPE_MISSING'; END IF;
 SELECT estado INTO v_state FROM lf_ops.reglas WHERE codigo=p_rule;
 IF NOT FOUND THEN
   v_kind:='CREATE';
   v_source:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||p_rule,'UTF8'),'sha256'),'hex');
 ELSE
   v_kind:=CASE WHEN v_state='CANDIDATO' THEN 'UPDATE_CANDIDATE'
                WHEN v_state='VIGENTE' THEN 'CORRECT_VIGENTE' ELSE NULL END;
   v_source:=public.lf_asset_snapshot_sha_v1('REGLA',p_rule);
   IF NOT EXISTS (SELECT 1 FROM lf_ops.pantallas s
     JOIN lf_ops.reglas_pantallas rp ON rp.pantalla_id=s.id
     JOIN lf_ops.reglas r ON r.id=rp.regla_id
     WHERE s.codigo=v_screen AND r.codigo=p_rule)
   THEN RAISE EXCEPTION 'LF_IG_OWNER_RULE_NOT_IN_SCREEN'; END IF;
 END IF;
 IF v_kind IS NULL OR v_source IS DISTINCT FROM p_source_sha256
 THEN RAISE EXCEPTION 'LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT'; END IF;
 IF (v_kind='CREATE' AND v_patch->>'change_kind'<>'CREATE')
   OR (v_kind='UPDATE_CANDIDATE' AND v_patch->>'change_kind'<>'DOCUMENTARY_ONLY')
   OR (v_kind='CORRECT_VIGENTE' AND v_patch->>'change_kind' NOT IN ('DOCUMENTARY_ONLY','FUNCTIONAL'))
 THEN RAISE EXCEPTION 'LF_IG_OWNER_CHANGE_KIND_MISMATCH'; END IF;
 v_sha:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
 v_decision_record:=jsonb_build_object(
  'codigo_regla',p_rule,'propuesta_sha256',v_sha,'veredicto',v_verdict,
  'decisor',v_decisor,'fecha',to_char(v_decision_date AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'frase_literal',v_phrase);
 v_decision_sha:=encode(extensions.digest(convert_to(v_decision_record::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_owner_decision_v2(
  project_code,owner_sub,decisor,proponente,decision_date,literal_phrase,
  decision_record,decision_record_sha256,parent_execution_id,rule_code,kind,
  source_sha256,proposal_sha256,verdict,approved_patch)
 VALUES('LF',v_uid,v_decisor,v_proponente,v_decision_date,v_phrase,
   v_decision_record,v_decision_sha,p_parent,p_rule,v_kind,
   v_source,v_sha,v_verdict,v_patch)
 ON CONFLICT(parent_execution_id,rule_code,kind) DO NOTHING
 RETURNING decision_id INTO v_id;
 IF v_id IS NULL
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_ALREADY_RECORDED_NO_OVERRIDE'; END IF;
 IF v_verdict='RECHAZAR' THEN
   RETURN jsonb_build_object('status','RECHAZADO','decision_id',v_id,
     'decision_record',v_decision_record,'decision_record_sha256',v_decision_sha,
     'decisor',v_decisor,'proponente',v_proponente,'identity_verified',false,
     'rule_code',p_rule,'source_sha256',v_source,'proposal_sha256',v_sha,
     'write_performed',false);
 END IF;
 -- Single owner decision triggers official skill invoker, seven-step writer,
 -- promotion and canonical readback in ONE transaction. On any failure,
 -- RAISE rolls back approval + child + candidate/active mutation atomically.
 v_skill:=case when v_kind='CREATE' then 'RULE_CREATE_APPLY' else 'RULE_UPDATE_APPLY' end;
 v_skill_input:=jsonb_build_object(
   'regla_codigo',p_rule,'analysis_snapshot_sha256',v_source,
   'decision_id',v_output->'deliverable_created'->'product_decision'->>'decision_id',
   'candidate_patch',v_patch,'owner_decision_id',v_id);
 IF nullif(v_skill_input->>'decision_id','') IS NULL THEN
   RAISE EXCEPTION 'LF_IG_OWNER_PROFILE_DECISION_ID_MISSING'; END IF;
 v_invoked:=public.lf_skill_invoke_v1(v_skill,p_parent,v_skill_input);
 IF v_invoked->>'status'<>'COMPLETED'
    OR nullif(v_invoked->>'child_execution_id','') IS NULL
 THEN RAISE EXCEPTION 'LF_IG_OWNER_OFFICIAL_SKILL_INVOKE_FAILED:%',
      coalesce(v_invoked->>'blocking_code','UNKNOWN'); END IF;
 IF v_kind='CREATE' THEN
   -- RULE_CREATE_APPLY already wrote/closed the child with 7/7 real steps.
   -- Preserve CANDIDATO, pending decision, and never call the promotion finalizer.
   IF NOT EXISTS (
     SELECT 1
     FROM public.lf_ig_rule_change_v2 ch
     JOIN public.lf_operation_execution ce
       ON ce.execution_id=ch.child_execution_id
     JOIN lf_ops.reglas r ON r.codigo=ch.rule_code
     WHERE ch.child_execution_id=v_invoked->>'child_execution_id'
       AND ch.parent_execution_id=p_parent
       AND ch.rule_code=p_rule AND ch.kind='CREATE'
       AND ch.owner_decision_id=v_id AND ch.state='CANDIDATE_VERIFIED'
       AND ch.source_snapshot_sha256=v_source
       AND ch.approved_patch=v_patch
       AND ch.candidate_snapshot_sha256=public.lf_asset_snapshot_sha_v1('REGLA',p_rule)
       AND ce.operation_code='CREACION_REGLA_LF'
       AND ce.status='COMPLETED' AND ce.target_code=p_rule
       AND ce.created_by_execution_id=p_parent
       AND r.estado='CANDIDATO' AND r.pendiente_decision=true
       AND r.created_by=ce.execution_id
   ) OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_invoked->>'child_execution_id'
           AND status='PASS_CLEAN')<>7
     OR EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1
       WHERE rule_code=p_rule AND request_execution_id=p_parent)
   THEN RAISE EXCEPTION 'LF_IG_OWNER_CREATE_CANDIDATE_CHILD_OR_NO_PROMOTION_READBACK_FAILED'; END IF;
   RETURN jsonb_build_object(
     'status','APPROVED_AND_CANDIDATO_VERIFIED',
     'decision_id',v_id,'decisor',v_decisor,'proponente',v_proponente,
     'decision_record',v_decision_record,'decision_record_sha256',v_decision_sha,
     'identity_verified',false,'identity_mode','USERNAME_ONLY_UNVERIFIED',
     'rule_code',p_rule,'kind',v_kind,
     'source_sha256',v_source,'proposal_sha256',v_sha,
     'child_execution_id',v_invoked->>'child_execution_id',
     'candidate_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',p_rule),
     'candidate_status','CANDIDATO','pending_decision',true,
     'production_authorized',false,'promotion_authorized',false,
     'profile_execution_id',p_parent,
     'next_action','OFFICIAL_PROFILE_STEP80_REPORT_READBACK_AND_CLOSE',
     'profile_run_closed',false,'write_performed',true);
 END IF;
 v_final:=public.lf_ig_rule_finalize_v2(v_invoked->>'child_execution_id');
 IF v_final->>'status'<>'VIGENTE_VERIFIED'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_GOVERNED_FINALIZE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPROVED_AND_VIGENTE_VERIFIED',
   'decision_id',v_id,'decisor',v_decisor,'proponente',v_proponente,
   'decision_record',v_decision_record,'decision_record_sha256',v_decision_sha,
   'identity_verified',false,'identity_mode','USERNAME_ONLY_UNVERIFIED',
   'rule_code',p_rule,'kind',v_kind,
   'source_sha256',v_source,'proposal_sha256',v_sha,
   'child_execution_id',v_invoked->>'child_execution_id',
   'finalized_snapshot_sha256',v_final->>'result_snapshot_sha256',
   'profile_execution_id',p_parent,
   'next_action','OFFICIAL_PROFILE_STEP80_REPORT_READBACK_AND_CLOSE',
   'profile_run_closed',false,'write_performed',true);
END
$function$;

DO $ig_create_post$
DECLARE v70 text; vOwner text;
BEGIN
 SELECT pg_get_functiondef('public.lf_ig_step70_functional_train_auto_v1(text)'::regprocedure)
 INTO v70;
 SELECT pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure)
 INTO vOwner;
 IF position('AUTO_TRAIN_CREATE_ABSENCE_OR_SCREEN_INVALID' IN v70)=0
    OR position('RULE_CONTRACT_LEVEL' IN v70)=0
    OR position('APPROVED_AND_CANDIDATO_VERIFIED' IN vOwner)=0
    OR position('LF_IG_OWNER_CREATE_CANDIDATE_CHILD_OR_NO_PROMOTION_READBACK_FAILED' IN vOwner)=0
 THEN RAISE EXCEPTION 'IG_CREATE_DEPLOYED_FUNCTION_READBACK_INVALID'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>579 OR
  (SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r)
     IS DISTINCT FROM pg_catalog.current_setting('ig_chat8.rules_before')
 THEN RAISE EXCEPTION 'IG_CREATE_UNAUTHORIZED_RULE_DELTA'; END IF;
 RAISE NOTICE 'IG_CREATE_GATE_READY_RULES_579_UNCHANGED_CREATE_CANDIDATO_ONLY';
END $ig_create_post$;
-- One server-side AUTH integer resolver. Rule text/config stores keys, not values.
-- SECURITY DEFINER reads the existing no-policy RLS table; no anon/user exposure.
DO $ig_auth_reader_pre$
BEGIN
 IF to_regprocedure('public.lf_auth_config_integer_v1(text)') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_AUTH_READER_ALREADY_EXISTS_UNEXPECTED'; END IF;
END $ig_auth_reader_pre$;

CREATE FUNCTION public.lf_auth_config_integer_v1(p_config_key text)
RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $ig_auth_reader$
DECLARE v_value text;
BEGIN
 IF coalesce(p_config_key,'') !~ '^[A-Z][A-Z0-9_]{2,99}$'
 THEN RAISE EXCEPTION 'IG_AUTH_CONFIG_KEY_INVALID'; END IF;
 SELECT g.config_value INTO v_value
 FROM public.lf_global_config g
 WHERE g.scope='AUTH' AND g.config_key=p_config_key
   AND g.value_type='INTEGER' AND g.value_status='REAL'
   AND g.valid_from<=now()
 ORDER BY g.valid_from DESC,g.created_at DESC LIMIT 1;
 IF v_value IS NULL OR v_value !~ '^[0-9]{1,9}$'
 THEN RAISE EXCEPTION 'IG_AUTH_CONFIG_INTEGER_MISSING_OR_INVALID:%',p_config_key; END IF;
 RETURN v_value::integer;
END
$ig_auth_reader$;

REVOKE ALL ON FUNCTION public.lf_auth_config_integer_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_auth_config_integer_v1(text)
 TO service_role;

DO $ig_auth_reader_post$
DECLARE v_key text;
BEGIN
 FOREACH v_key IN ARRAY ARRAY[
  'MFA_DEVICE_IDLE_DAYS','MFA_PASSWORD_AGE_MONTHS',
  'LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES',
  'LOGIN_LOCKOUT_ATTEMPTS_1','LOGIN_LOCKOUT_ATTEMPTS_2','LOGIN_LOCKOUT_ATTEMPTS_3',
  'LOGIN_LOCKOUT_MINUTES_1','LOGIN_LOCKOUT_MINUTES_2','LOGIN_LOCKOUT_MINUTES_3',
  'LOGIN_LOCKOUT_RESET_MINUTES'] LOOP
  IF public.lf_auth_config_integer_v1(v_key) IS NULL THEN
   RAISE EXCEPTION 'IG_AUTH_READER_PARAM_MISSING:%',v_key;
  END IF;
 END LOOP;
 IF has_function_privilege('anon','public.lf_auth_config_integer_v1(text)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_auth_config_integer_v1(text)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.lf_auth_config_integer_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_AUTH_READER_ACL_INVALID'; END IF;
 RAISE NOTICE 'IG_AUTH_READER_10_KEYS_VERIFIED_NO_CLIENT_EXECUTE';
END $ig_auth_reader_post$;

COMMIT;
