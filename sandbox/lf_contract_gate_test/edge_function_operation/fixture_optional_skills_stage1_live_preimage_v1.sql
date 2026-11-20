-- Disposable ONLY: exact live pg_get_functiondef snapshots and minimal contract fixture.
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;
DO $r$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $r$;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,
 target_repo text,target_path text,status text,manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),
 updated_by_execution_id text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,evidence_payload jsonb,
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_operation_steps(
 operation_code text,step_order int,step_id text,active boolean,required boolean);
CREATE TABLE public.lf_operation_step_contracts(
 operation_code text,step_id text,status text,resolver_ref text,next_if_pass text,
 next_if_blocked text,required_evidence_keys jsonb);
CREATE TABLE public.lf_profile_selection_registry_v1(
 profile_code text PRIMARY KEY,descriptor_status text);
CREATE TABLE public.lf_profile_selector_policy_v1(
 profile_code text PRIMARY KEY,channels text[]);
CREATE TABLE public.lf_skill_selector_policy_v1(
 profile_code text,skill_code text,channels text[],required_operation text,
 allowed_effects text[],selection_mode text,enabled boolean,
 owner_decision_required boolean,applicability_contract jsonb,
 policy_evidence_ref text,updated_at timestamptz,
 PRIMARY KEY(profile_code,skill_code));
CREATE TABLE public.lf_skill_catalog_v1(
 skill_code text PRIMARY KEY,handler_fn text,required_operation text,effect text,
 input_required text[],status text,runtime_slug text);
CREATE TABLE public.lf_skill_selection_registry_v1(
 skill_code text PRIMARY KEY,descriptor jsonb,source_ref text,
 source_revision text,descriptor_status text);
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text);
CREATE TABLE public.lf_router_business_catalog_v1(business_code text);
INSERT INTO public.lf_router_business_catalog_v1 VALUES('LF');
CREATE TABLE public.lf_activos(
 codigo_activo text,tipo_activo text,archived_at timestamptz,metadata jsonb);
CREATE TABLE private.lf_profile_skill_runtime_ticket_v1(
 ticket_id uuid,execution_id text,skill_code text,runtime_slug text,
 request_body jsonb,request_sha256 text,issued_at timestamptz,
 expires_at timestamptz,consumed_at timestamptz,consumed_by text);
INSERT INTO public.lf_operation_steps(operation_code,step_order,step_id,active,required)
SELECT 'EJECUCION_PERFIL_LF',x,'step_'||x,true,true
FROM unnest(ARRAY[0,10,20,30,40,45,47,50,60,70,80]) AS x;
INSERT INTO public.lf_operation_step_contracts(operation_code,step_id,status,resolver_ref,next_if_pass,next_if_blocked,required_evidence_keys)
SELECT operation_code,step_id,'ACTIVE_ENFORCEMENT','public.stub',null,null,'[]'::jsonb
FROM public.lf_operation_steps;
INSERT INTO public.lf_skill_catalog_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK','lf_skill_h_input_governance_context_pack_v1',
   'EJECUCION_PERFIL_LF','READ_ONLY',
   ARRAY['request_text','profile_code','scope','consumer'],'READY','input-governance-agent-v1'),
 ('SCREEN_RULES_SNAPSHOT','lf_skill_h_screen_rules_snapshot_v1',
   'EJECUCION_PERFIL_LF','READ_ONLY',ARRAY['pantalla_codigo'],'READY',null);
INSERT INTO public.lf_skill_selection_registry_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK','{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1","PURPOSE":"context readiness","BOUNDARY":"read only"}',
  'supabase://skill/ig','sha256:25dd30f67ed5759209b11a7e7d993d7766bd3c5cedf5f79a61976e25362980dc','CURRENT'),
 ('SCREEN_RULES_SNAPSHOT','{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1","PURPOSE":"screen rules","BOUNDARY":"read only"}',
  'supabase://skill/screen','sha256:e1d9545da14de1f43ebab0a803624c79fdac46f2f33b42ff4ce95a9ca849ddb4','CURRENT');
INSERT INTO public.lf_profile_selection_registry_v1(profile_code,descriptor_status)
SELECT p,'CURRENT' FROM unnest(ARRAY[
 'ACT-0051','PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING',
 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
 'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
 'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT','PERFIL-PRODUCT-DIRECTOR-LF',
 'PERFIL-QUALITY-PACK','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
 'PERFIL-UI-ARCHITECT','PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531']) AS p;
INSERT INTO public.lf_profile_selector_policy_v1(profile_code,channels)
SELECT profile_code,
 CASE
 WHEN profile_code IN ('ACT-0051','PERFIL-UI-ARCHITECT') THEN ARRAY['PRODUCTO','PROGRAMACION']::text[]
 WHEN profile_code IN ('PERFIL-QUALITY-PACK','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF')
    THEN ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']::text[]
 WHEN profile_code='PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF' THEN ARRAY['OPERACIONES']::text[]
 ELSE ARRAY['PRODUCTO']::text[] END
FROM public.lf_profile_selection_registry_v1;
INSERT INTO public.lf_skill_selector_policy_v1
 (profile_code,skill_code,channels,required_operation,allowed_effects,selection_mode,enabled,
 owner_decision_required,applicability_contract,policy_evidence_ref,updated_at)
SELECT p.profile_code,'INPUT_GOVERNANCE_CONTEXT_PACK',p.channels,
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY']::text[],'SEMANTIC_OPTIONAL',true,false,
 '{"only_if_applicable":false,"selection_required":true}'::jsonb,'owner://fixture',now()
 FROM public.lf_profile_selector_policy_v1 p;
INSERT INTO public.lf_skill_selector_policy_v1
 (profile_code,skill_code,channels,required_operation,allowed_effects,selection_mode,enabled,
 owner_decision_required,applicability_contract,policy_evidence_ref,updated_at)
SELECT p.profile_code,'SCREEN_RULES_SNAPSHOT',p.channels,
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY']::text[],'SEMANTIC_OPTIONAL',true,false,
 '{"only_if_applicable":false}'::jsonb,'owner://fixture',now()
 FROM public.lf_profile_selector_policy_v1 p
 WHERE p.profile_code IN ('PERFIL-PRODUCT-DIRECTOR-LF',
 'PERFIL-UI-ARCHITECT','PERFIL-QUALITY-PACK',
 'PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING',
 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
 'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT',
 'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531',
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,created_at,manifest)
SELECT v,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',
 '2026-11-14 18:00:00+00'::timestamptz,
 jsonb_build_object('router_profile_handoff',jsonb_build_object(
  'literal_request','Entra por el router y revisa las reglas de carga masiva del b2b',
  'channel','PRODUCTO','intent','review rules'))
FROM unnest(ARRAY['EXEC-PROFILE-GATE2-0248912F0BB40220F116168D',
 'EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
 'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1']) v;
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
SELECT v,'input_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('resolved_scope',jsonb_build_object(
  'resolution_status','RESOLVED','resolved_screen_code','B2B-CARGA-002'))
FROM unnest(ARRAY['EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
 'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1']) v;

-- Exact current public function preimages for PG version-specific migration guards.
-- lf_profile_execution_plan_v1 md5 14e045fe02c9c635c166f8cced7ee4d8
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_v1(p_profile_code text, p_channel text DEFAULT NULL::text, p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_steps jsonb; v_count int; v_invalid int; v_selected jsonb; v_out jsonb;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE c.step_id IS NULL),
     coalesce(jsonb_agg(jsonb_build_object('step_order',s.step_order,'step_id',s.step_id,
       'resolver_ref',c.resolver_ref,'next_if_pass',c.next_if_pass,
       'next_if_blocked',c.next_if_blocked,'required_evidence_keys',c.required_evidence_keys)
       ORDER BY s.step_order),'[]'::jsonb)
 INTO v_count,v_invalid,v_steps
 FROM public.lf_operation_steps s
 LEFT JOIN public.lf_operation_step_contracts c
 ON c.operation_code=s.operation_code AND c.step_id=s.step_id AND c.status='ACTIVE_ENFORCEMENT'
 WHERE s.operation_code='EJECUCION_PERFIL_LF' AND s.active AND s.required;
 IF v_count<>11 OR v_invalid>0 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_OPERATION_STEP_CONTRACTS_INCOMPLETE');
 END IF;
 v_selected:=public.lf_profile_skill_selection_prepare_v1(p_profile_code,p_channel,p_semantic_decision);
 v_out:=jsonb_build_object('operation_code','EJECUCION_PERFIL_LF','profile_code',p_profile_code,
      'channel',p_channel,'status',v_selected->>'status',
      'steps',v_steps,'skills',coalesce(v_selected->'skills','[]'::jsonb),
      'selection_receipt',v_selected,'runtime_mode','GPT_NATIVE',
      'model_external_api',false,'step_source','lf_operation_steps+lf_operation_step_contracts');
 IF v_selected->>'status'='BLOCKED' THEN
    RETURN v_out||jsonb_build_object('blocking_code',v_selected->>'blocking_code');
 END IF;
 RETURN v_out;
END;
$function$
;

