CREATE OR REPLACE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 e public.lf_operation_execution%rowtype;
 v40 jsonb; v50 jsonb; v60 jsonb; changes jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
    OR e.manifest->>'governed_repair_write'<>'true'
    OR e.manifest->>'read_only'<>'false'
    OR e.manifest->>'no_write'<>'false'
    OR e.manifest->>'automatic_impact'<>'false'
    OR e.manifest#>>'{router_profile_handoff,router_authorization_receipt,effect_authority}' IS DISTINCT FROM 'false'
 THEN RETURN false; END IF;
 SELECT evidence_payload INTO v40 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO v50 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO v60 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL
    OR v40->>'analysis_scope'<>'READ_ONLY_WITH_IG_FINDINGS'
    OR v40->>'mutation_authorized' IS DISTINCT FROM 'false'
    OR v40->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR v40#>>'{input_governance,analysis_scope}' IS DISTINCT FROM 'READ_ONLY_WITH_IG_FINDINGS'
    OR jsonb_typeof(v40->'allowed_actions')<>'array'
    OR NOT (v40->'allowed_actions' <@ '["ANALYZE","PROPOSE","VALIDATE","REPORT"]'::jsonb)
    OR v60#>>'{deterministic_validation,status}'<>'PASS'
 THEN RETURN false; END IF;
 changes:=v50#>'{profile_output,repair_execution,changes}';
 IF jsonb_typeof(changes)<>'array' OR jsonb_array_length(changes)=0 THEN RETURN false; END IF;
 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(changes) ch
   WHERE jsonb_typeof(ch)<>'object'
      OR coalesce(ch->>'target_ref','') !~ '^github://cristhianlujan/claude-persona-lf-patch@[0-9a-f]{40}/sandbox/lf_contract_gate_test/'
      OR coalesce(ch->>'after_ref','') IS DISTINCT FROM ch->>'target_ref'
      OR ch->>'before_ref' IS NOT NULL
      OR ch->>'change_type'<>'CREATE'
 ) THEN RETURN false; END IF;
 RETURN true;
END
$function$
