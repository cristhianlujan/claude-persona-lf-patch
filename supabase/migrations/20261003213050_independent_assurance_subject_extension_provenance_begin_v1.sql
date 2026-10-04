-- T-INDEP / PAULO-035 — governed provenance binding for subject-extension mutation.
-- This is NOT capability promotion and does not activate runtime/production behavior.
-- It materializes the scope-matched execution identity already referenced by
-- 20261003213100_independent_assurance_subject_extension_v2.sql before that migration
-- mutates the canonical independent-review operation definition.
--
-- EKB: GOV-ADAPTER-ORPHAN-RESOLVER-MUTATION-20260829
--      CI-CANDIDATE-ROLLBACK-GOVERNED-ACTOR-001

DO $pre$
BEGIN
  IF to_regprocedure('public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_RESERVE_PRIMITIVE_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND operation_type='INDEPENDENT_REVIEW'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_OPERATION_NOT_OPERATIONAL';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='CHATGPT-T-INDEP-PAULO-035-20261002'
      AND (
        operation_code IS DISTINCT FROM 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
        OR target_type IS DISTINCT FROM 'OPERATION'
        OR target_code IS DISTINCT FROM 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
        OR target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
        OR target_path IS DISTINCT FROM 'supabase/migrations/20261003213100_independent_assurance_subject_extension_v2.sql'
        OR request_sha256 IS DISTINCT FROM 'a35c9e9f1266cd2b97f6c0034d7cccb2d5b97a6c2f7a824e3a03d3d4c159776e'
        OR status IS DISTINCT FROM 'IN_PROGRESS'
      )
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_EXECUTION_ID_COLLISION';
  END IF;
END
$pre$;

DO $bind$
DECLARE
  r jsonb;
BEGIN
  r:=public.fn_lf_operation_reserve_execution_v1(
    'CHATGPT-T-INDEP-PAULO-035-20261002',
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    'OPERATION',
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    't-indep:subject-extension-v2:operation-definition-mutation',
    'a35c9e9f1266cd2b97f6c0034d7cccb2d5b97a6c2f7a824e3a03d3d4c159776e',
    'CHATGPT-T-INDEP-PAULO-035-20261002',
    'cristhianlujan/claude-persona-lf-patch',
    'supabase/migrations/20261003213100_independent_assurance_subject_extension_v2.sql',
    jsonb_build_object(
      'mode','OPERATION_DEFINITION_MUTATION_PROVENANCE_ONLY',
      'operation_definition_mutation_provenance',true,
      'target_operation','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
      'candidate_source_sha256','a35c9e9f1266cd2b97f6c0034d7cccb2d5b97a6c2f7a824e3a03d3d4c159776e',
      'source_ref','github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261003213100_independent_assurance_subject_extension_v2.sql',
      'runtime_activation',false,
      'production_activation',false,
      'promotion_authorized',false,
      'business_effect_allowed',false
    )
  );

  IF coalesce(r->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION')
     OR coalesce(r->>'status','')<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_RESERVE_FAILED:%',r;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='CHATGPT-T-INDEP-PAULO-035-20261002'
      AND operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND target_type='OPERATION'
      AND target_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND target_repo='cristhianlujan/claude-persona-lf-patch'
      AND target_path='supabase/migrations/20261003213100_independent_assurance_subject_extension_v2.sql'
      AND status='IN_PROGRESS'
      AND coalesce((manifest->>'operation_definition_mutation_provenance')::boolean,false)=true
      AND manifest->>'target_operation'='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND coalesce((manifest->>'runtime_activation')::boolean,false)=false
      AND coalesce((manifest->>'production_activation')::boolean,false)=false
      AND coalesce((manifest->>'promotion_authorized')::boolean,false)=false
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_BINDING_NOT_EXACT';
  END IF;
END
$bind$;