-- lf_profile_native_bridge_prepare_v1 md5 bc85d57f8509728527efa62b2b6bd124
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(p_execution_id text, p_source_revision text, p_source_digest text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_valid jsonb;
  v_actor text;
  v_slug text;
  v_source_ref text;
  v_existing text;
  v_step jsonb;
  v_input jsonb;
  v_base_context jsonb;
  v_context jsonb;
  v_baseline jsonb;
  v_clean integer;
  v_policy_selection jsonb;
  v_ig_ticket jsonb;
  v_skill_plan jsonb;
  v_skill_item jsonb;
  v_skill_result jsonb;
  v_skill_findings jsonb:='[]'::jsonb;
  v_skill_receipts jsonb:='[]'::jsonb;
  v_skill_input jsonb;
  v_skill_code text;
  v_skill_ig jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_source_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_SOURCE_BINDING_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false) THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  SELECT metadata->>'profile_slug' INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=e.target_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF nullif(v_slug,'') IS NULL
     OR nullif(e.target_repo,'') IS NULL
     OR nullif(e.target_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_UNRESOLVED'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_source_ref:='github://'||e.target_repo||'@'||p_source_revision||'/'||e.target_path;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_resolve';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_resolve',
      'supabase://public.lf_activos/'||e.target_code,
      jsonb_build_object(
        'exact_profile_resolved',true,
        'codigo_activo',e.target_code,
        'profile_slug',v_slug
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_RESOLVE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_source_read';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_source_read',
      v_source_ref,
      jsonb_build_object(
        'profile_source_ref',v_source_ref,
        'source_revision',p_source_revision,
        'profile_source_digest',p_source_digest,
        'profile_source_path',e.target_path
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL THEN
    v_input:=public.lf_profile_execution_input_validate_v1(
      p_execution_id,
      v_handoff->>'literal_request',
      v_source_ref,
      v_handoff
    );

    IF v_input->>'status'<>'READY' THEN
      IF v_input->>'status'='SCREEN_SELECTION_REQUIRED'
         AND v_input->>'next_action'='RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
         AND jsonb_typeof(v_input->'screen_selection_request')='object'
      THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_input->'screen_selection_request',
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'next_action','SUBMIT_SCREEN_SELECTION_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;


      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;


    -- Step40 executes all policy-selected READ_ONLY skills; never Router-owned.
    v_skill_plan:=public.lf_profile_execution_plan_v1(e.target_code,v_handoff->>'channel',null::jsonb);
    -- Selected skills are optional to profile continuation. A missing/invalid
    -- skill plan produces an auditable READ_ONLY finding, never implicit skill
    -- execution or permission to write. Router/scope validation is unchanged.
    IF v_skill_plan->>'status'='SEMANTIC_SELECTION_REQUIRED'
       AND jsonb_typeof(v_skill_plan#>'{selection_receipt,required_skills}')='array' THEN
      -- Optional semantic choice is NOT automatically selected. Execute
      -- deterministic mandatory skills from verified DB policy while leaving
      -- optional selection as an auditable finding. No skill scope expansion.
      v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
        'skill_code','OPTIONAL_SKILL_SELECTION',
        'status','SKILL_FAILED_AS_FINDING',
        'blocking_code','SKILL_OPTIONAL_SEMANTIC_DECISION_DEFERRED',
        'remediation_action','NATIVE_SEMANTIC_REVIEW_IN_GOVERNED_FOLLOWUP',
        'continuation_allowed',true,'production_authorized',false,
        'policy_receipt',v_skill_plan->'selection_receipt'));
      v_skill_plan:=v_skill_plan||jsonb_build_object(
        'status','READY',
        'skills',v_skill_plan#>'{selection_receipt,required_skills}',
        'selection_mode','REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED');
    ELSIF v_skill_plan->>'status'<>'READY' THEN
      v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
        'skill_code','SKILL_POLICY_SELECTION',
        'status','SKILL_FAILED_AS_FINDING',
        'blocking_code',coalesce(v_skill_plan->>'blocking_code','SKILL_POLICY_NOT_READY'),
        'remediation_action','REPAIR_PROFILE_SKILL_POLICY_AND_RERUN_SKILL',
        'continuation_allowed',true,'production_authorized',false,
        'policy_receipt',v_skill_plan));
      v_skill_plan:=jsonb_build_object('status','READY','skills','[]'::jsonb);
    END IF;
    FOR v_skill_item IN SELECT x FROM jsonb_array_elements(v_skill_plan->'skills') x LOOP
      v_skill_code:=v_skill_item->>'skill_code';
      IF v_skill_item->>'effect'<>'READ_ONLY' THEN
        v_skill_receipts:=v_skill_receipts||jsonb_build_array(
          jsonb_build_object('skill_code',v_skill_code,'status','DEFERRED_NOT_STEP40',
             'effect_authorized',false));
        CONTINUE;
      END IF;
      v_skill_input:=jsonb_build_object(
        'execution_id',p_execution_id,
        'request_text',v_handoff->>'literal_request',
        'profile_code',e.target_code,
        'scope',v_input->'resolved_scope',
        'consumer','CONTEXT_PACK',
        'pantalla_codigo',v_input#>>'{resolved_scope,resolved_screen_code}'
      );
      v_skill_result:=public.lf_profile_skill_invoke_selected_v1(
        p_execution_id,v_handoff->>'channel',v_skill_code,v_skill_input,null
      );
      IF v_skill_result->>'status'='RUNTIME_REQUIRED' THEN
        v_ig_ticket:=public.lf_profile_skill_runtime_ticket_issue_v1(
          p_execution_id,v_skill_code,v_skill_input);
        IF v_ig_ticket->>'status'='AUTHORIZED' THEN
          RETURN jsonb_build_object(
            'status','SKILL_RUNTIME_REQUIRED','skill_code',v_skill_code,
            'execution_id',p_execution_id,'input_validate',v_input,
            'input_governance_runtime_request',jsonb_build_object(
              'transport','DIRECT_EDGE_INVOCATION',
              'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1',
              'runtime_slug',v_ig_ticket->>'runtime_slug',
              'request_headers',jsonb_build_object(
                'X-LF-Profile-Runtime-Ticket',v_ig_ticket->>'ticket'),
              'request_body',jsonb_build_object(
                'action','profile_skill_runtime_v1','execution_id',p_execution_id,
                'skill_code',v_skill_code),
              'terminal_statuses',jsonb_build_array('READY','BLOCKED','HUMAN_DECISION_REQUIRED','FAILED'),
              'continuation_statuses',jsonb_build_array('VALIDATOR_RESUME_REQUIRED'),
              'ticket_expires_at',v_ig_ticket->'expires_at',
              'queue_required',false,'polling_required',false),
            'next_action','INVOKE_SELECTED_SKILL_RUNTIME_AND_RETRY_SAME_BRIDGE',
            'router_reentry_required',false);
        END IF;
        v_skill_result:=jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
          'blocking_code',coalesce(v_ig_ticket->>'code','SKILL_RUNTIME_TICKET_NOT_AUTHORIZED'),
          'ticket_status',v_ig_ticket->>'status','skill_code',v_skill_code,
          'attempt_count',v_ig_ticket->'attempt_count',
          'remediation_action','INVESTIGATE_SKILL_RUNTIME_AND_RECURATE_SOURCES_GOVERNED',
          'continuation_allowed',true,'production_authorized',false);
      END IF;
      v_skill_receipts:=v_skill_receipts||jsonb_build_array(jsonb_build_object(
        'skill_code',v_skill_code,'result',v_skill_result));
      IF v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' THEN
        v_skill_ig:=coalesce(v_skill_result#>'{output,input_governance}',
          v_skill_result->'input_governance','{}'::jsonb);
        IF v_skill_result->>'status' NOT IN ('READY','COMPLETED','SKIPPED','PASS') THEN
          -- IG is only a policy-selected READ_ONLY skill; its failure is a
          -- finding, not a success claim or a gate for Step45/50/70/80.
          v_skill_ig:=v_skill_ig||jsonb_build_object(
            'status','BLOCKED',
            'blocking_code',coalesce(v_skill_result->>'blocking_code',
                                     v_skill_result->>'status','IG_SKILL_NOT_READY'),
            'continuation_allowed',true,
            'remediation_action',coalesce(v_skill_result->>'remediation_action',
              'RECURATE_IG_FROM_CURRENT_CANONICAL_SOURCES'),
            'production_authorized',false,'promotion_authorized',false);
        END IF;
      END IF;
      IF v_skill_result->>'status' NOT IN ('READY','COMPLETED','SKIPPED','PASS') THEN
        v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
           'skill_code',v_skill_code,'status','SKILL_FAILED_AS_FINDING',
           'blocking_code',coalesce(v_skill_result->>'blocking_code',
                                     v_skill_result->>'status','SKILL_FAILED'),
           'continuation_allowed',true,
           'remediation_action',coalesce(v_skill_result->>'remediation_action',
             'REVIEW_SKILL_SOURCE_POLICY_AND_RETRY_GOVERNED'),
           'evidence_ref',v_skill_result->>'evidence_ref',
           'receipt',v_skill_result));
      END IF;
    END LOOP;
    v_input:=v_input||jsonb_build_object(
      'skill_execution_receipts',v_skill_receipts,
      'skill_findings',v_skill_findings,
      'analysis_scope',case when jsonb_array_length(v_skill_findings)>0
        then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
      'input_governance',coalesce(v_skill_ig,'{}'::jsonb)
          ||jsonb_build_object('analysis_scope',
              case when jsonb_array_length(v_skill_findings)>0
                then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
              'production_authorized',false,'promotion_authorized',false),
      'production_authorized',false,'promotion_authorized',false,
      'mutation_authorized',false,
      'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT')
    );
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'input_validate',
      'supabase://public.lf_profile_execution_input_validate_v1/'||p_execution_id,
      v_input,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context IS NULL THEN
    v_base_context:=public.lf_profile_execution_context_admission_v1(p_execution_id);
    IF v_base_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_base_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_BASE_CONTEXT_NOT_READY'
        ),
        'base_context',v_base_context
      );
    END IF;

    v_context:=public.lf_profile_execution_channel_context_v1(
      p_execution_id,
      v_base_context,
      v_handoff
    );
    IF v_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_NOT_READY'
        ),
        'channel_context',v_context
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'context_admission',
      v_context->>'context_receipt_ref',
      v_context,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_baseline IS NULL THEN
    v_baseline:=public.lf_profile_execution_research_baseline_v1(
      p_execution_id,
      NULL,
      v_actor
    );
    IF coalesce(v_baseline->>'outcome','') NOT IN (
         'STEP_RECORDED',
         'STEP_ALREADY_RECORDED'
       )
       AND NOT EXISTS(
         SELECT 1
         FROM public.lf_operation_execution_steps
         WHERE execution_id=p_execution_id
           AND step_id='research_baseline_freeze'
           AND status='STEP_PASS_WITH_EVIDENCE'
       ) THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY',
        'baseline_result',v_baseline
      );
    END IF;

    SELECT evidence_payload INTO v_baseline
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='research_baseline_freeze'
      AND status='STEP_PASS_WITH_EVIDENCE';
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>7 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',7
    );
  END IF;

  v_policy_selection:=public.lf_profile_policy_selection_prepare_v1(p_execution_id);

  IF v_policy_selection->>'status'<>'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_policy_selection->>'blocking_code','BLOCK_PROFILE_POLICY_SELECTION_PREPARE_FAILED'),
      'policy_selection',v_policy_selection
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_MODEL_INPUT_READY',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',e.target_code,
    'profile_slug',v_slug,
    'profile_source_ref',v_source_ref,
    'profile_source_digest',p_source_digest,
    'literal_request',v_handoff->>'literal_request',
    'input_governance',v_input->'input_governance',
    'ig_open_work',public.lf_profile_ig_open_work_v1(p_execution_id),
    'ig_open_work_count',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id)),
    'ig_open_work_response_contract',jsonb_build_object(
      'required',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))>0,
      'output_field','traceability.ig_open_work_resolution',
      'coverage','EXACT_ONE_RESPONSE_PER_FAMILY',
      'allowed_statuses',jsonb_build_array(
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      ),
      'resolved_requires_evidence',true,
      'dependency_or_decision_requires_next_action',true
    ),
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'policy_resolution_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'policy_selection_request',v_policy_selection,
    'repair_execution_authority',
      e.manifest->'repair_execution_authority',
    'execution_write_mode',
      case
        when coalesce((e.manifest->>'governed_repair_write')::boolean,false)
          then 'GOVERNED_REPAIR_WRITE'
        else 'READ_ONLY'
      end,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action',CASE e.manifest->>'executor_mode' WHEN 'CLAUDE_NATIVE' THEN 'EXECUTE_PROFILE_IN_CURRENT_CLAUDE_NATIVE_CONTEXT' ELSE 'EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT' END,
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$function$
;

