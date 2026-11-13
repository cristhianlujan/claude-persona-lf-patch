-- LF Input Governance rule lifecycle V2. ONE governed migration, NO historical RUN edits.
-- Deployment lane: ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
-- TEMPORARY documentary owner identity (no Supabase Auth/JWT/AAL2).
-- Only an official service-role route may submit decisions with exact receipts.
-- Final-production identity verification is explicitly OUT OF SCOPE.
-- No historical RUN changes. PostgreSQL 17+ syntax.
BEGIN;

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
       IS DISTINCT FROM 'c311087befe49afb2affa668231c9dd1'
     OR md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure))
       IS DISTINCT FROM 'ac7e351e1834cbfb91aabf26e1a04a8d'
     OR md5(pg_get_functiondef('public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)'::regprocedure))
       IS DISTINCT FROM 'dc97a0e7c65b65ae1951e2da86c6238b'
     OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
       IS DISTINCT FROM 'd7fe763c999db6f6259b6b1e2bd69644'
     OR md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
       IS DISTINCT FROM '16e45f40dad5cecc215a2f978be47728'
     OR md5(pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
       IS DISTINCT FROM 'fe08a25c8e3c023d7181194d2dfdee0d'
  THEN RAISE EXCEPTION 'LF_IG_V2_SOURCE_PREIMAGE_DRIFT'; END IF;
  IF (SELECT count(*) FROM public.lf_skill_catalog_v1
      WHERE (skill_code='RULE_CREATE_APPLY' AND opener_fn IS NULL
        AND required_operation='CREACION_REGLA_LF' AND effect='WRITE_GOVERNED')
         OR (skill_code='RULE_UPDATE_APPLY'
        AND opener_fn='lf_skill_o_rule_update_v1' AND effect='WRITE_GOVERNED')) <> 2
  THEN RAISE EXCEPTION 'LF_IG_V2_SKILL_CATALOG_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_operation_registry
             WHERE operation_code='PROMOCION_REGLA_LF')
      OR to_regclass('public.lf_ig_rule_change_v2') IS NOT NULL
      OR to_regclass('public.lf_ig_project_owner_v2') IS NOT NULL
  THEN RAISE EXCEPTION 'LF_IG_V2_ALREADY_INSTALLED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_mode_bindings
      WHERE operation_code='CREACION_REGLA_LF' AND task_mode='CREATE_NEW'
        AND execution_mode='GOVERNED' AND allowed AND write_allowed AND status='ACTIVE')
   OR NOT EXISTS (SELECT 1 FROM public.lf_operation_mode_bindings
      WHERE operation_code='ACTUALIZACION_REGLA_LF' AND task_mode='REMEDIATE_EXISTING'
        AND execution_mode='GOVERNED' AND allowed AND write_allowed AND status='ACTIVE')
  THEN RAISE EXCEPTION 'LF_IG_V2_OPERATION_MODE_MISSING'; END IF;
END $preflight$;

