-- T-INDEP / PAULO-035 — close the bounded operation-definition mutation provenance execution.
-- This does NOT requalify the operation and does NOT promote INDEPENDENT_ASSURANCE v2.
-- Requalification remains a separate exact-revision gate; capability v1 remains current.

DO $pre$
DECLARE
  v_revision text;
BEGIN
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
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_BINDING_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND operation_type='INDEPENDENT_REVIEW'
      AND lifecycle_state_code='OP_OPERATIONAL'
      AND applies_to_asset_type IS NULL
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_OPERATION_NOT_GENERALIZED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_version_registry
    WHERE capability_code='INDEPENDENT_ASSURANCE'
      AND version='2.0.0'
      AND release_state='RELEASED'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_V2_NOT_MATERIALIZED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_current
    WHERE capability_code='INDEPENDENT_ASSURANCE'
      AND version='1.0.0'
      AND manifest_sha256='a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_V1_CURRENT_CHANGED';
  END IF;

  IF to_regprocedure('public.lf_independent_review_begin_v2(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_record_independent_review_step_v2(text,text,text,jsonb,text,text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_GENERIC_SURFACE_MISSING';
  END IF;

  v_revision:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  IF public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',v_revision) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_REQUALIFICATION_GATE_NOT_VISIBLE:%',v_revision;
  END IF;
END
$pre$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002'
WHERE execution_id='CHATGPT-T-INDEP-PAULO-035-20261002'
  AND status='IN_PROGRESS';

DO $post$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='CHATGPT-T-INDEP-PAULO-035-20261002'
      AND operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND status='COMPLETED'
      AND completed_at IS NOT NULL
      AND coalesce((manifest->>'operation_definition_mutation_provenance')::boolean,false)=true
      AND coalesce((manifest->>'runtime_activation')::boolean,false)=false
      AND coalesce((manifest->>'production_activation')::boolean,false)=false
      AND coalesce((manifest->>'promotion_authorized')::boolean,false)=false
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PROVENANCE_CLOSE_NOT_TERMINAL';
  END IF;
END
$post$;