-- lf_profile_skill_invoke_selected_v1 md5 ddf9f81751512a956c8027c79f966642
CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(p_execution_id text, p_channel text, p_skill_code text, p_input jsonb, p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE e record; v_plan jsonb; v_skill jsonb; v_out jsonb; v_receipt jsonb;
 v_app_contract jsonb; v_app_evidence jsonb; v_app_path text[];
 v_app_value text;
BEGIN
 SELECT target_code,status,operation_code,manifest INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF' THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PARENT_RUN_NOT_ACTIVE'); END IF;
 IF e.manifest#>>'{router_profile_handoff,channel}' IS DISTINCT FROM p_channel THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CHANNEL_NOT_BOUND_TO_PARENT_RUN'); END IF;
 v_plan:=public.lf_profile_execution_plan_v1(e.target_code,p_channel,p_semantic_decision);
 -- Required deterministic skills are not vetoed by a pending OPTIONAL choice.
 -- The optional candidate is NOT automatically selected.
 IF v_plan->>'status'='SEMANTIC_SELECTION_REQUIRED'
    AND p_semantic_decision IS NULL
    AND jsonb_typeof(v_plan#>'{selection_receipt,required_skills}')='array'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(
       v_plan#>'{selection_receipt,required_skills}') x
       WHERE x->>'skill_code'=p_skill_code
         AND x->>'selection_mode'='DETERMINISTIC_POLICY') THEN
   v_plan:=v_plan||jsonb_build_object(
     'status','READY',
     'skills',v_plan#>'{selection_receipt,required_skills}',
     'selection_mode','SKILL_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED');
 END IF;
 IF v_plan->>'status'<>'READY' THEN
  RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code',coalesce(v_plan->>'blocking_code', 'SKILL_SEMANTIC_DECISION_PENDING')); END IF;
 SELECT x INTO v_skill FROM jsonb_array_elements(v_plan->'skills') x
 WHERE x->>'skill_code'=p_skill_code;
 IF v_skill IS NULL THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_NOT_SELECTED_BY_DB_POLICY'); END IF;
 -- Generic, policy-bound applicability; no skill/IG/profile name is encoded
 -- in the invoker or in the Step40/50 operation contract. A legacy NOT_REQUIRED
 -- receipt MUST NOT trigger a skill invocation.
 SELECT applicability_contract INTO v_app_contract
 FROM public.lf_skill_selector_policy_v1
 WHERE profile_code=e.target_code AND skill_code=p_skill_code
   AND required_operation=v_skill->>'required_operation'
   AND enabled AND p_channel=ANY(channels);
 IF v_app_contract IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_POLICY_NOT_FOUND');
 END IF;
 IF coalesce((v_app_contract->>'only_if_applicable')::boolean,false) THEN
   IF v_app_contract->>'evaluation'<>'EVIDENCE_PAYLOAD' OR
      coalesce(v_app_contract->>'evidence_step_id','')='' OR
      jsonb_typeof(v_app_contract->'evidence_json_path')<>'array' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_POLICY_INVALID');
   END IF;
   SELECT array_agg(path_element ORDER BY ord) INTO v_app_path
   FROM jsonb_array_elements_text(v_app_contract->'evidence_json_path')
       WITH ORDINALITY AS path(path_element,ord);
   IF v_app_path IS NULL OR cardinality(v_app_path)<1 THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_PATH_INVALID');
   END IF;
   SELECT evidence_payload INTO v_app_evidence
   FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id
     AND step_id=v_app_contract->>'evidence_step_id'
     AND status='STEP_PASS_WITH_EVIDENCE';
   IF v_app_evidence IS NULL THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_EVIDENCE_NOT_READY');
   END IF;
   v_app_value:=jsonb_extract_path_text(v_app_evidence,VARIADIC v_app_path);
   IF v_app_value IS DISTINCT FROM v_app_contract->>'positive_literal' THEN
     RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code',case when v_app_value='false'
             then 'SKILL_NOT_REQUIRED_BY_INPUT_VALIDATE'
             else 'SKILL_APPLICABILITY_NOT_ATTESTED' end);
   END IF;
 END IF;
 v_receipt:=jsonb_build_object('execution_id',p_execution_id,'skill_code',p_skill_code,
     'selection_mode',v_skill->>'selection_mode',
     'selection_evidence',v_skill->'selection_evidence','channel',p_channel);
 -- Source authority, input validation, dedupe, handler and child opener belong to official invoker.
 BEGIN
   v_out:=public.lf_skill_invoke_v1(p_skill_code,p_execution_id,p_input);
 EXCEPTION WHEN OTHERS THEN
   RETURN jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'parent_execution_id',p_execution_id,'skill_code',p_skill_code,
     'blocking_code',SQLSTATE,'error_message',left(SQLERRM,500),
     'selection_receipt',v_receipt,'effect_authorized',false,
     'next_action','CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS');
 END;
 IF v_out->>'status' IN ('BLOCKED','FAILED','SKILL_FAILED_AS_FINDING') THEN
   RETURN v_out||jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'parent_execution_id',p_execution_id,'selection_receipt',v_receipt,
     'effect_authorized',false,
     'next_action','CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS');
 END IF;
 IF v_out->>'status'='COMPLETED' AND nullif(v_out->>'skill_run_id','') IS NOT NULL THEN
   INSERT INTO public.lf_profile_skill_selection_receipt_v1(
     skill_run_id,parent_execution_id,skill_code,profile_code,channel,
     selection_mode,selection_evidence,selection_sha256)
   VALUES (v_out->>'skill_run_id',p_execution_id,p_skill_code,e.target_code,p_channel,
       v_skill->>'selection_mode',v_receipt,
       encode(extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),'hex'))
   ON CONFLICT(skill_run_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM public.lf_profile_skill_selection_receipt_v1 s
                 WHERE s.skill_run_id=v_out->>'skill_run_id'
                   AND s.parent_execution_id=p_execution_id AND s.skill_code=p_skill_code
                   AND s.selection_evidence=v_receipt) THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_REPLAY_RECEIPT_MISMATCH');
   END IF;
 END IF;
 RETURN v_out||jsonb_build_object('parent_execution_id',p_execution_id,
     'selection_mode',v_skill->>'selection_mode','selection_receipt',v_receipt);
END;
$function$
;