-- TEMPORARY LF documentary owner declaration from the conversation.
-- owner_sub below is a NON-IDENTITY internal placeholder, not Supabase Auth.
-- Only LF is seeded; SALY has no owner authorization.
-- Proposer remains separate; no claim of physical-identity verification.
CREATE TABLE public.lf_ig_project_owner_v2(
  project_code text PRIMARY KEY CHECK (project_code IN ('LF','SALY')),
  owner_sub uuid NOT NULL,
  owner_name text NOT NULL CHECK(owner_name='Cristhian Luján'),
  identity_mode text NOT NULL DEFAULT 'UNVERIFIED_CHAT_DECLARATION'
    CHECK(identity_mode='UNVERIFIED_CHAT_DECLARATION'),
  owner_profile_code text NOT NULL CHECK (length(btrim(owner_profile_code))>3
    AND owner_profile_code NOT IN ('SUPER_ADMIN','LF_SUPER_ADMIN')),
  authority_receipt_sha256 text NOT NULL CHECK (authority_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  status text NOT NULL DEFAULT 'CANDIDATE'
    CHECK(status IN ('CANDIDATE','TEMP_DOCUMENTARY_ACTIVE','SUSPENDED')),
  source_execution_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.lf_ig_project_owner_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_ig_project_owner_v2 FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO public.lf_ig_project_owner_v2(
  project_code,owner_sub,owner_name,owner_profile_code,
  authority_receipt_sha256,status,source_execution_id)
VALUES('LF','00000000-0000-4000-8000-000000000001'::uuid,
  'Cristhian Luján','PERFIL-PRODUCT-DIRECTOR-LF',
  encode(extensions.digest(convert_to(
    'CHAT_DECLARATION_OWNER_CRISTHIAN_LUJAN_2026_11_12_LF_TEMPORAL','UTF8'),
    'sha256'),'hex'),
  'TEMP_DOCUMENTARY_ACTIVE','OWNER_CHAT_TEMPORARY_2026-11-12');


CREATE TABLE public.lf_ig_owner_decision_v2(
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_code text NOT NULL REFERENCES public.lf_ig_project_owner_v2(project_code),
  owner_sub uuid NOT NULL,
  decisor text NOT NULL CHECK(decisor='Cristhian Luján'),
  proponente text NOT NULL CHECK(proponente<>'Cristhian Luján'),
  decision_date timestamptz NOT NULL,
  literal_phrase text NOT NULL CHECK(length(btrim(literal_phrase))>=6),
  decision_record jsonb NOT NULL,
  decision_record_sha256 text NOT NULL CHECK(
    decision_record_sha256 ~ '^[0-9a-f]{64}$'),
  identity_mode text NOT NULL DEFAULT 'UNVERIFIED_CHAT_DECLARATION'
    CHECK(identity_mode='UNVERIFIED_CHAT_DECLARATION'),
  parent_execution_id text NOT NULL,
  rule_code text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('CREATE','UPDATE_CANDIDATE','CORRECT_VIGENTE')),
  source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
  proposal_sha256 text NOT NULL CHECK(proposal_sha256 ~ '^[0-9a-f]{64}$'),
  verdict text NOT NULL CHECK(verdict IN ('APROBAR','RECHAZAR')),
  approved_patch jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(parent_execution_id,rule_code,kind)
);
ALTER TABLE public.lf_ig_owner_decision_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_ig_owner_decision_v2 FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE public.lf_ig_rule_change_v2(
  change_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_execution_id text NOT NULL,
  child_execution_id text NOT NULL UNIQUE,
  rule_code text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('CREATE','UPDATE_CANDIDATE','CORRECT_VIGENTE')),
  owner_decision_id uuid NOT NULL REFERENCES public.lf_ig_owner_decision_v2(decision_id),
  source_snapshot_sha256 text NOT NULL,
  candidate_snapshot_sha256 text,
  finalized_snapshot_sha256 text,
  approved_patch jsonb NOT NULL,
  state text NOT NULL CHECK(state IN ('STAGED','CANDIDATE_VERIFIED','VIGENTE_VERIFIED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  finalized_at timestamptz,
  UNIQUE(parent_execution_id,rule_code)
);
ALTER TABLE public.lf_ig_rule_change_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_ig_rule_change_v2 FROM PUBLIC, anon, authenticated, service_role;

-- LF TEMPORARY documentary decision. No JWT/AAL2 or Supabase Auth identity.
-- The decision must be supplied through the official service_role transport.
-- This is NOT a verified human identity. Production requires separate IAM.
CREATE FUNCTION public.lf_ig_rule_owner_decide_v2(
  p_parent text,p_rule text,p_source_sha256 text,p_decision jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $fn$
DECLARE
 v_uid uuid; v_owner record; v_parent public.lf_operation_execution%ROWTYPE;
 v_output jsonb; v_patch jsonb; v_kind text; v_source text; v_sha text;
 v_judge jsonb; v_state text; v_id uuid; v_screen text;
 v_skill text; v_skill_input jsonb; v_invoked jsonb; v_final jsonb;
 v_verdict text; v_decisor text; v_proponente text; v_phrase text;
 v_decision_date timestamptz; v_decision_sha text;
BEGIN

 IF p_decision IS NULL OR jsonb_typeof(p_decision)<>'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_decision))<>6
    OR NOT (p_decision ?& ARRAY['codigo_regla','propuesta_sha256',
        'veredicto','decisor','fecha','frase_literal'])
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_RECORD_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(p_decision) e
   WHERE jsonb_typeof(e.value)<>'string')
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_FIELD_TYPE_INVALID'; END IF;
 v_verdict:=p_decision->>'veredicto';
 v_decisor:=p_decision->>'decisor';
 v_phrase:=p_decision->>'frase_literal';
 IF v_decisor IS DISTINCT FROM 'Cristhian Luján'
    OR v_verdict NOT IN ('APROBAR','RECHAZAR')
    OR p_decision->>'codigo_regla' IS DISTINCT FROM p_rule
    OR coalesce(p_decision->>'propuesta_sha256','') !~ '^[0-9a-f]{64}$'
    OR length(btrim(coalesce(v_phrase,'')))<6
    OR p_rule !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR p_source_sha256 !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_INPUT_INVALID'; END IF;
 IF coalesce(p_decision->>'fecha','') !~
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_DATE_INVALID'; END IF;
 v_decision_date:=(p_decision->>'fecha')::timestamptz;
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
   AND manifest->>'no_write'='true' AND manifest->>'no_promotion'='true'
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
 THEN RAISE EXCEPTION 'LF_IG_OWNER_INDEPENDENT_JUDGE_REQUIRED'; END IF;
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
 IF p_decision->>'propuesta_sha256' IS DISTINCT FROM v_sha
 THEN RAISE EXCEPTION 'LF_IG_OWNER_PROPOSAL_SHA256_MISMATCH'; END IF;
 v_decision_sha:=encode(extensions.digest(convert_to(p_decision::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_owner_decision_v2(
  project_code,owner_sub,decisor,proponente,decision_date,literal_phrase,
  decision_record,decision_record_sha256,parent_execution_id,rule_code,kind,
  source_sha256,proposal_sha256,verdict,approved_patch)
 VALUES('LF',v_uid,v_decisor,v_proponente,v_decision_date,v_phrase,
   p_decision,v_decision_sha,p_parent,p_rule,v_kind,
   v_source,v_sha,v_verdict,v_patch)
 ON CONFLICT(parent_execution_id,rule_code,kind) DO NOTHING
 RETURNING decision_id INTO v_id;
 IF v_id IS NULL
 THEN RAISE EXCEPTION 'LF_IG_OWNER_DECISION_ALREADY_RECORDED_NO_OVERRIDE'; END IF;
 IF v_verdict='RECHAZAR' THEN
   RETURN jsonb_build_object('status','RECHAZADO','decision_id',v_id,
     'decision_record',p_decision,'decision_record_sha256',v_decision_sha,
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
 v_final:=public.lf_ig_rule_finalize_v2(v_invoked->>'child_execution_id');
 IF v_final->>'status'<>'VIGENTE_VERIFIED'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_GOVERNED_FINALIZE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPROVED_AND_VIGENTE_VERIFIED',
   'decision_id',v_id,'decisor',v_decisor,'proponente',v_proponente,
   'decision_record',p_decision,'decision_record_sha256',v_decision_sha,
   'identity_verified',false,'identity_mode','UNVERIFIED_CHAT_DECLARATION',
   'rule_code',p_rule,'kind',v_kind,
   'source_sha256',v_source,'proposal_sha256',v_sha,
   'child_execution_id',v_invoked->>'child_execution_id',
   'finalized_snapshot_sha256',v_final->>'result_snapshot_sha256',
   'profile_execution_id',p_parent,
   'next_action','OFFICIAL_PROFILE_STEP80_REPORT_READBACK_AND_CLOSE',
   'profile_run_closed',false,'write_performed',true);
END
$fn$;

-- Every child must use the SAME fresh parent RAW, persisted judge and an
-- owner decision recorded documentarily, not by Auth. The approved patch is
-- read from SQL, never from a caller-provided claim; official transport only.
CREATE FUNCTION public.lf_ig_rule_child_guard_v2(
 p_child text,p_input jsonb,p_parent text,p_run text,p_request_sha text,p_skill text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $fn$
DECLARE v_par public.lf_operation_execution%ROWTYPE;
 v_inv public.lf_skill_invocation_v1%ROWTYPE; v_dec public.lf_ig_owner_decision_v2%ROWTYPE;
 v_patch jsonb; v_output jsonb; v_sha text; v_source text;
BEGIN
 SELECT * INTO v_par FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
 AND status='IN_PROGRESS' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND manifest->>'read_only'='true' AND manifest->>'no_write'='true'
 AND manifest->>'no_promotion'='true';
 IF NOT FOUND OR p_request_sha IS DISTINCT FROM v_par.request_sha256
 THEN RAISE EXCEPTION 'LF_IG_CHILD_PARENT_REQUEST_MISMATCH'; END IF;
 SELECT * INTO v_inv FROM public.lf_skill_invocation_v1
 WHERE skill_run_id=p_run AND skill_code=p_skill
 AND child_execution_id=p_child AND parent_execution_id=p_parent
 AND profile_code=v_par.target_code AND status='COMPLETED'
 AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex');
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_CHILD_INVOCATION_MISMATCH'; END IF;
 SELECT * INTO v_dec FROM public.lf_ig_owner_decision_v2
 WHERE decision_id=(p_input->>'owner_decision_id')::uuid
 AND parent_execution_id=p_parent
 AND rule_code=p_input->>'regla_codigo' AND verdict='APROBAR';
 IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.lf_ig_project_owner_v2
    WHERE project_code='LF' AND owner_sub=v_dec.owner_sub AND owner_name=v_dec.decisor
      AND status='TEMP_DOCUMENTARY_ACTIVE')
 THEN RAISE EXCEPTION 'LF_IG_CHILD_OWNER_DOCUMENTARY_APPROVAL_NOT_RECORDED'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_output
 FROM public.lf_operation_execution_steps WHERE execution_id=p_parent
 AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_output->'deliverable_created'->'governed_rule_patch';
 v_sha:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
 IF v_patch IS DISTINCT FROM v_dec.approved_patch
    OR v_patch IS DISTINCT FROM p_input->'candidate_patch'
    OR v_sha IS DISTINCT FROM v_dec.proposal_sha256
    OR v_dec.source_sha256 IS DISTINCT FROM p_input->>'analysis_snapshot_sha256'
    OR v_dec.decision_record->>'propuesta_sha256' IS DISTINCT FROM v_sha
    OR v_dec.decision_record->>'codigo_regla' IS DISTINCT FROM v_dec.rule_code
    OR v_dec.decision_record->>'decisor' IS DISTINCT FROM v_dec.decisor
    OR v_dec.decision_record->>'veredicto' IS DISTINCT FROM 'APROBAR'
    OR v_output#>>'{deliverable_created,product_decision,proposed_by}'
        IS DISTINCT FROM v_dec.proponente
    OR encode(extensions.digest(convert_to(v_dec.decision_record::text,'UTF8'),'sha256'),'hex')
        IS DISTINCT FROM v_dec.decision_record_sha256
 THEN RAISE EXCEPTION 'LF_IG_CHILD_APPROVED_PATCH_SHA_DRIFT'; END IF;
 v_source:=coalesce(public.lf_asset_snapshot_sha_v1('REGLA',v_dec.rule_code),
    encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v_dec.rule_code,'UTF8'),'sha256'),'hex'));
 IF v_source IS DISTINCT FROM v_dec.source_sha256
 THEN RAISE EXCEPTION 'LF_IG_CHILD_SOURCE_STALE'; END IF;
 RETURN jsonb_build_object('decision_id',v_dec.decision_id,'kind',v_dec.kind,
   'rule_code',v_dec.rule_code,'source_sha256',v_source,'proposal_sha256',v_sha,
   'decision_record_sha256',v_dec.decision_record_sha256,
   'decision_record',v_dec.decision_record,'patch',v_patch);
END
$fn$;

CREATE FUNCTION public.lf_ig_rule_step_record_v2(
 p_child text,p_operation text,p_step text,p_ref text,p_evidence jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE v jsonb;
BEGIN
 IF p_operation NOT IN ('CREACION_REGLA_LF','ACTUALIZACION_REGLA_LF')
 THEN RAISE EXCEPTION 'LF_IG_STEP_OPERATION_INVALID'; END IF;
 v:=public.lf_record_operation_step_core_v1(
 p_child,p_step,p_ref,p_evidence,p_child,p_operation,'REGLA',
 'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
 jsonb_build_object('valid',true,'code','LF_IG_SERVER_VALIDATED_V2',
   'server_assertions',jsonb_build_array('required_evidence_present'),
   'server_hard_fails','[]'::jsonb),false,'lf_ig_rule_step_record_v2');
 IF v->>'outcome'<>'STEP_RECORDED' OR v->>'status'<>'PASS_CLEAN'
 THEN RAISE EXCEPTION 'LF_IG_STEP_NOT_CLEAN:%:%',p_step,coalesce(v->>'code',v->>'status','UNKNOWN'); END IF;
END
$fn$;

CREATE FUNCTION public.lf_skill_o_rule_create_v2(
 p_child text,p_input jsonb,p_parent text,p_run text,p_request_sha text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $fn$
DECLARE v jsonb; c jsonb; w jsonb; res jsonb; after_row jsonb;
 v_rule text; v_source text; v_after text; v_ref text;
BEGIN
 v:=public.lf_ig_rule_child_guard_v2(p_child,p_input,p_parent,p_run,p_request_sha,'RULE_CREATE_APPLY');
 IF v->>'kind'<>'CREATE' THEN RAISE EXCEPTION 'LF_IG_CREATE_KIND_INVALID'; END IF;
 v_rule:=v->>'rule_code';v_source:=v->>'source_sha256';c:=v->'patch'->'changes';
 IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo=v_rule)<>0 OR
    coalesce(c->>'categoria','')='' OR length(btrim(coalesce(c->>'titulo','')))<8 OR
    length(btrim(coalesce(c->>'descripcion','')))<8 OR
    jsonb_typeof(c->'es_transversal') IS DISTINCT FROM 'boolean'
 THEN RAISE EXCEPTION 'LF_IG_CREATE_FIELD_OR_ABSENCE_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN
  ('categoria','titulo','descripcion','razon','valor_config','es_transversal','origen'))
 THEN RAISE EXCEPTION 'LF_IG_CREATE_PROTECTED_FIELDS'; END IF;
 res:=public.fn_lf_operation_reserve_execution_v1(
  p_child,'CREACION_REGLA_LF','REGLA',v_rule,
  'skill-child-v1:'||p_run,p_request_sha,p_parent,NULL,NULL,
  jsonb_build_object('profile_handoff',jsonb_build_object(
   'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
   'analysis_snapshot_sha256',v_source,'approved_owner_decision_id',v->>'decision_id',
   'owner_decision_record_sha256',v->>'decision_record_sha256',
   'production_allowed',false,'promotion_authorized',false));
 IF res->>'result'<>'RESERVED_NEW_EXECUTION' THEN
 RAISE EXCEPTION 'LF_IG_CREATE_CHILD_RESERVATION_NOT_NEW'; END IF;
 v_ref:='SKILLRUN:'||p_run;
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','ekb_preflight',v_ref||'/10',
   jsonb_build_object('ekb_refs',jsonb_build_array('INPUT_GOVERNANCE_LF_V1_4'),'execution_binding',p_child));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','classify',v_ref||'/20',
   jsonb_build_object('rule_code',v_rule,'category',c->>'categoria','candidate_classification','REGLA_CREATE'));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','existing_check',v_ref||'/30',
   jsonb_build_object('rule_code',v_rule,'existing_count',0,'expected_existence','ZERO'));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','destination_validate',v_ref||'/40',
   jsonb_build_object('destination_schema','lf_ops','destination_table','reglas','unique_code_guard',true));
 w:=public.lf_regla_candidate_write_v1(
  p_child,'REGLA_CREATE',v_rule,c->>'categoria',c->>'titulo',c->>'descripcion',
  c->>'razon',c->'valor_config',(c->>'es_transversal')::boolean,c->>'origen');
 IF w->>'result'<>'RULE_CANDIDATE_CREATED' OR w->'after'->>'estado'<>'CANDIDATO'
 THEN RAISE EXCEPTION 'LF_IG_CREATE_OFFICIAL_WRITER_FAILED'; END IF;
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','candidate_write',v_ref||'/50',
   jsonb_build_object('execution_id',p_child,'rule_code',v_rule,
   'write_result','RULE_CANDIDATE_CREATED','estado','CANDIDATO'));
 SELECT to_jsonb(r) INTO after_row FROM lf_ops.reglas r WHERE codigo=v_rule;
 v_after:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF after_row->>'estado'<>'CANDIDATO' OR after_row->>'pendiente_decision'<>'true'
    OR v_after IS NULL OR v_after=v_source
 THEN RAISE EXCEPTION 'LF_IG_CREATE_CANONICAL_READBACK_FAILED'; END IF;
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','readback',v_ref||'/60',
   jsonb_build_object('rule_code',v_rule,'readback_row',after_row,'estado','CANDIDATO',
     'source_snapshot_sha256',v_source,'result_snapshot_sha256',v_after));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'CREACION_REGLA_LF','trace_close',v_ref||'/70',
   jsonb_build_object('execution_id',p_child,'operation_code','CREACION_REGLA_LF',
      'trace_ref',v_ref,'no_promotion',true));
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
 WHERE execution_id=p_child AND status='PASS_CLEAN')<>7
 THEN RAISE EXCEPTION 'LF_IG_CREATE_7_7_NOT_CLEAN'; END IF;
 INSERT INTO public.lf_ig_rule_change_v2(parent_execution_id,child_execution_id,
   rule_code,kind,owner_decision_id,source_snapshot_sha256,candidate_snapshot_sha256,
   approved_patch,state)
 VALUES(p_parent,p_child,v_rule,'CREATE',(v->>'decision_id')::uuid,v_source,v_after,
   v->'patch','CANDIDATE_VERIFIED');
 UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=now(),
  manifest=manifest||jsonb_build_object('operation_closed',true,
  'candidate_write_verified',true,'result_snapshot_sha256',v_after,
  'rule_state','CANDIDATO','promotion_authorized',false),
  updated_by_execution_id=p_child,updated_at=now()
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_CREATE_CHILD_CLOSE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','child_execution_id',p_child,
  'rule_code',v_rule,'result_snapshot_sha256',v_after,'promotion_authorized',false);
