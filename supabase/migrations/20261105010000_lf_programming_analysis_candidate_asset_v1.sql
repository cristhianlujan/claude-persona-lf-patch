-- LF / Programming Agent / Analysis
-- Register ONE existing GitHub skill as a candidate catalog asset.
-- Authorized execution path: ACTUALIZACION_DB_LF / DB_WRITE_TRANSPORT / LF Migration Merge Train ONLY.
-- Source owner: PR #3529, merged commit 777c7437668b62dc5b6773161cd771754ba30b5f.
-- Source blob: skills/programming_analysis/SKILL.md @ 9abb2ce0513bcb3241dec459420c394e2c93a03c.
-- No skill creation, regeneration, activation, consumer binding, ACL or other assets.
-- The migration version may be retimestamped by the canonical Train.

BEGIN;

DO $analysis_candidate$
DECLARE
  v_code constant text := 'PROGRAMMING_ANALYSIS_LF';
  v_legacy_code constant text := 'PROGRAMMING_ANALYSIS_A1';
  v_path constant text := 'skills/programming_analysis/SKILL.md';
  v_blob constant text := '9abb2ce0513bcb3241dec459420c394e2c93a03c';
  v_manifest_blob constant text := 'b778f5ce1c510cd91d13cf0584080837e2fc84ea';
  v_merge constant text := '777c7437668b62dc5b6773161cd771754ba30b5f';
  v_execution text;
  v_train_count integer;
  v_batch uuid := pg_catalog.gen_random_uuid();
  v_id bigint;
  v_count integer;
BEGIN
  -- Fail closed if this existing asset was already catalogued, even if archived.
  IF EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo IN (v_code,v_legacy_code)
  ) THEN
    RAISE EXCEPTION 'BLOCK_ANALYSIS_SKILL_ASSET_ALREADY_PRESENT';
  END IF;

  IF length(v_blob) <> 40 OR length(v_manifest_blob) <> 40 OR length(v_merge) <> 40 THEN
    RAISE EXCEPTION 'BLOCK_ANALYSIS_SKILL_SOURCE_IDENTITY';
  END IF;

  -- Require the Train's REAL pre-apply operation, never a direct SQL replay.
  SELECT count(*), min(e.execution_id)
    INTO v_train_count,v_execution
  FROM public.lf_operation_execution e
  WHERE e.operation_code = 'ACTUALIZACION_DB_LF'
    AND e.target_type = 'MIGRATION'
    AND e.target_code ~ '^[0-9]{14}_lf_programming_analysis_candidate_asset_v1$'
    AND e.target_path ~ '^supabase/migrations/[0-9]{14}_lf_programming_analysis_candidate_asset_v1\.sql$'
    AND e.status = 'IN_PROGRESS'
    AND e.manifest->>'producer' = 'lf-migration-merge-train'
    AND e.manifest->>'train_run_id' IS NOT NULL
    AND e.manifest->>'pr' IS NOT NULL;

  IF v_train_count <> 1 OR v_execution IS NULL THEN
    RAISE EXCEPTION 'BLOCK_ANALYSIS_SKILL_TRAIN_EXECUTION_UNATTESTED count=%',v_train_count;
  END IF;

  INSERT INTO public.lf_activos (
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,url,owner_name,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) VALUES (
    v_code,'programming_analysis_lf','SKILL','ANALYSIS_STAGE',
    'CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
    'REGISTER_SKILL_CANDIDATE','v0.1-candidate',
    v_path,'supabase://public/lf_activos/PROGRAMMING_ANALYSIS_LF',
    'LF_GOVERNANCE',
    'Skill unica de Analisis del Agente de Programacion; A1-A15 son pasos internos. Alta de inventario sin runtime.',
    'GITHUB_MAIN_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
    'PROGRAMMING_ANALYSIS_SKILL_CANDIDATE_SOURCE',1,
    v_batch,
    pg_catalog.jsonb_build_object(
      'repository','cristhianlujan/claude-persona-lf-patch',
      'source_pr',3529,
      'source_merge_sha',v_merge,
      'path',v_path,
      'source_blob_sha1',v_blob,
      'manifest_path','skills/programming_analysis/contracts/analysis_skill_manifest_v1.json',
      'manifest_blob_sha1',v_manifest_blob,
      'registered_by_execution_id',v_execution,
      'source_kind','GITHUB_MAIN',
      'asset_registration_only',true
    ),
    pg_catalog.jsonb_build_object(
      'domain','PROGRAMMING_AGENT',
      'inventory_status','CANDIDATE_PENDING_QUALIFICATION',
      'approval_status','NOT_APPROVED',
      'skill_step_model','ONE_STAGE_SKILL_WITH_INTERNAL_A1_A15',
      'internal_step_count',15,
      'no_individual_step_assets',true,
      'legacy_a1_is_skill',false,
      'source_blob_sha1',v_blob,
      'source_merge_sha',v_merge,
      'runtime_binding_enabled',false,
      'production_authorized',false,
      'no_skill_code_generation',true,
      'no_runtime_activation',true,
      'future_operation_code','EJECUCION_SKILL_LF',
      'asset_registration_mode','EXISTING_GITHUB_SKILL_CANDIDATE',
      'governed_migration_execution_id',v_execution
    ),
    v_execution,v_execution
  )
  RETURNING id INTO v_id;

  SELECT count(*) INTO v_count
  FROM public.lf_activos a
  WHERE a.id = v_id
    AND a.codigo_activo = v_code
    AND a.tipo_activo = 'SKILL'
    AND a.subtipo_activo = 'ANALYSIS_STAGE'
    AND a.estado_documental = 'CANDIDATO'
    AND a.estado_operativo = 'READ_ONLY'
    AND a.runtime_estado = 'CANDIDATE_READ_ONLY'
    AND a.impacto_automatico = 'BLOQUEADO'
    AND a.ruta_esperada = v_path
    AND a.raw_payload->>'source_blob_sha1' = v_blob
    AND a.metadata->>'approval_status' = 'NOT_APPROVED'
    AND a.metadata->>'runtime_binding_enabled' = 'false'
    AND a.metadata->>'internal_step_count' = '15'
    AND a.created_by_execution_id = v_execution
    AND a.migration_batch_id = v_batch
    AND a.archived_at IS NULL;

  IF v_count <> 1 OR (SELECT count(*) FROM public.lf_activos WHERE codigo_activo=v_code) <> 1
     OR EXISTS (SELECT 1 FROM public.lf_activos WHERE codigo_activo=v_legacy_code) THEN
    RAISE EXCEPTION 'BLOCK_ANALYSIS_SKILL_POSTWRITE_READBACK';
  END IF;

  RAISE NOTICE 'REGISTER_ANALYSIS_SKILL_CANDIDATE_PASS id=% execution=% batch=%',v_id,v_execution,v_batch;
END;
$analysis_candidate$;

COMMIT;