-- lf_profile_skill_runtime_ticket_issue_v1 md5 3b3fffdb37780f543546263cf732ab5d
CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(p_execution_id text, p_skill_code text, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
DECLARE
 v_e public.lf_operation_execution%rowtype;
 v_plan jsonb;v_invoked jsonb;v_req jsonb;
 v_catalog_runtime_slug text;
 v_id uuid:=extensions.gen_random_uuid();
 v_exp timestamptz:=clock_timestamp()+interval '5 minutes';
 v_screen integer;
 v_existing_tickets integer;
BEGIN
 IF jsonb_typeof(p_input)<>'object'
   OR p_input->>'execution_id' IS DISTINCT FROM p_execution_id THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_INPUT_INVALID');
 END IF;
 SELECT * INTO v_e FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_type='PERFIL' AND e.status='IN_PROGRESS';
 IF NOT FOUND OR p_input->>'profile_code' IS DISTINCT FROM v_e.target_code THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_PARENT_INVALID');
 END IF;
 v_plan:=public.lf_profile_execution_plan_v1(v_e.target_code,
   v_e.manifest#>>'{router_profile_handoff,channel}',NULL);
 -- Follow the same deterministic-required policy despite optional semantic
 -- pending. Do not issue runtime tickets for unselected optional skills.
 IF v_plan->>'status'='SEMANTIC_SELECTION_REQUIRED'
   AND jsonb_typeof(v_plan#>'{selection_receipt,required_skills}')='array'
   AND EXISTS(SELECT 1 FROM jsonb_array_elements(
        v_plan#>'{selection_receipt,required_skills}') x
       WHERE x->>'skill_code'=p_skill_code
         AND x->>'selection_mode'='DETERMINISTIC_POLICY') THEN
   v_plan:=v_plan||jsonb_build_object(
     'status','READY',
     'skills',v_plan#>'{selection_receipt,required_skills}',
     'selection_mode','TICKET_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED');
 END IF;
 IF v_plan->>'status'<>'READY' OR NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_plan->'skills') sk
    WHERE sk->>'skill_code'=p_skill_code AND sk->>'effect'='READ_ONLY'
 ) THEN RETURN jsonb_build_object(
   'status','BLOCKED','code','SKILL_TICKET_NOT_POLICY_SELECTED'); END IF;
 v_invoked:=public.lf_profile_skill_invoke_selected_v1(
    p_execution_id,v_e.manifest#>>'{router_profile_handoff,channel}',
    p_skill_code,p_input,NULL);
 v_req:=v_invoked->'runtime_request';
 SELECT c.runtime_slug INTO v_catalog_runtime_slug FROM public.lf_skill_catalog_v1 c
 WHERE c.skill_code=p_skill_code AND c.status='READY' AND c.effect='READ_ONLY';
 IF coalesce(v_catalog_runtime_slug,'') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
 OR v_catalog_runtime_slug IS DISTINCT FROM v_req->>'runtime_slug' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','SKILL_RUNTIME_CATALOG_SLUG_MISMATCH');
 END IF;
 IF v_invoked->>'status'<>'RUNTIME_REQUIRED'
    OR v_req->>'transport'<>'DIRECT_EDGE_INVOCATION'
    OR coalesce(v_req->>'runtime_slug','') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
    OR jsonb_typeof(v_req->'request_body')<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_RUNTIME_NOT_ATTESTED',
      'skill_status',v_invoked->>'status');
 END IF;
 -- Strong DB-side bound and serialized ticket issue: no third ticket,
 -- including retries racing across native clients for the same RUN.
 PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('LF_PROFILE_SKILL_TICKET_CAP:'||
       p_execution_id||':'||p_skill_code,0));
 SELECT count(*)::integer INTO v_existing_tickets
 FROM private.lf_profile_skill_runtime_ticket_v1
 WHERE execution_id=p_execution_id AND skill_code=p_skill_code;
 IF v_existing_tickets>=2 THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'code','SKILL_RUNTIME_TICKET_CAP_EXHAUSTED',
     'attempt_count',v_existing_tickets,'production_authorized',false);
 END IF;
 INSERT INTO private.lf_profile_skill_runtime_ticket_v1(
   ticket_id,execution_id,skill_code,runtime_slug,request_body,
   request_sha256,expires_at
 ) VALUES (
   v_id,p_execution_id,p_skill_code,v_req->>'runtime_slug',v_req->'request_body',
   encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex'),v_exp
 );
 IF v_req->>'legacy_ticket_adapter'='INPUT_GOVERNANCE_CONTEXT_PACK_V1' THEN
   v_screen:=nullif(v_req#>>'{request_body,pantalla_id}','')::integer;
   IF p_skill_code<>'INPUT_GOVERNANCE_CONTEXT_PACK'
     OR v_screen IS NULL OR v_screen<1
     OR v_req#>>'{request_body,consumer}'<>'CONTEXT_PACK' THEN
     RAISE EXCEPTION 'SKILL_IG_ADAPTER_SCOPE_INVALID';
   END IF;
   INSERT INTO private.lf_profile_input_governance_runtime_ticket_v1(
     ticket_id,execution_id,pantalla_id,consumer,
     router_handoff_fingerprint,expires_at
   ) VALUES(
     v_id,p_execution_id,v_screen,'CONTEXT_PACK',
     v_e.manifest#>>'{router_profile_handoff,fingerprint_sha256}',v_exp
   );
 END IF;
 RETURN jsonb_build_object('status','AUTHORIZED','ticket',v_id::text,
   'execution_id',p_execution_id,'skill_code',p_skill_code,
   'runtime_slug',v_req->>'runtime_slug',
   'expires_at',v_exp,'transport','DIRECT_EDGE_INVOCATION');
END
$function$
;

-- lf_profile_skill_selection_prepare_v1 md5 24850ec585cecca9a54fe87e3d1ad2da
CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_v1(p_profile_code text, p_channel text, p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_n int;
 v_missing int;
 v_stale int;
 v_required jsonb:='[]'::jsonb;
 v_optional jsonb:='[]'::jsonb;
 v_selected jsonb:='[]'::jsonb;
 v_choice text;
 v_reason text;
 v_refs jsonb;
 v_revision text;
 v_row record;
 v_sem_n int;
BEGIN
 IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL OR
    coalesce(p_channel,'') NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_CHANNEL_INVALID'); END IF;
 -- Follow the existing profile selector registry/policy: no unauthorized profile+channel.
 IF NOT EXISTS (
    SELECT 1 FROM public.lf_profile_selection_registry_v1 d
    JOIN public.lf_profile_selector_policy_v1 p USING(profile_code)
    WHERE d.profile_code=p_profile_code AND d.descriptor_status='CURRENT'
      AND p_channel=ANY(p.channels))
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_SOURCE_OR_CHANNEL_NOT_CURRENT'); END IF;

 -- 'enabled' alone is not owner authorization in a candidate row.
 IF EXISTS (SELECT 1 FROM public.lf_skill_selector_policy_v1 p
   WHERE p.profile_code=p_profile_code AND p.enabled
     AND p_channel=ANY(p.channels) AND p.owner_decision_required) THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_OWNER_DECISION_REQUIRED');
 END IF;
 SELECT count(*) INTO v_n FROM public.lf_skill_selector_policy_v1 p
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels);
 IF v_n=0 THEN
    RETURN jsonb_build_object('status','READY','skills','[]'::jsonb,
      'profile_code',p_profile_code,'channel',p_channel,
      'selection_mode','NO_ENABLED_SKILL_POLICY_LEGACY_STEP40_COMPAT');
 END IF;
 SELECT count(*) INTO v_missing
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_catalog_v1 c ON c.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND (c.skill_code IS NULL OR c.status<>'READY' OR c.required_operation<>p.required_operation
        OR NOT(c.effect=ANY(p.allowed_effects))
        OR (c.effect='WRITE_GOVERNED' AND NOT EXISTS (
            SELECT 1 FROM public.lf_profile_write_authority_v1 a
            WHERE a.profile_code=p_profile_code AND a.operation_code=c.required_operation
              AND a.status='ACTIVE')));
 IF v_missing>0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DETERMINISTIC_POLICY_OR_CATALOG_INVALID',
       'invalid_bindings',v_missing);
 END IF;
 SELECT count(*) INTO v_stale
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_selection_registry_v1 d ON d.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND (d.skill_code IS NULL OR d.descriptor_status<>'CURRENT'
        OR d.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
        OR coalesce(d.source_revision,'')='');
 IF v_stale>0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DESCRIPTOR_STALE_OR_MISSING',
       'stale_count',v_stale);
 END IF;
 FOR v_row IN
   SELECT p.skill_code,p.selection_mode,c.handler_fn,c.required_operation,c.effect,
          c.input_required,d.descriptor,d.source_ref,d.source_revision
     FROM public.lf_skill_selector_policy_v1 p
     JOIN public.lf_skill_catalog_v1 c USING(skill_code)
     JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
    WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
    ORDER BY p.skill_code
 LOOP
   IF v_row.selection_mode='DETERMINISTIC_REQUIRED' THEN
     v_required:=v_required||jsonb_build_array(jsonb_build_object(
       'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
       'required_operation',v_row.required_operation,'effect',v_row.effect,
       'input_required',to_jsonb(v_row.input_required),'selection_mode','DETERMINISTIC_POLICY',
       'selection_evidence',jsonb_build_object('reason','MANDATORY_POLICY_FOR_PROFILE_AND_CHANNEL',
         'descriptor_revision',v_row.source_revision,'source_ref',v_row.source_ref),
       'invoker','public.lf_skill_invoke_v1'));
   ELSE
     v_optional:=v_optional||jsonb_build_array(jsonb_build_object(
       'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
       'required_operation',v_row.required_operation,'effect',v_row.effect,
       'input_required',to_jsonb(v_row.input_required),'descriptor',v_row.descriptor,
       'source_ref',v_row.source_ref,'source_revision',v_row.source_revision));
   END IF;
 END LOOP;
 IF jsonb_array_length(v_optional)=0 THEN
   IF p_semantic_decision IS NOT NULL THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_UNEXPECTED_SEMANTIC_DECISION');
   END IF;
   v_selected:=v_required;
 ELSE
   IF p_semantic_decision IS NULL THEN
     RETURN jsonb_build_object('status','SEMANTIC_SELECTION_REQUIRED',
       'blocking_code',null,'required_skills',v_required,
       'semantic_candidates',v_optional,'profile_code',p_profile_code,'channel',p_channel,
       'selection_mode','DETERMINISTIC_FILTER_THEN_NATIVE_SEMANTIC',
       'next_action','NATIVE_PROFILE_JUDGE_SKILL_AND_SUBMIT_SAME_EXECUTION');
   END IF;
   IF jsonb_typeof(p_semantic_decision)<>'object' OR
      p_semantic_decision ? 'selected_skill_codes' OR
      jsonb_typeof(p_semantic_decision->'selected_skill_code')<>'string'
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_SELECTION_AMBIGUOUS'); END IF;
   v_choice:=nullif(btrim(p_semantic_decision->>'selected_skill_code'),'');
   v_reason:=nullif(btrim(p_semantic_decision->>'reason'),'');
   v_refs:=p_semantic_decision->'evidence_refs';
   v_revision:=p_semantic_decision->>'descriptor_revision';
   SELECT count(*) INTO v_sem_n FROM jsonb_array_elements(v_optional) x
   WHERE x->>'skill_code'=v_choice AND x->>'source_revision'=v_revision;
   IF v_sem_n<>1 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_CHOICE_NOT_ALLOWED_OR_STALE'); END IF;
   IF v_reason IS NULL OR jsonb_typeof(v_refs)<>'array' OR jsonb_array_length(v_refs)=0
      OR coalesce(p_semantic_decision->>'review_mode','')<>'CURRENT_CONTEXT_REVIEW' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_EVIDENCE_MISSING');
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'skill_code',x->>'skill_code','handler_fn',x->>'handler_fn',
      'required_operation',x->>'required_operation','effect',x->>'effect',
      'input_required',x->'input_required','selection_mode','SEMANTIC_DESCRIPTOR',
      'selection_evidence',jsonb_build_object('reason',v_reason,'evidence_refs',v_refs,
        'descriptor_revision',v_revision,'source_ref',x->>'source_ref',
        'review_mode','CURRENT_CONTEXT_REVIEW'),
      'invoker','public.lf_skill_invoke_v1')),'[]'::jsonb)
   INTO v_selected FROM jsonb_array_elements(v_optional) x
   WHERE x->>'skill_code'=v_choice;
   v_selected:=v_required||v_selected;
 END IF;
 RETURN jsonb_build_object('status','READY','skills',v_selected,
   'profile_code',p_profile_code,'channel',p_channel,
   'selection_mode','DETERMINISTIC_THEN_SEMANTIC',
   'source','lf_skill_selector_policy_v1+lf_skill_selection_registry_v1+lf_skill_catalog_v1',
   'independence_attested',false);
END;
$function$
;

-- lf_router_pipeline_context_profile_semantic_prepare_v2 md5 2d7b39fe0f89bfdf3ceef705588a1911
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_semantic_prepare_v2(p_context_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
BEGIN
    DECLARE
      v_ctx jsonb; v_stage1 jsonb; v_route jsonb;
      v_trans jsonb; v_req jsonb; v_literal text;
    BEGIN
      IF left(coalesce(p_context_token,''),6)<>'RCTX2:' THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_context_token,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      v_stage1:=v_ctx->'stage1_payload';
      v_route:=v_ctx->'stage2_route';
      v_trans:=v_ctx->'transition';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_EXECUTION_CONTEXT_V2'
        OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
        OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
        OR v_stage1->>'texto_original' IS DISTINCT FROM v_literal
        OR coalesce((public.lf_router_stage1_validate_v2(v_stage1)->>'valid')::boolean,false) IS NOT TRUE
        OR v_route IS DISTINCT FROM public.lf_router_route_v1(v_stage1,'{}'::jsonb,false)
        OR v_trans IS DISTINCT FROM public.lf_router_route_transition_resolve_v1(v_route)
        OR v_trans->>'next_step'<>'profile_semantic_selection'
        OR v_trans->>'transition_code'<>'PROFILE_SELECTION_REQUIRED'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_NOT_VERIFIED');
      END IF;
      v_req:=v_route->'profile_selection_request';
      IF jsonb_typeof(v_req)<>'object'
         OR v_req->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
         OR v_req->>'literal_request' IS DISTINCT FROM v_literal
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_PROFILE_REQUEST_INVALID');
      END IF;
      RETURN jsonb_build_object(
         'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','CONTEXT_TRANSPORT',
         'context_token',p_context_token,
         'current_step','resolve_next_transition',
         'next_step','profile_semantic_selection',
         'profile_selection_request',v_req,
         'profile_selection_request_sha256',
             encode(extensions.digest(convert_to(v_req::text,'UTF8'),'sha256'),'hex'),
         'stage1_payload',v_stage1,
         'transition',v_trans,
         'persistence_policy','CONTRACT_CONTROLLED',
         'effect_authority',false,
         'downstream_execution_allowed',false
      );
    END;
END
$function$
;

-- lf_router_pipeline_context_profile_semantic_submit_v2 md5 269c144458c84beaa30ae8ffbf734186
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_semantic_submit_v2(p_context_token text, p_raw text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
BEGIN
    DECLARE
      v_prep jsonb; v_ctx jsonb; v_raw_result jsonb; v_sel jsonb;
      v_after jsonb; v_gate jsonb; v_literal text;
      v_sha text;
    BEGIN
      v_prep:=public.lf_router_pipeline_context_profile_semantic_prepare_v2(p_context_token);
      IF v_prep->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED' THEN
        RETURN v_prep;
      END IF;
      IF nullif(btrim(coalesce(p_raw,'')),'') IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_RAW_REQUIRED');
      END IF;
      v_raw_result:=public.lf_profile_selector_semantic_consume_raw_v1(
        v_prep->'profile_selection_request',p_raw);
      IF v_raw_result->>'status'<>'VALID'
         OR jsonb_typeof(v_raw_result->'result')<>'object'
         OR jsonb_typeof(v_raw_result->'validation')<>'object'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_INVALID',
         'semantic_consume_result',v_raw_result);
      END IF;
      v_sel:=v_raw_result->'result';
      IF v_sel->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status',CASE WHEN v_sel->>'decision'='AMBIGUOUS' THEN 'PROFILE_SELECTION_AMBIGUOUS' ELSE 'PROFILE_SELECTION_NO_MATCH' END,
          'current_step','profile_semantic_selection',
          'semantic_result',v_sel,
          'semantic_validation',v_raw_result->'validation',
          'persistence_policy','CONTRACT_CONTROLLED','effect_authority',false,
          'downstream_execution_allowed',false);
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_context_token,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_INVALID');
      END;
      v_after:=public.lf_router_profile_after_selection_v1(v_ctx->'stage1_payload',v_sel);
      IF v_after->>'status'<>'READY_FOR_GATE2' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code',coalesce(v_after->>'blocking_code','BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_READY'),
          'after_selection_result',v_after,'effect_authority',false);
      END IF;
      v_gate:=public.lf_router_profile_gate2_result_from_selection_v1(
          v_after->'gate2_request',v_sel);
      IF v_gate->>'status'<>'READY' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_GATE2_DERIVATION_FAILED',
          'gate2_derivation',v_gate,'effect_authority',false);
      END IF;
      RETURN jsonb_build_object(
         'status','GATE2_DERIVED_PENDING_GOVERNED_ADMISSION',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','CONTEXT_TRANSPORT',
         'current_step','profile_gate2',
          'next_step','PROFILE_HANDOFF_REQUIRED',
          'next_action','HANDOFF_CONTEXT_TO_SELECTED_PROFILE',
          'terminal',false,
          'continuation_required',true,
          'stop_allowed',false,
          'execution_owner','EJECUCION_PERFIL_LF',
          'router_execution_authority',false,
         'stage1_payload',v_ctx->'stage1_payload',
         'route_result',v_ctx->'stage2_route',
         'transition',v_ctx->'transition',
         'semantic_result',v_sel,
         'semantic_validation',v_raw_result->'validation',
         'after_selection_result',v_after,
         'gate2_derivation',v_gate,
         'persistence_policy','CONTRACT_CONTROLLED',
         'effect_authority',false,
         'downstream_execution_allowed',false,
         'handoff_authorized',false
      );
    END;