END
$fn$;

CREATE FUNCTION public.lf_skill_o_rule_update_v2(
 p_child text,p_input jsonb,p_parent text,p_run text,p_request_sha text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $fn$
DECLARE v jsonb;c jsonb;r jsonb;ret jsonb;v_rule text;v_source text;v_ref text;
DECLARE_KIND text;
BEGIN
 v:=public.lf_ig_rule_child_guard_v2(p_child,p_input,p_parent,p_run,p_request_sha,'RULE_UPDATE_APPLY');
 DECLARE_KIND:=v->>'kind';v_rule:=v->>'rule_code';v_source:=v->>'source_sha256';
 IF DECLARE_KIND='UPDATE_CANDIDATE' THEN
   ret:=public.lf_skill_o_rule_update_v1(p_child,p_input,p_parent,p_run,p_request_sha);
   IF ret->>'status'<>'APPLIED_VERIFIED' THEN
     RAISE EXCEPTION 'LF_IG_UPDATE_LEGACY_WRITER_NOT_VERIFIED'; END IF;
   INSERT INTO public.lf_ig_rule_change_v2(parent_execution_id,child_execution_id,
     rule_code,kind,owner_decision_id,source_snapshot_sha256,
     candidate_snapshot_sha256,approved_patch,state)
   VALUES(p_parent,p_child,v_rule,'UPDATE_CANDIDATE',(v->>'decision_id')::uuid,v_source,
     ret->>'result_snapshot_sha256',v->'patch','CANDIDATE_VERIFIED');
   RETURN ret;
 END IF;
 IF DECLARE_KIND<>'CORRECT_VIGENTE'
 THEN RAISE EXCEPTION 'LF_IG_UPDATE_STATE_NOT_ALLOWED'; END IF;
 c:=v->'patch'->'changes';
 IF (SELECT count(*) FROM jsonb_object_keys(c)) NOT BETWEEN 1 AND 7
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN
      ('categoria','titulo','descripcion','razon','valor_config','es_transversal','origen'))
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_CHANGE_SCOPE_INVALID'; END IF;
 IF v->'patch'->>'change_kind'='DOCUMENTARY_ONLY'
    AND EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('titulo','descripcion','razon'))
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_DOCUMENTARY_SCOPE_VIOLATION'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(c) j WHERE j.value='null'::jsonb)
    OR (c ? 'es_transversal' AND jsonb_typeof(c->'es_transversal')<>'boolean')
    OR (c ? 'valor_config' AND jsonb_typeof(c->'valor_config')<>'object')
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FIELD_TYPE_INVALID'; END IF;
 IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_rule AND estado='VIGENTE')
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_SOURCE_STATE_STALE'; END IF;
 r:=public.fn_lf_operation_reserve_execution_v1(
  p_child,'ACTUALIZACION_REGLA_LF','REGLA',v_rule,
  'skill-child-v1:'||p_run,p_request_sha,p_parent,NULL,NULL,
  jsonb_build_object('profile_handoff',jsonb_build_object(
   'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
   'analysis_snapshot_sha256',v_source,'approved_owner_decision_id',v->>'decision_id',
   'owner_decision_record_sha256',v->>'decision_record_sha256',
   'production_allowed',false,'promotion_authorized',false,
   'candidate_patch_scope','VIGENTE_REVISION_STAGED'));
 IF r->>'result'<>'RESERVED_NEW_EXECUTION' THEN
   RAISE EXCEPTION 'LF_IG_VIGENTE_RESERVATION_NOT_NEW'; END IF;
 v_ref:='SKILLRUN:'||p_run;
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','ekb_preflight',v_ref||'/10',
   jsonb_build_object('ekb_refs',jsonb_build_array('INPUT_GOVERNANCE_LF_V1_4'),'execution_binding',p_child));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','classify',v_ref||'/20',
   jsonb_build_object('rule_code',v_rule,'category','VIGENTE_REVISION','candidate_classification','REGLA_UPDATE'));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','existing_check',v_ref||'/30',
   jsonb_build_object('rule_code',v_rule,'existing_count',1,'expected_existence','ONE_VIGENTE'));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','destination_validate',v_ref||'/40',
   jsonb_build_object('destination_schema','public','destination_table','lf_ig_rule_change_v2','unique_code_guard',true));
 INSERT INTO public.lf_ig_rule_change_v2(parent_execution_id,child_execution_id,
   rule_code,kind,owner_decision_id,source_snapshot_sha256,approved_patch,state)
 VALUES(p_parent,p_child,v_rule,'CORRECT_VIGENTE',(v->>'decision_id')::uuid,
   v_source,v->'patch','STAGED');
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','candidate_write',v_ref||'/50',
   jsonb_build_object('execution_id',p_child,'rule_code',v_rule,
   'write_result','VIGENTE_REVISION_STAGED','estado','STAGED'));
 IF public.lf_asset_snapshot_sha_v1('REGLA',v_rule) IS DISTINCT FROM v_source
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_STAGE_MUTATED_CANONICAL'; END IF;
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','readback',v_ref||'/60',
   jsonb_build_object('rule_code',v_rule,'readback_row',v->'patch',
     'estado','STAGED','source_snapshot_sha256',v_source));
 PERFORM public.lf_ig_rule_step_record_v2(p_child,'ACTUALIZACION_REGLA_LF','trace_close',v_ref||'/70',
   jsonb_build_object('execution_id',p_child,'operation_code','ACTUALIZACION_REGLA_LF',
      'trace_ref',v_ref,'no_promotion',true));
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
    WHERE execution_id=p_child AND status='PASS_CLEAN')<>7
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_STAGE_7_7_NOT_CLEAN'; END IF;
 UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=now(),
  manifest=manifest||jsonb_build_object('operation_closed',true,
    'revision_staged_verified',true,'result_snapshot_sha256',v_source,
    'rule_state','VIGENTE','promotion_authorized',false),
  updated_by_execution_id=p_child,updated_at=now()
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_VIGENTE_STAGE_CHILD_CLOSE_FAILED'; END IF;
 RETURN jsonb_build_object('status','STAGED_VERIFIED','child_execution_id',p_child,
  'rule_code',v_rule,'source_snapshot_sha256',v_source,'promotion_authorized',false);