END
$function$
;

-- lf_router_pipeline_context_stage1_submit_v2 md5 db6767852494edcf725829e719096fd6
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_stage1_submit_v2(p_context_token text, p_stage1 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_validation jsonb;
BEGIN
  -- The read-only user supplies an encoded JSON envelope in the existing
  -- execution-id parameter. It does not qualify as an execution id or receipt.
    DECLARE
      v_ctx jsonb;
      v_route jsonb;
      v_transition jsonb;
      v_literal text;
    BEGIN
      IF left(coalesce(p_context_token,''),6)<>'RCTX2:' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_CONTEXT_TRANSPORT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_context_token,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_CONTEXT_TRANSPORT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_EXECUTION_CONTEXT_V2'
         OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
         OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
         OR p_stage1->>'texto_original' IS DISTINCT FROM v_literal
         OR p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
      THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_CONTEXT_TRANSPORT_REQUEST_MISMATCH');
      END IF;
      v_validation:=public.lf_router_stage1_validate_v2(p_stage1);
      IF v_validation->>'valid'<>'true' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_ROUTER_STAGE1_INVALID',
          'stage1_validation',v_validation);
      END IF;
      v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
      v_transition:=public.lf_router_route_transition_resolve_v1(v_route);
      IF v_transition->>'status'<>'RESOLVED' THEN
        RETURN jsonb_build_object('status','BLOCKED',
           'blocking_code','BLOCK_ROUTER_TRANSITION_INVALID',
           'stage1_validation',v_validation,
           'route_result',v_route,'transition',v_transition);
      END IF;
      RETURN jsonb_build_object(
        'status','NEXT_TRANSITION_READY',
        'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
        'transport_mode','CONTEXT_TRANSPORT',
        'current_step','resolve_next_transition',
        'next_step',v_transition->>'next_step',
        'stage1_validation',v_validation,
        'stage1_payload',p_stage1,
        'route_result',v_route,
        'transition',v_transition,
        'profile_selection_request',v_route->'profile_selection_request',
        'context_token','RCTX2:'||encode(convert_to(jsonb_build_object(
           'schema_version','LF_ROUTER_EXECUTION_CONTEXT_V2',
           'original_request_text',v_literal,
           'request_sha256',v_ctx->>'request_sha256',
           'stage1_payload',p_stage1,
           'stage2_route',v_route,
           'transition',v_transition,
           'next_step',v_transition->>'next_step',
           'effect_authority',false
        )::text,'UTF8'),'base64'),
        'persistence_policy','CONTRACT_CONTROLLED',
        'effect_authority',false,
        'downstream_execution_allowed',false
      );
    END;
END
$function$
;

-- lf_router_pipeline_profile_semantic_prepare_v1 md5 905b9dba6f033c78783ab513cc451a8d
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s2 public.lf_operation_execution_steps%rowtype;
  st public.lf_operation_execution_steps%rowtype;
  v_request jsonb;
  v_request_sha text;
BEGIN
  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_ctx jsonb; v_stage1 jsonb; v_route jsonb;
      v_trans jsonb; v_req jsonb; v_literal text;
    BEGIN
      IF left(coalesce(p_execution_id,''),6)<>'ROCTX:' THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      v_stage1:=v_ctx->'stage1_payload';
      v_route:=v_ctx->'stage2_route';
      v_trans:=v_ctx->'transition';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_READ_ONLY_CONTEXT_V1'
        OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
        OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
        OR v_stage1->>'texto_original' IS DISTINCT FROM v_literal
        OR coalesce((public.lf_router_stage1_validate_v2(v_stage1)->>'valid')::boolean,false) IS NOT TRUE
        OR v_route IS DISTINCT FROM public.lf_router_route_v1(v_stage1,'{}'::jsonb,false)
        OR v_trans IS DISTINCT FROM public.lf_router_route_transition_resolve_v1(v_route)
        OR v_trans->>'next_step'<>'profile_semantic_selection'
        OR v_trans->>'transition_code'<>'PROFILE_SELECTION_REQUIRED'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_NOT_VERIFIED');
      END IF;
      v_req:=v_route->'profile_selection_request';
      IF jsonb_typeof(v_req)<>'object'
         OR v_req->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
         OR v_req->>'literal_request' IS DISTINCT FROM v_literal
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_PROFILE_REQUEST_INVALID');
      END IF;
      RETURN jsonb_build_object(
         'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','READ_ONLY_CONTEXT',
         'transport_token',p_execution_id,
         'current_step','resolve_next_transition',
         'next_step','profile_semantic_selection',
         'profile_selection_request',v_req,
         'profile_selection_request_sha256',
             encode(extensions.digest(convert_to(v_req::text,'UTF8'),'sha256'),'hex'),
         'stage1_payload',v_stage1,
         'transition',v_trans,
         'trace_persistence','NONE',
         'effect_authority',false,
         'downstream_execution_allowed',false
      );
    END;
  END IF;
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PIPELINE_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO st
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='resolve_next_transition';

  IF NOT FOUND
     OR st.status<>'STEP_PASS_WITH_EVIDENCE'
     OR st.evidence_payload#>>'{transition_result,next_step}'<>'profile_semantic_selection'
     OR st.evidence_payload#>>'{transition_result,transition_code}'<>'PROFILE_SELECTION_REQUIRED'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_TRANSITION_NOT_READY',
      'execution_id',p_execution_id
    );
  END IF;

  SELECT * INTO s2
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage2_route';

  v_request:=s2.evidence_payload#>'{route_result,profile_selection_request}';

  IF jsonb_typeof(v_request)<>'object'
     OR v_request->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_REQUEST_MISSING',
      'execution_id',p_execution_id
    );
  END IF;

  v_request_sha:=encode(
    extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','resolve_next_transition',
    'next_step','profile_semantic_selection',
    'profile_selection_request_sha256',v_request_sha,
    'profile_selection_request',v_request,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$function$
;

-- lf_router_pipeline_profile_semantic_submit_v1 md5 9b0eef4e0cffab64a551ed27d33d823f
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(p_execution_id text, p_raw text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_prepare jsonb;
  v_request jsonb;
  v_consumed jsonb;
  v_result jsonb;
  v_validation jsonb;
  v_request_sha text;
  v_step jsonb;
  v_decision text;
  v_next_step text;
  v_status text;
  v_after_selection jsonb;
BEGIN
  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_prep jsonb; v_ctx jsonb; v_raw_result jsonb; v_sel jsonb;
      v_after jsonb; v_gate jsonb; v_literal text;
      v_sha text;
    BEGIN
      v_prep:=public.lf_router_pipeline_profile_semantic_prepare_v1(p_execution_id);
      IF v_prep->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED' THEN
        RETURN v_prep;
      END IF;
      IF nullif(btrim(coalesce(p_raw,'')),'') IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_RAW_REQUIRED');
      END IF;
      v_raw_result:=public.lf_profile_selector_semantic_consume_raw_v1(
        v_prep->'profile_selection_request',p_raw);
      IF v_raw_result->>'status'<>'VALID'
         OR jsonb_typeof(v_raw_result->'result')<>'object'
         OR jsonb_typeof(v_raw_result->'validation')<>'object'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_INVALID',
         'semantic_consume_result',v_raw_result);
      END IF;
      v_sel:=v_raw_result->'result';
      IF v_sel->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status',CASE WHEN v_sel->>'decision'='AMBIGUOUS' THEN 'PROFILE_SELECTION_AMBIGUOUS' ELSE 'PROFILE_SELECTION_NO_MATCH' END,
          'current_step','profile_semantic_selection',
          'semantic_result',v_sel,
          'semantic_validation',v_raw_result->'validation',
          'trace_persistence','NONE','effect_authority',false,
          'downstream_execution_allowed',false);
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_after:=public.lf_router_profile_after_selection_v1(v_ctx->'stage1_payload',v_sel);
      IF v_after->>'status'<>'READY_FOR_GATE2' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code',coalesce(v_after->>'blocking_code','BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_READY'),
          'after_selection_result',v_after,'effect_authority',false);
      END IF;
      v_gate:=public.lf_router_profile_gate2_result_from_selection_v1(
          v_after->'gate2_request',v_sel);
      IF v_gate->>'status'<>'READY' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_GATE2_DERIVATION_FAILED',
          'gate2_derivation',v_gate,'effect_authority',false);
      END IF;
      RETURN jsonb_build_object(
         'status','READ_ONLY_GATE2_DERIVED_NOT_AUTHORIZED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','READ_ONLY_CONTEXT',
         'current_step','profile_gate2',
         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'stage1_payload',v_ctx->'stage1_payload',
         'route_result',v_ctx->'stage2_route',
         'transition',v_ctx->'transition',
         'semantic_result',v_sel,
         'semantic_validation',v_raw_result->'validation',
         'after_selection_result',v_after,
         'gate2_derivation',v_gate,
         'trace_persistence','NONE',
         'effect_authority',false,
         'downstream_execution_allowed',false,
         'handoff_authorized',false
      );
    END;
  END IF;
  v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(
    p_execution_id
  );

  IF v_prepare->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED' THEN
    RETURN v_prepare;
  END IF;

  IF nullif(btrim(coalesce(p_raw,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_RAW_REQUIRED',
      'execution_id',p_execution_id
    );
  END IF;

  v_request:=v_prepare->'profile_selection_request';
  v_request_sha:=v_prepare->>'profile_selection_request_sha256';

  v_consumed:=public.lf_profile_selector_semantic_consume_raw_v1(
    v_request,p_raw
  );

  IF v_consumed->>'status'<>'VALID'
     OR jsonb_typeof(v_consumed->'result')<>'object'
     OR jsonb_typeof(v_consumed->'validation')<>'object'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_INVALID',
      'execution_id',p_execution_id,
      'semantic_consume_result',v_consumed
    );
  END IF;

  v_result:=v_consumed->'result';
  v_validation:=v_consumed->'validation';
  v_decision:=v_result->>'decision';

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'profile_semantic_selection',
    'router-profile-selection://'||(v_result->>'semantic_receipt_sha256'),
    jsonb_build_object(
      'profile_selection_request_sha256',v_request_sha,
      'semantic_result',v_result,
      'semantic_validation',v_validation,
      'semantic_receipt_sha256',v_result->>'semantic_receipt_sha256',
      'decision',v_decision
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(
        v_step->>'code',
        'BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_NOT_CLEAN'
      ),
      'execution_id',p_execution_id,
      'step_result',v_step
    );
  END IF;

  IF v_decision='SELECTED' THEN
    v_next_step:='profile_after_selection';
    v_status:='PROFILE_SELECTION_READY';
  ELSIF v_decision='AMBIGUOUS' THEN
    v_next_step:='profile_selection_decision';
    v_status:='PROFILE_SELECTION_AMBIGUOUS';
  ELSE
    v_next_step:='blocked_no_profile_match';
    v_status:='PROFILE_SELECTION_NO_MATCH';
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','profile_semantic_selection',
        'next_step',v_next_step,
        'profile_selection_decision',v_decision,
        'selected_profile_code',v_result->>'selected_profile_code',
        'semantic_receipt_sha256',v_result->>'semantic_receipt_sha256'
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  IF v_decision='SELECTED' THEN
    v_after_selection:=
      public.lf_router_pipeline_profile_after_selection_continue_v1(
        p_execution_id
      );

    RETURN v_after_selection||jsonb_build_object(
      'semantic_status','PROFILE_SELECTION_READY',
      'semantic_result',v_result,
      'semantic_validation',v_validation
    );
  END IF;

  RETURN jsonb_build_object(
    'status',v_status,
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','profile_semantic_selection',
    'next_step',v_next_step,
    'semantic_result',v_result,
    'semantic_validation',v_validation,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$function$
;

-- lf_router_pipeline_stage1_submit_v1 md5 82747605ce694ecb3b2ddee405d8bff7
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_stage1_submit_v1(p_execution_id text, p_stage1 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_validation jsonb;
  v_stage1_sha text;
  v_step jsonb;
  v_stage2 jsonb;
BEGIN
  -- The read-only user supplies an encoded JSON envelope in the existing
  -- execution-id parameter. It does not qualify as an execution id or receipt.
  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_ctx jsonb;
      v_route jsonb;
      v_transition jsonb;
      v_literal text;
    BEGIN
      IF left(coalesce(p_execution_id,''),6)<>'ROCTX:' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_READ_ONLY_CONTEXT_V1'
         OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
         OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
         OR p_stage1->>'texto_original' IS DISTINCT FROM v_literal
         OR p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
      THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUEST_MISMATCH');
      END IF;
      v_validation:=public.lf_router_stage1_validate_v2(p_stage1);
      IF v_validation->>'valid'<>'true' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_ROUTER_STAGE1_INVALID',
          'stage1_validation',v_validation);
      END IF;
      v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
      v_transition:=public.lf_router_route_transition_resolve_v1(v_route);
      IF v_transition->>'status'<>'RESOLVED' THEN
        RETURN jsonb_build_object('status','BLOCKED',
           'blocking_code','BLOCK_ROUTER_TRANSITION_INVALID',
           'stage1_validation',v_validation,
           'route_result',v_route,'transition',v_transition);
      END IF;
      RETURN jsonb_build_object(
        'status','NEXT_TRANSITION_READY',
        'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
        'transport_mode','READ_ONLY_CONTEXT',
        'current_step','resolve_next_transition',
        'next_step',v_transition->>'next_step',
        'stage1_validation',v_validation,
        'stage1_payload',p_stage1,
        'route_result',v_route,
        'transition',v_transition,
        'profile_selection_request',v_route->'profile_selection_request',
        'transport_token','ROCTX:'||encode(convert_to(jsonb_build_object(
           'schema_version','LF_ROUTER_READ_ONLY_CONTEXT_V1',
           'original_request_text',v_literal,
           'request_sha256',v_ctx->>'request_sha256',
           'stage1_payload',p_stage1,
           'stage2_route',v_route,
           'transition',v_transition,
           'next_step',v_transition->>'next_step',
           'effect_authority',false
        )::text,'UTF8'),'base64'),
        'trace_persistence','NONE',
        'effect_authority',false,
        'downstream_execution_allowed',false
      );
    END;
  END IF;
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PIPELINE_EXECUTION_INVALID'
    );
  END IF;

  IF p_stage1 IS NULL OR jsonb_typeof(p_stage1)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_STAGE1_REQUIRED',
      'execution_id',p_execution_id
    );
  END IF;

  v_validation:=public.lf_router_stage1_validate_v2(p_stage1);
  v_stage1_sha:=encode(
    extensions.digest(convert_to(p_stage1::text,'UTF8'),'sha256'),
    'hex'
  );

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'stage1_seal',
    'router-stage1://'||v_stage1_sha,
    jsonb_build_object(
      'stage1_payload',p_stage1,
      'stage1_sha256',v_stage1_sha,
      'stage1_validation',v_validation
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_step->>'code','BLOCK_ROUTER_STAGE1_NOT_CLEAN'),
      'execution_id',p_execution_id,
      'stage1_validation',v_validation,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','stage1_seal',
        'next_step','stage2_route',
        'stage1_sha256',v_stage1_sha
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  v_stage2:=public.lf_router_pipeline_stage2_continue_v1(p_execution_id);

  RETURN v_stage2||jsonb_build_object(
    'stage1_status','SEALED',
    'stage1_sha256',v_stage1_sha
  );
END
$function$
;