END
$fn$;

-- Post-owner-approval finalizer; always initiated by the existing governed
-- Edge/OIDC service role after a NEW child has 7 clean steps. It may not close
-- the parent profile: official step-80 native bridge owns that final close.
CREATE FUNCTION public.lf_ig_rule_finalize_v2(p_child text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $fn$
DECLARE ch public.lf_ig_rule_change_v2%ROWTYPE;
 d public.lf_ig_owner_decision_v2%ROWTYPE;
 par public.lf_operation_execution%ROWTYPE; ce public.lf_operation_execution%ROWTYPE;
 r lf_ops.reglas%ROWTYPE; p record; approval jsonb;apply_result jsonb;
 c jsonb;before_sha text;after_sha text;v_promotion text;
BEGIN
 SELECT * INTO ch FROM public.lf_ig_rule_change_v2
 WHERE child_execution_id=p_child FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_FINALIZE_CHILD_NOT_FOUND'; END IF;
 SELECT * INTO d FROM public.lf_ig_owner_decision_v2
 WHERE decision_id=ch.owner_decision_id AND verdict='APROBAR';
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF' AND owner_sub=d.owner_sub
   AND owner_name=d.decisor AND status='TEMP_DOCUMENTARY_ACTIVE')
 THEN RAISE EXCEPTION 'LF_IG_FINALIZE_OWNER_RECEIPT_STALE'; END IF;
 SELECT * INTO ce FROM public.lf_operation_execution
 WHERE execution_id=p_child AND created_by_execution_id=ch.parent_execution_id
 AND target_code=ch.rule_code AND status='COMPLETED'
 AND operation_code IN ('CREACION_REGLA_LF','ACTUALIZACION_REGLA_LF');
 IF NOT FOUND OR (SELECT count(*) FROM public.lf_operation_execution_steps
  WHERE execution_id=p_child AND status='PASS_CLEAN')<>7
 THEN RAISE EXCEPTION 'LF_IG_FINALIZE_CHILD_7_STEPS_REQUIRED'; END IF;
 SELECT * INTO par FROM public.lf_operation_execution
 WHERE execution_id=ch.parent_execution_id AND operation_code='EJECUCION_PERFIL_LF'
 AND status='IN_PROGRESS' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_FINALIZE_PARENT_NOT_ACTIVE'; END IF;
 IF ch.state='VIGENTE_VERIFIED' THEN
  IF public.lf_asset_snapshot_sha_v1('REGLA',ch.rule_code)
     IS DISTINCT FROM ch.finalized_snapshot_sha256
  THEN RAISE EXCEPTION 'LF_IG_FINALIZE_REPLAY_SOURCE_DRIFT'; END IF;
  RETURN jsonb_build_object('status','VIGENTE_VERIFIED','replay',true,
    'rule_code',ch.rule_code,'result_snapshot_sha256',ch.finalized_snapshot_sha256);
 END IF;
 SELECT * INTO r FROM lf_ops.reglas WHERE codigo=ch.rule_code FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_FINALIZE_RULE_MISSING'; END IF;
 before_sha:=public.lf_asset_snapshot_sha_v1('REGLA',ch.rule_code);
 c:=ch.approved_patch->'changes';
 IF ch.kind='CORRECT_VIGENTE' THEN
   IF r.estado<>'VIGENTE' OR before_sha IS DISTINCT FROM ch.source_snapshot_sha256
   THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FINALIZE_SOURCE_STALE'; END IF;
   -- A functional change can weaken security/business controls. A declared
   -- human decision plus profile semantic PASS is insufficient for post-write
   -- impact; no signed independent impact receipt is installed in this version.
   IF ch.approved_patch->>'change_kind' IS DISTINCT FROM 'DOCUMENTARY_ONLY'
   THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING'; END IF;
   UPDATE lf_ops.reglas SET
      categoria=coalesce(c->>'categoria',categoria),
      titulo=coalesce(c->>'titulo',titulo),
      descripcion=coalesce(c->>'descripcion',descripcion),
      razon=coalesce(c->>'razon',razon),
      valor_config=coalesce(c->'valor_config',valor_config),
      es_transversal=coalesce((c->>'es_transversal')::boolean,es_transversal),
      origen=coalesce(c->>'origen',origen),
      pendiente_decision=false,pendiente_detalle=NULL,updated_at=now()
   WHERE codigo=ch.rule_code AND estado='VIGENTE';
   -- This is a guarded in-place correction, NOT a CANDIDATO promotion.
   -- Never forge an APPLIED promotion receipt for a rule already VIGENTE.
 ELSE
   IF r.estado<>'CANDIDATO' OR before_sha IS DISTINCT FROM ch.candidate_snapshot_sha256
   THEN RAISE EXCEPTION 'LF_IG_FINALIZE_CANDIDATE_SNAPSHOT_STALE'; END IF;
   SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE rule_code=ch.rule_code
   AND request_execution_id=ch.parent_execution_id
   AND request_snapshot_sha256=before_sha AND status='PENDING' FOR UPDATE;
   IF NOT FOUND THEN
     approval:=public.lf_rule_promotion_request_v1(
      ch.parent_execution_id,ch.rule_code,'OWNER_APPROVED_EXACT_RULE_CANDIDATE_V2');
     IF approval->>'status'<>'PENDING_HUMAN_APPROVAL'
     THEN RAISE EXCEPTION 'LF_IG_PROMOTION_REQUEST_NOT_ACCEPTED'; END IF;
     v_promotion:=approval->>'promotion_id';
   ELSE
     v_promotion:=p.promotion_id;
   END IF;
   UPDATE public.lf_rule_promotion_v1
   SET status='APPROVED',decided_by=d.decisor,
       decided_at=d.decision_date
   WHERE promotion_id=v_promotion AND status='PENDING'
   AND request_snapshot_sha256=before_sha;
   IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_PROMOTION_APPROVAL_NOT_RECORDED'; END IF;
   apply_result:=public.lf_rule_promotion_apply_v1(v_promotion);
   IF apply_result->>'status'<>'APPLIED'
   THEN RAISE EXCEPTION 'LF_IG_PROMOTION_OFFICIAL_APPLY_FAILED'; END IF;
   UPDATE lf_ops.reglas SET pendiente_decision=false,pendiente_detalle=NULL,
        updated_at=now()
   WHERE codigo=ch.rule_code AND estado='VIGENTE';
 END IF;
 after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',ch.rule_code);
 IF after_sha IS NULL OR after_sha=before_sha OR NOT EXISTS(
   SELECT 1 FROM lf_ops.reglas
   WHERE codigo=ch.rule_code AND estado='VIGENTE' AND NOT pendiente_decision)
 THEN RAISE EXCEPTION 'LF_IG_FINALIZE_VIGENTE_READBACK_FAILED'; END IF;
 UPDATE public.lf_ig_rule_change_v2 SET state='VIGENTE_VERIFIED',
   finalized_snapshot_sha256=after_sha,finalized_at=now()
 WHERE change_id=ch.change_id AND state IN ('STAGED','CANDIDATE_VERIFIED');
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_FINALIZE_RECEIPT_CLOSE_FAILED'; END IF;
 RETURN jsonb_build_object('status','VIGENTE_VERIFIED','rule_code',ch.rule_code,
   'source_snapshot_sha256',before_sha,'result_snapshot_sha256',after_sha,
   'owner_decision_id',d.decision_id,
   'owner_decision_record_sha256',d.decision_record_sha256,
   'decision_record',d.decision_record,'identity_verified',false,
   'parent_execution_id',ch.parent_execution_id,
   'next_action','OFFICIAL_PROFILE_STEP80_REPORT_READBACK_AND_CLOSE',
   'parent_closed',false,'production_authorized',false);
END
$fn$;

-- lf_activos: per-row documentary owner decision (not Auth) with
-- exact preimage + ACTUALIZACION_DB_LF Merge Train step-10 PASS_CLEAN.
CREATE TABLE public.lf_ig_asset_owner_receipt_v2(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_code text NOT NULL,
  owner_sub uuid NOT NULL,
  decisor text NOT NULL CHECK(decisor='Cristhian Luján'),
  proponente text NOT NULL CHECK(proponente<>'Cristhian Luján'),
  decision_record jsonb NOT NULL,
  decision_record_sha256 text NOT NULL CHECK(
    decision_record_sha256 ~ '^[0-9a-f]{64}$'),
  proposed_owner text NOT NULL,
  train_execution_id text NOT NULL,
  preimage_sha256 text NOT NULL,
  before_row jsonb NOT NULL,
  after_sha256 text,
  state text NOT NULL DEFAULT 'APPROVED' CHECK(state IN ('APPROVED','APPLIED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(train_execution_id,asset_code)
);
ALTER TABLE public.lf_ig_asset_owner_receipt_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_ig_asset_owner_receipt_v2 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.lf_ig_asset_owner_approve_v2(
 p_train_execution text,p_asset_code text,p_preimage_sha256 text,
 p_new_owner text,p_decision jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE a public.lf_activos%ROWTYPE; v_sha text; v_id uuid; v_sub uuid;
 v_train public.lf_operation_execution%ROWTYPE;
 v_proposer text; v_date timestamptz; v_dec_sha text;
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
 v_proposer:=nullif(btrim(v_train.manifest->>'proposer_actor'),'');
 IF v_proposer IS NULL OR v_proposer='Cristhian Luján'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_SELF_APPROVAL_FORBIDDEN'; END IF;
 IF v_date < v_train.started_at-interval '5 minutes'
    OR v_date > now()+interval '5 minutes'
 THEN RAISE EXCEPTION 'LF_IG_ASSET_DECISION_DATE_OUT_OF_SCOPE'; END IF;
 SELECT * INTO a FROM public.lf_activos
 WHERE codigo_activo=p_asset_code AND archived_at IS NULL FOR SHARE;
 IF NOT FOUND OR p_new_owner !~ '^LF_[A-Z0-9_]{4,50}$'
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

CREATE FUNCTION public.lf_ig_asset_owner_apply_v2(p_receipt uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE t public.lf_ig_asset_owner_receipt_v2%ROWTYPE;a public.lf_activos%ROWTYPE;v_sha text;v_after text;
BEGIN
 SELECT * INTO t FROM public.lf_ig_asset_owner_receipt_v2 WHERE receipt_id=p_receipt FOR UPDATE;
 IF NOT FOUND OR t.state<>'APPROVED'
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
 SELECT * INTO a FROM public.lf_activos WHERE codigo_activo=t.asset_code
 AND archived_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_TARGET_MISSING'; END IF;
 v_sha:=encode(extensions.digest(convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex');
 IF v_sha IS DISTINCT FROM t.preimage_sha256 OR to_jsonb(a) IS DISTINCT FROM t.before_row
 THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_PREIMAGE_MISMATCH'; END IF;
 UPDATE public.lf_activos SET owner_name=t.proposed_owner,
    updated_by_execution_id=t.train_execution_id,updated_at=now()
 WHERE id=a.id AND codigo_activo=t.asset_code AND archived_at IS NULL;
 SELECT * INTO a FROM public.lf_activos WHERE id=a.id;
 v_after:=encode(extensions.digest(convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex');
 IF a.owner_name IS DISTINCT FROM t.proposed_owner OR v_after=v_sha
 THEN RAISE EXCEPTION 'LF_IG_ASSET_OWNER_READBACK_FAILED'; END IF;
 UPDATE public.lf_ig_asset_owner_receipt_v2 SET state='APPLIED',after_sha256=v_after
 WHERE receipt_id=p_receipt AND state='APPROVED';
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','asset_code',t.asset_code,
 'old_sha256',v_sha,'new_sha256',v_after,
 'decision_record',t.decision_record,'decision_record_sha256',t.decision_record_sha256,
 'identity_verified',false,'train_execution_id',t.train_execution_id);
END
$fn$;

-- Register promotion without enabling Router direct side effects.
INSERT INTO public.lf_operation_registry(operation_code,version,status,source_model,
 source_repo,source_paths,notes,operation_family,operation_domain,operation_type,
 applies_to_asset_type,created_by_execution_id,lifecycle_state_code)
VALUES('PROMOCION_REGLA_LF','v0.2','SANDBOX_ACTIVE','GIT_FIRST_YAML',
 'cristhianlujan/claude-persona-lf-patch',
 '["public.lf_ig_rule_finalize_v2","public.lf_rule_promotion_apply_v1","lf_ops.reglas"]'::jsonb,
 'Only via authenticated LF owner receipt and official child 7/7. No direct Router write.',
 'RULE_OPERATIONS','RULE_GOVERNANCE','PROMOTE_CANDIDATE','REGLA',
 'EXEC-MIGRATION-LF-IG-LIFECYCLE-V2','OP_CANDIDATE');

-- Canonical invoker calls these two openers. Old update function remains intact
-- for vetted candidate-only cases, but callers may no longer bypass the V2 gate.
UPDATE public.lf_skill_catalog_v1
 SET opener_fn='lf_skill_o_rule_create_v2',
 input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id',
   'candidate_patch','owner_decision_id'],
 description='Creates official CANDIDATO child after LF temporary documentary decision and 7-step readback'
 WHERE skill_code='RULE_CREATE_APPLY' AND opener_fn IS NULL;
-- Row cardinality is checked in the final readback DO.
UPDATE public.lf_skill_catalog_v1
 SET opener_fn='lf_skill_o_rule_update_v2',
 input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id',
   'candidate_patch','owner_decision_id'],
 description='Candidate-only legacy writer plus staged VIGENTE correction; exact documentary owner decision and preimage required'
 WHERE skill_code='RULE_UPDATE_APPLY' AND opener_fn='lf_skill_o_rule_update_v1';

-- The public PostgREST caller cannot assert a fake HUMAN:... label.
REVOKE ALL ON FUNCTION public.lf_rule_promotion_decide_v1(text,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.lf_ig_rule_child_guard_v2(text,jsonb,text,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.lf_ig_rule_step_record_v2(text,text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.lf_ig_asset_owner_approve_v2(text,text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_asset_owner_approve_v2(text,text,text,text,jsonb)
  TO service_role;
REVOKE ALL ON FUNCTION public.lf_skill_o_rule_create_v2(text,jsonb,text,text,text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.lf_skill_o_rule_update_v2(text,jsonb,text,text,text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.lf_ig_rule_finalize_v2(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.lf_ig_asset_owner_apply_v2(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_rule_create_v2(text,jsonb,text,text,text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_rule_update_v2(text,jsonb,text,text,text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_rule_finalize_v2(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_asset_owner_apply_v2(uuid) TO service_role;

DO $readback$
BEGIN
 IF (SELECT opener_fn FROM public.lf_skill_catalog_v1
      WHERE skill_code='RULE_CREATE_APPLY')<>'lf_skill_o_rule_create_v2'
 OR (SELECT opener_fn FROM public.lf_skill_catalog_v1
      WHERE skill_code='RULE_UPDATE_APPLY')<>'lf_skill_o_rule_update_v2'
 OR (SELECT count(*) FROM public.lf_ig_project_owner_v2
       WHERE project_code='LF' AND owner_name='Cristhian Luján'
       AND status='TEMP_DOCUMENTARY_ACTIVE')<>1
 OR (SELECT count(*) FROM public.lf_ig_project_owner_v2
       WHERE project_code='SALY')<>0
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_registry
       WHERE operation_code='PROMOCION_REGLA_LF' AND status='SANDBOX_ACTIVE')
 THEN RAISE EXCEPTION 'LF_IG_V2_MIGRATION_READBACK_FAILED'; END IF;
END $readback$;

COMMIT;