-- lf_router_route_v1 md5 8a74d20e7ad65f1fb3f80f1cc4bbb313
CREATE OR REPLACE FUNCTION public.lf_router_route_v1(p_stage1 jsonb, p_caller jsonb DEFAULT '{}'::jsonb, p_nivel2_consentido boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_rs jsonb;
  v jsonb;
  v_formas text[];
  v_hint text;
  v_cands jsonb;
  v_n int;
  v_l2 jsonb;
  v_d jsonb;
  v_schema text;
  v_channel text;
  v_business text;
  v_scope jsonb;
  v_is_v2 boolean := false;
  v_base jsonb;
  v_profile_selection_request jsonb;
BEGIN
  v_schema := p_stage1->>'schema_version';
  v_is_v2 := v_schema='LF_ROUTER_STAGE1_V2';

  IF v_is_v2 THEN
    v := public.lf_router_stage1_validate_v2(p_stage1);
  ELSE
    v := public.lf_router_stage1_validate_v1(p_stage1);
  END IF;

  v_base := jsonb_build_object(
    'schema_version','LF_ROUTER_ROUTE_V1',
    'router','ACT-0001',
    'stage1_schema_version',v_schema,
    'downstream_execution_allowed',false
  );

  IF (v->>'valid')::boolean IS NOT TRUE THEN
    RETURN v_base || jsonb_build_object(
      'paso',CASE WHEN v_is_v2 THEN 'INVALID_STAGE1_V2' ELSE 'INVALID_STAGE1' END,
      'codigos',v->'codes',
      'motivo_es','La salida de la etapa 1 no cumple el contrato.',
      'siguiente_paso_es','Rehacer la etapa 1 corrigiendo los codigos indicados.'
    );
  END IF;

  IF (p_stage1->>'es_operacion')::boolean IS FALSE THEN
    RETURN v_base || jsonb_build_object(
      'paso','DIRECT_ANSWER',
      'motivo_es','No es una operacion: se responde sin inventario.',
      'siguiente_paso_es','Responder directamente al usuario.'
    );
  END IF;

  IF (p_stage1->>'ambiguo')::boolean IS TRUE THEN
    RETURN v_base || jsonb_build_object(
      'paso','ASK_USER',
      'pregunta_usuario',p_stage1->'pregunta_usuario',
      'alternativas',p_stage1->'alternativas',
      'motivo_es','La solicitud tiene mas de una lectura posible.',
      'siguiente_paso_es','Hacer esa unica pregunta y repetir la etapa 1.'
    );
  END IF;

  IF v_is_v2 THEN
    v_channel := nullif(p_stage1->>'canal_candidato','');
    v_business := nullif(p_stage1->>'negocio_codigo','');
    v_scope := p_stage1->'alcance';

    v_base := v_base || jsonb_build_object(
      'canal_candidato',v_channel,
      'negocio_codigo',v_business,
      'alcance',v_scope
    );

    IF jsonb_array_length(coalesce(p_stage1->'negocios_afectados','[]'::jsonb))>0 THEN
      RETURN v_base || jsonb_build_object(
        'paso','MULTINEGOCIO_PENDIENTE',
        'negocios_afectados',p_stage1->'negocios_afectados',
        'motivo_es','La fase actual esta cerrada a LF.',
        'siguiente_paso_es','Resolver autoridad por negocio antes de habilitar otras operaciones.'
      );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.lf_router_business_catalog_v1 b WHERE b.business_code=v_business AND b.status='ENABLED') THEN
      RETURN v_base || jsonb_build_object(
        'paso','NEGOCIO_NO_HABILITADO',
        'motivo_es','La fase actual del Router atiende exclusivamente LF.',
        'siguiente_paso_es','No despachar; otros negocios se habilitan en una fase separada.'
      );
    END IF;

    IF v_channel='PROGRAMACION' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v2(p_stage1->>'texto_original', v_channel, CASE
          WHEN nullif(btrim(coalesce(p_stage1#>>'{alcance,source_execution_id}','')),'') IS NOT NULL
          THEN jsonb_build_object('source_execution_id',p_stage1#>>'{alcance,source_execution_id}')
          ELSE NULL::jsonb
        END, p_stage1);

      RETURN v_base || jsonb_build_object(
        'paso','PROGRAMACION_PROFILE_SELECTION_REQUIRED',
        'router_work_mode','DERIVATION_ONLY',
        'channel_precondition',jsonb_build_object(
          'code','PROGRAMACION_PRECHECK_DEFINICION',
          'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
          'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
          'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
          'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
          'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
          'alcance_requiere_ready',v_scope IS NOT NULL,
          'required_before_channel_effect',true,
          'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
        ),
        'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
        'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'gate2_authorizes_profile_effects',false,
        'motivo_es','Programacion se administra por perfiles. El perfil puede investigar en solo lectura; definicion/currentness y PG-01 siguen siendo obligatorios antes de cualquier efecto tecnico.',
        'siguiente_paso_es','Seleccionar perfil CURRENT, resolver Gate2 para administracion READ_ONLY y exigir la precondicion de Programacion antes de implementar/probar/desplegar.',
        'downstream_execution_allowed',false
      );
    END IF;

    IF v_channel='OPERACIONES' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v2(p_stage1->>'texto_original', v_channel, CASE
          WHEN nullif(btrim(coalesce(p_stage1#>>'{alcance,source_execution_id}','')),'') IS NOT NULL
          THEN jsonb_build_object('source_execution_id',p_stage1#>>'{alcance,source_execution_id}')
          ELSE NULL::jsonb
        END, p_stage1);

      RETURN v_base || jsonb_build_object(
        'paso','OPERACIONES_PROFILE_SELECTION_REQUIRED',
        'router_work_mode','DERIVATION_ONLY',
        'channel_precondition',jsonb_build_object(
          'code','OPERACIONES_CAPACIDAD_REQUERIDA',
          'capability_hint_candidato',nullif(p_stage1->>'capability_hint',''),
          'capability_hint_autoridad','CANDIDATE_ONLY',
          'alcance_requiere_autorizacion',v_scope IS NOT NULL,
          'capability_status_required','ACTIVE',
          'actor_scope_authorization_required',true,
          'required_before_channel_effect',true,
          'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
        ),
        'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
        'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'gate2_authorizes_profile_effects',false,
        'motivo_es','Operaciones se administra por perfiles. Gate2 autoriza solo la investigacion del perfil; la capacidad ACTIVE y el alcance del actor siguen siendo obligatorios antes de ejecutar una operacion.',
        'siguiente_paso_es','Seleccionar perfil CURRENT y resolver Gate2 READ_ONLY; cualquier efecto operativo exige capacidad/actor/alcance autorizados.',
        'downstream_execution_allowed',false
      );
    END IF;


    IF v_channel='PRODUCTO' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v2(p_stage1->>'texto_original', v_channel, CASE
          WHEN nullif(btrim(coalesce(p_stage1#>>'{alcance,source_execution_id}','')),'') IS NOT NULL
          THEN jsonb_build_object('source_execution_id',p_stage1#>>'{alcance,source_execution_id}')
          ELSE NULL::jsonb
        END, p_stage1);

      RETURN v_base||jsonb_build_object(
        'paso','PRODUCTO_PROFILE_SELECTION_REQUIRED',
        'router_work_mode','DERIVATION_ONLY',
        'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
        'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'motivo_es','ACT-0001 clasifica y deriva. El perfil seleccionado investiga la fuente canonica en solo lectura.',
        'siguiente_paso_es','Seleccionar un perfil CURRENT y derivar investigacion READ_ONLY; cualquier cambio posterior usa una operacion gobernada separada.',
        'downstream_execution_allowed',false
      );
    END IF;




    -- If no exact aggregate product context is available, preserve the bounded
    -- canonical search fallback. target_type never narrows the search by itself.
    v_hint := NULL;
  ELSE
    -- Legacy V1 compatibility only. V2 never reads or emits this field.
    IF p_stage1->>'sistema'<>'LF' THEN
      RETURN v_base || jsonb_build_object(
        'paso','SYSTEM_NOT_SUPPORTED',
        'sistema',p_stage1->'sistema',
        'motivo_es','El contrato V1 heredado solo atiende LF.',
        'siguiente_paso_es','Informar al usuario; no despachar.'
      );
    END IF;

    v_hint := nullif(p_stage1->>'capability_hint','');
    IF v_hint IS NOT NULL THEN
      v_d := public.lf_router_dispatch_v1(
        p_stage1->>'texto_original',
        v_hint,
        coalesce(p_caller,'{}'::jsonb)
      );
      RETURN v_base || jsonb_build_object(
        'paso','DISPATCHED',
        'despacho',v_d,
        'motivo_es','Se conserva el despacho del contrato V1 heredado.',
        'siguiente_paso_es','Seguir el resultado del despacho.'
      );
    END IF;
  END IF;

  IF coalesce(p_stage1->>'accion','') ~* '(cambi|modific|actualiz|edit|correg|renombr|update|change|modify|fix|rename)' THEN
    v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
    IF v_rs->>'subject_binding_state'='RESOLVED'
       AND jsonb_array_length(coalesce(v_rs->'executor_candidates','[]'::jsonb))>0
       AND v_rs->>'blocking_code'='BLOCK_EXECUTOR_CAPABILITY_UNATTESTED' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROPUESTA_PERFIL',
        'sujeto',v_rs->'subject_candidates',
        'perfil_candidato',v_rs#>'{executor_candidates,0}',
        'modo','PROPUESTA_SOLO_LECTURA',
        'instruccion_literal',p_stage1->>'texto_original',
        'router_resolve',jsonb_build_object(
          'status',v_rs->>'status',
          'blocking_code',v_rs->>'blocking_code',
          'semantic_gap_code',v_rs->>'semantic_gap_code',
          'request_sha256',v_rs->>'request_sha256'
        ),
        'siguiente_operacion',jsonb_build_object(
          'operation_code','EJECUCION_PERFIL_LF',
          'entrypoint','ROUTER_ONLY',
          'executor_mode','GPT_NATIVE',
          'read_only',true,
          'no_write',true
        ),
        'motivo_es','El sujeto esta resuelto y el perfil candidato solo puede trabajar en propuesta.',
        'siguiente_paso_es','Trabajar la propuesta y volver al Router para cualquier efecto.'
      );
    END IF;
  END IF;

  SELECT array_agg(e#>>'{}')
  INTO v_formas
  FROM jsonb_array_elements(p_stage1->'formas_busqueda') e;

  SELECT coalesce(
    jsonb_agg(
      x ORDER BY
      (x->>'exacto')::boolean DESC,
      (x->>'cobertura')::numeric DESC,
      (x->>'apariciones')::int DESC,
      (x->>'mejor_posicion')::int ASC,
      x->>'codigo'
    ),
    '[]'::jsonb
  )
  INTO v_cands
  FROM (
    SELECT jsonb_build_object(
      'origen',min(c->>'origen'),
      'codigo',c->>'codigo',
      'tipo',min(c->>'tipo'),
      'titulo',min(c->>'titulo'),
      'exacto',bool_or((c->>'exacto')::boolean),
      'cobertura',round(max((c->>'coinciden')::numeric/nullif((c->>'de')::numeric,0)),2),
      'apariciones',count(*),
      'mejor_posicion',min(pos)
    ) AS x
    FROM unnest(v_formas) f,
         LATERAL jsonb_array_elements(public.lf_router_search_v1(f,5)->'candidatos')
           WITH ORDINALITY AS t(c,pos)
    GROUP BY c->>'codigo'
  ) s;

  v_n := jsonb_array_length(v_cands);
  IF v_n=1 OR (
    v_n>1
    AND (v_cands->0->>'exacto')::boolean IS TRUE
    AND (v_cands->1->>'exacto')::boolean IS NOT TRUE
  ) THEN
    RETURN v_base || jsonb_build_object(
      'paso','CANDIDATO_UNICO',
      'candidatos',jsonb_build_array(v_cands->0),
      'motivo_es','El nivel 1 dio un candidato unico o exacto. Es una pista, no autoridad.',
      'siguiente_paso_es','Confirmar identidad y continuar por la autoridad correspondiente.'
    );
  ELSIF v_n>1 THEN
    RETURN v_base || jsonb_build_object(
      'paso','ELEGIR_O_PROFUNDIZAR',
      'candidatos',v_cands,
      'sondeo_sugerido',jsonb_build_object(
        'leer_juntos',(
          SELECT jsonb_agg(x->>'codigo')
          FROM (SELECT x FROM jsonb_array_elements(v_cands) x LIMIT 3) t
        ),
        'max_sondeos_por_duda',3,
        'cuarto_sondeo_requiere_autorizacion_del_propietario',true,
        'solo_lectura',true
      ),
      'motivo_es','El nivel 1 dio varios candidatos.',
      'siguiente_paso_es','Elegir con evidencia acotada; preguntar solo si persiste ambiguedad material.'
    );
  END IF;

  IF NOT coalesce(p_nivel2_consentido,false) THEN
    RETURN v_base || jsonb_build_object(
      'paso','NIVEL_2_CONSENTIMIENTO',
      'candidatos','[]'::jsonb,
      'pregunta_usuario','Busque en el inventario y no lo encuentro. ¿Busco fuera del inventario (repo y tablas, solo lectura)?',
      'motivo_es','El nivel 1 no dio candidatos.',
      'siguiente_paso_es','Pedir consentimiento antes del nivel 2.'
    );
  END IF;

  SELECT coalesce(
    jsonb_agg(x ORDER BY (x->>'coinciden')::int DESC,x->>'ref'),
    '[]'::jsonb
  )
  INTO v_l2
  FROM (
    SELECT DISTINCT ON (c->>'ref') c AS x
    FROM unnest(v_formas) f,
         LATERAL jsonb_array_elements(public.lf_router_search_nivel2_v1(f,5)->'candidatos') c
    ORDER BY c->>'ref',(c->>'coinciden')::int DESC
  ) d;

  RETURN v_base || jsonb_build_object(
    'paso','NIVEL_2_RESULTADO',
    'resultado',CASE
      WHEN jsonb_array_length(v_l2)>0 THEN 'ENCONTRADO_FUERA_DE_INVENTARIO'
      ELSE 'NO_ENCONTRADO_EN_INDICE'
    END,
    'candidatos',(
      SELECT coalesce(jsonb_agg(x),'[]'::jsonb)
      FROM (SELECT x FROM jsonb_array_elements(v_l2) x LIMIT 5) t
    ),
    'downstream_execution_allowed',false
  );
END
$function$
;

-- lf_router_stage1_validate_v2 md5 b9b8f68bc4cf02af657830857a80bfc2
CREATE OR REPLACE FUNCTION public.lf_router_stage1_validate_v2(p_stage1 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_codes text[] := '{}';
  v_es_op jsonb;
  v_amb jsonb;
  v_formas jsonb;
  v_alts jsonb;
  v_corr jsonb;
  v_preg jsonb;
  v_hint jsonb;
  v_scope jsonb;
  v_businesses jsonb;
  v_channel text;
  v_business text;
  v_reason text;
  v_scope_state text;
  v_nformas int := 0;
  v_nalts int := 0;
BEGIN
  IF p_stage1 IS NULL OR jsonb_typeof(p_stage1) <> 'object' THEN
    RETURN jsonb_build_object('valid',false,'codes',jsonb_build_array('NOT_AN_OBJECT'));
  END IF;

  IF p_stage1->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_STAGE1_V2' THEN
    v_codes := array_append(v_codes,'BAD_V2_SCHEMA_VERSION');
  END IF;
  IF p_stage1 ? 'sistema' THEN
    v_codes := array_append(v_codes,'CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2');
  END IF;
  -- Closed schema: all inputs not declared in the active contract fail closed.
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_stage1) AS field(field_name)
    WHERE field.field_name <> ALL (ARRAY[
      'schema_version','texto_original','es_operacion','ambiguo',
      'respuesta_directa','sujeto','accion','formas_busqueda',
      'alternativas','correcciones','pregunta_usuario','capability_hint',
      'downstream_execution_allowed','canal_candidato','negocio_codigo',
      'negocios_afectados','razon_seleccion','alcance'
    ]::text[])
  ) THEN
    v_codes := array_append(v_codes,'CAMPO_NO_PERMITIDO_EN_V2');
  END IF;
  IF nullif(btrim(coalesce(p_stage1->>'texto_original','')),'') IS NULL THEN
    v_codes := array_append(v_codes,'ORIGINAL_TEXT_REQUIRED');
  END IF;
  IF p_stage1->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
    v_codes := array_append(v_codes,'DOWNSTREAM_EXECUTION_MUST_BE_FALSE');
  END IF;

  v_es_op := p_stage1->'es_operacion';
  v_amb := p_stage1->'ambiguo';
  IF jsonb_typeof(v_es_op) IS DISTINCT FROM 'boolean' THEN
    v_codes := array_append(v_codes,'ES_OPERACION_BOOL_REQUIRED');
  END IF;
  IF jsonb_typeof(v_amb) IS DISTINCT FROM 'boolean' THEN
    v_codes := array_append(v_codes,'AMBIGUO_BOOL_REQUIRED');
  END IF;

  v_formas := coalesce(p_stage1->'formas_busqueda','[]'::jsonb);
  IF jsonb_typeof(v_formas) <> 'array' THEN
    v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_INVALID');
    v_formas := '[]'::jsonb;
  ELSIF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_formas) e
    WHERE jsonb_typeof(e) <> 'string' OR btrim(e#>>'{}')=''
  ) THEN
    v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_INVALID');
    v_formas := '[]'::jsonb;
  END IF;
  v_nformas := jsonb_array_length(v_formas);
  IF v_nformas > 4 THEN v_codes := array_append(v_codes,'TOO_MANY_FORMAS'); END IF;

  v_alts := coalesce(p_stage1->'alternativas','[]'::jsonb);
  IF jsonb_typeof(v_alts) <> 'array' THEN
    v_codes := array_append(v_codes,'ALTERNATIVAS_INVALID');
    v_alts := '[]'::jsonb;
  ELSIF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_alts) e
    WHERE jsonb_typeof(e) <> 'string' OR btrim(e#>>'{}')=''
  ) THEN
    v_codes := array_append(v_codes,'ALTERNATIVAS_INVALID');
    v_alts := '[]'::jsonb;
  END IF;
  v_nalts := jsonb_array_length(v_alts);
  IF v_nalts > 3 THEN v_codes := array_append(v_codes,'TOO_MANY_ALTERNATIVAS'); END IF;

  v_preg := p_stage1->'pregunta_usuario';
  IF v_preg IS NOT NULL AND jsonb_typeof(v_preg) IS DISTINCT FROM 'null' THEN
    IF jsonb_typeof(v_preg) <> 'string' OR btrim(v_preg#>>'{}')='' THEN
      v_codes := array_append(v_codes,'PREGUNTA_INVALID');
    END IF;
  END IF;

  v_hint := p_stage1->'capability_hint';
  IF v_hint IS NOT NULL AND jsonb_typeof(v_hint) IS DISTINCT FROM 'null' THEN
    IF jsonb_typeof(v_hint) <> 'string' OR (v_hint#>>'{}') !~ '^[A-Z][A-Z0-9_]{2,63}$' THEN
      v_codes := array_append(v_codes,'CAPABILITY_HINT_INVALID');
    END IF;
  END IF;

  v_corr := coalesce(p_stage1->'correcciones','[]'::jsonb);
  IF jsonb_typeof(v_corr) <> 'array' THEN
    v_codes := array_append(v_codes,'CORRECCIONES_INVALID');
  ELSIF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_corr) e
    WHERE jsonb_typeof(e)<>'object'
       OR jsonb_typeof(e->'de')<>'string'
       OR jsonb_typeof(e->'a')<>'string'
       OR btrim(e->>'de')=''
       OR btrim(e->>'a')=''
       OR lower(btrim(e->>'de'))=lower(btrim(e->>'a'))
  ) THEN
    v_codes := array_append(v_codes,'CORRECCIONES_INVALID');
  END IF;

  v_channel := nullif(btrim(coalesce(p_stage1->>'canal_candidato','')),'');
  v_business := nullif(btrim(coalesce(p_stage1->>'negocio_codigo','')),'');
  v_reason := nullif(btrim(coalesce(p_stage1->>'razon_seleccion','')),'');
  v_scope := p_stage1->'alcance';
  v_businesses := coalesce(p_stage1->'negocios_afectados','[]'::jsonb);

  IF jsonb_typeof(v_businesses) <> 'array' THEN
    v_codes := array_append(v_codes,'NEGOCIOS_AFECTADOS_INVALIDOS');
    v_businesses := '[]'::jsonb;
  ELSE
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_businesses) e
      WHERE jsonb_typeof(e)<>'string' OR NOT EXISTS (SELECT 1 FROM public.lf_router_business_catalog_v1 b WHERE b.business_code=(e#>>'{}'))
    ) THEN
      v_codes := array_append(v_codes,'NEGOCIOS_AFECTADOS_INVALIDOS');
      v_businesses := '[]'::jsonb;
    ELSIF (
      SELECT count(*) FROM jsonb_array_elements(v_businesses)
    ) <> (
      SELECT count(DISTINCT e#>>'{}') FROM jsonb_array_elements(v_businesses) e
    ) THEN
      v_codes := array_append(v_codes,'NEGOCIOS_AFECTADOS_INVALIDOS');
      v_businesses := '[]'::jsonb;
    END IF;
  END IF;

  IF v_scope IS NOT NULL AND jsonb_typeof(v_scope) IS DISTINCT FROM 'null' THEN
    IF jsonb_typeof(v_scope) <> 'object' THEN
      v_codes := array_append(v_codes,'ALCANCE_INVALID');
    ELSE
      IF coalesce(v_scope->>'target_type','') !~ '^[A-Z][A-Z0-9_]{1,63}$' THEN
        v_codes := array_append(v_codes,'ALCANCE_TIPO_INVALIDO');
      END IF;
      IF v_scope ? 'target_hint'
         AND jsonb_typeof(v_scope->'target_hint') IS DISTINCT FROM 'null'
         AND (jsonb_typeof(v_scope->'target_hint')<>'string' OR btrim(v_scope->>'target_hint')='') THEN
        v_codes := array_append(v_codes,'ALCANCE_PISTA_INVALIDA');
      END IF;
      v_scope_state := coalesce(v_scope->>'resolution_status','UNRESOLVED');
      IF v_scope_state NOT IN ('NOT_REQUIRED','UNRESOLVED','MULTIPLE_MATCHES') THEN
        v_codes := array_append(v_codes,'ALCANCE_ESTADO_NO_PERMITIDO_EN_STAGE1');
      END IF;
      IF nullif(v_scope->>'target_ref','') IS NOT NULL OR v_scope->'verified'='true'::jsonb THEN
        v_codes := array_append(v_codes,'ALCANCE_NO_PUEDE_CERTIFICARSE_EN_STAGE1');
      END IF;
    END IF;
  END IF;

  IF v_es_op='false'::jsonb THEN
    IF p_stage1->'respuesta_directa' IS DISTINCT FROM 'true'::jsonb THEN
      v_codes := array_append(v_codes,'NON_OPERATION_REQUIRES_DIRECT_ANSWER');
    END IF;
    IF v_nformas>0 OR (v_hint IS NOT NULL AND jsonb_typeof(v_hint) IS DISTINCT FROM 'null') THEN
      v_codes := array_append(v_codes,'NON_OPERATION_MUST_NOT_SEARCH');
    END IF;
    IF v_channel IS NOT NULL OR v_business IS NOT NULL THEN
      v_codes := array_append(v_codes,'NO_OPERACION_NO_TIENE_RUTA');
    END IF;
    IF jsonb_array_length(v_businesses)>0 THEN
      v_codes := array_append(v_codes,'NO_OPERACION_NO_TIENE_NEGOCIOS');
    END IF;
    IF v_scope IS NOT NULL AND jsonb_typeof(v_scope) IS DISTINCT FROM 'null' THEN
      v_codes := array_append(v_codes,'NO_OPERACION_NO_TIENE_ALCANCE');
    END IF;
  ELSIF v_es_op='true'::jsonb THEN
    IF p_stage1->'respuesta_directa'='true'::jsonb THEN
      v_codes := array_append(v_codes,'OPERATION_CANNOT_BE_DIRECT_ANSWER');
    END IF;
    IF NOT (
      nullif(btrim(coalesce(p_stage1->>'sujeto','')),'') IS NOT NULL
      OR nullif(btrim(coalesce(p_stage1->>'accion','')),'') IS NOT NULL
    ) THEN
      v_codes := array_append(v_codes,'SUBJECT_OR_ACTION_REQUIRED');
    END IF;
    IF v_nformas=0 THEN v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_REQUIRED'); END IF;

    IF v_channel IS NULL OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES') THEN
      v_codes := array_append(v_codes,'CANAL_NO_RECONOCIDO');
    END IF;

    IF v_reason IS NULL THEN v_codes := array_append(v_codes,'RAZON_SELECCION_REQUERIDA'); END IF;
    IF v_business IS NULL AND jsonb_array_length(v_businesses)=0 THEN
      v_codes := array_append(v_codes,'NEGOCIO_REQUERIDO_EN_V2');
    END IF;
    IF v_business IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.lf_router_business_catalog_v1 b WHERE b.business_code=v_business) THEN
      v_codes := array_append(v_codes,'NEGOCIO_CODIGO_INVALIDO');
    END IF;
    IF jsonb_array_length(v_businesses)>0 AND (v_business IS NOT NULL OR jsonb_array_length(v_businesses)<2) THEN
      v_codes := array_append(v_codes,'MULTINEGOCIO_INCONSISTENTE');
    END IF;
  END IF;

  IF v_amb='true'::jsonb AND NOT (
    v_nalts BETWEEN 2 AND 3
    AND jsonb_typeof(v_preg)='string'
    AND btrim(v_preg#>>'{}')<>''
  ) THEN
    v_codes := array_append(v_codes,'AMBIGUOUS_REQUIRES_ALTERNATIVES_AND_ONE_QUESTION');
  END IF;
  IF v_amb='false'::jsonb AND v_nalts>0 THEN
    v_codes := array_append(v_codes,'ALTERNATIVES_WITHOUT_AMBIGUITY');
  END IF;

  SELECT coalesce(array_agg(DISTINCT c ORDER BY c),'{}') INTO v_codes FROM unnest(v_codes) c;
  RETURN jsonb_build_object('valid',cardinality(v_codes)=0,'codes',to_jsonb(v_codes));
END
$function$
;
