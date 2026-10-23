do $$
declare
  v_count integer;
begin
  select count(*)
    into v_count
  from private.lf_skill_artifacts a
  where a.skill_code='creating-integral-user-stories'
    and a.is_current=true
    and a.artifact_status='CANDIDATO_READ_ONLY'
    and a.validation_status='PASS_WITH_EVIDENCE'
    and a.artifact_code in (
      'PERFIL_SCREEN_DECOMPOSER_LF',
      'PERFIL_STORY_CORE_AUTHOR_LF',
      'PERFIL_FIELD_CONTRACT_AUDITOR_LF',
      'PERFIL_CROSS_CUTTING_ENRICHER_LF',
      'PERFIL_STORY_TEST_DERIVER_LF'
    );

  if v_count <> 5 then
    raise exception 'STORY_PROFILE_BINDING_SOURCE_ARTIFACTS_NOT_READY expected=5 observed=%', v_count;
  end if;
end
$$;

with profile_spec as (
  select * from (values
    ('PERFIL-SCREEN-DECOMPOSER-LF','PERFIL_SCREEN_DECOMPOSER_LF','Screen Decomposer LF','screen_decomposer_lf','PERFIL_SCREEN_DECOMPOSER_LF','perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md','SCREEN_DECOMPOSER'),
    ('PERFIL-STORY-CORE-AUTHOR-LF','PERFIL_STORY_CORE_AUTHOR_LF','Story Core Author LF','story_core_author_lf','PERFIL_STORY_CORE_AUTHOR_LF','perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md','STORY_CORE_AUTHOR'),
    ('PERFIL-FIELD-CONTRACT-AUDITOR-LF','PERFIL_FIELD_CONTRACT_AUDITOR_LF','Field Contract Author/Auditor LF','field_contract_auditor_lf','PERFIL_FIELD_CONTRACT_AUDITOR_LF','perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md','FIELD_CONTRACT_AUTHOR_AUDITOR'),
    ('PERFIL-CROSS-CUTTING-ENRICHER-LF','PERFIL_CROSS_CUTTING_ENRICHER_LF','Cross Cutting Enricher LF','cross_cutting_enricher_lf','PERFIL_CROSS_CUTTING_ENRICHER_LF','perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md','CROSS_CUTTING_ENRICHER'),
    ('PERFIL-STORY-TEST-DERIVER-LF','PERFIL_STORY_TEST_DERIVER_LF','Story Test Deriver LF','story_test_deriver_lf','PERFIL_STORY_TEST_DERIVER_LF','perfiles/PERFIL_STORY_TEST_DERIVER_LF.md','STORY_TEST_DERIVER')
  ) as v(codigo_activo,nombre_canonico,display_name,profile_slug,artifact_code,relative_path,worker_role)
), source_artifact as (
  select
    p.*,
    a.version as artifact_version,
    a.content_sha256 as artifact_sha256,
    a.validation_status,
    a.artifact_status
  from profile_spec p
  join private.lf_skill_artifacts a
    on a.skill_code='creating-integral-user-stories'
   and a.artifact_code=p.artifact_code
   and a.relative_path=p.relative_path
   and a.is_current=true
   and a.artifact_status='CANDIDATO_READ_ONLY'
   and a.validation_status='PASS_WITH_EVIDENCE'
)
insert into public.lf_activos (
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,
  estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
  raw_payload,metadata,created_by_execution_id,updated_by_execution_id
)
select
  s.codigo_activo,
  s.nombre_canonico,
  'PERFIL',
  s.display_name,
  'EMBEDDED_SKILL_PROFILE',
  'MARKDOWN_PROFILE_ARTIFACT',
  'CANDIDATO',
  'CANDIDATO',
  'READ_ONLY',
  'PROFILE_REGISTRY',
  'CANDIDATE_READ_ONLY',
  'BLOQUEADO',
  'INVENTARIADO_SUPABASE',
  'artifact-v'||s.artifact_version::text,
  'skills/creating-integral-user-stories/'||s.relative_path,
  'supabase://public/lf_activos/'||s.codigo_activo,
  'LF_GOVERNANCE',
  '2026-10-02',
  'Embedded Story Creator worker profile; identity only, runtime activation blocked',
  'SUPABASE_DIRECT_INVENTORY',
  'LF_SUPABASE_SANDBOX',
  'public.lf_activos',
  0,
  '86700000-0000-4000-8000-202610020001'::uuid,
  jsonb_build_object(
    'repo','cristhianlujan/claude-persona-lf-patch',
    'source_skill_code','creating-integral-user-stories',
    'source_artifact_code',s.artifact_code,
    'source_artifact_version',s.artifact_version,
    'source_artifact_sha256',s.artifact_sha256,
    'entrypoint_path','skills/creating-integral-user-stories/'||s.relative_path,
    'registration_reason','story_creator_embedded_profile_identity_binding'
  ),
  jsonb_build_object(
    'repo','cristhianlujan/claude-persona-lf-patch',
    'repo_path','skills/creating-integral-user-stories',
    'display_name',s.display_name,
    'profile_slug',s.profile_slug,
    'entrypoint_path','skills/creating-integral-user-stories/'||s.relative_path,
    'profile_pack_id','STORY_CREATOR_EMBEDDED_PROFILE_V1',
    'registry_source','SUPABASE',
    'runtime_enabled',false,
    'automatic_impact_enabled',false,
    'source_mode','EMBEDDED_SKILL_PROFILE',
    'source_skill_code','creating-integral-user-stories',
    'source_artifact_code',s.artifact_code,
    'source_artifact_version',s.artifact_version,
    'source_artifact_sha256',s.artifact_sha256,
    'worker_roles',jsonb_build_array(s.worker_role),
    'runtime_binding_state','BLOCKED_PENDING_PROFILE_TASK_RUNTIME_BINDING',
    'canonical_profile_key',s.profile_slug,
    'source_governance',jsonb_build_object(
      'operational_authority','SUPABASE',
      'github_role','TECHNICAL_IMPLEMENTATION_ARTIFACT',
      'github_is_authority',false,
      'artifact_authority','private.lf_skill_artifacts',
      'operational_source_ref','supabase://public/lf_activos/'||s.codigo_activo
    )
  ),
  'EXEC-STORY-PROFILE-ASSET-BINDING-20261002-001',
  'EXEC-STORY-PROFILE-ASSET-BINDING-20261002-001'
from source_artifact s
where not exists (
  select 1 from public.lf_activos a where a.codigo_activo=s.codigo_activo and a.archived_at is null
)
on conflict (codigo_activo) do nothing;

do $$
declare
  v_expected integer := 5;
  v_observed integer;
  v_mismatch integer;
begin
  select count(*) into v_observed
  from public.lf_activos a
  where a.archived_at is null
    and a.codigo_activo in (
      'PERFIL-SCREEN-DECOMPOSER-LF',
      'PERFIL-STORY-CORE-AUTHOR-LF',
      'PERFIL-FIELD-CONTRACT-AUDITOR-LF',
      'PERFIL-CROSS-CUTTING-ENRICHER-LF',
      'PERFIL-STORY-TEST-DERIVER-LF'
    );
  if v_observed <> v_expected then
    raise exception 'STORY_PROFILE_BINDING_ASSET_COUNT_MISMATCH expected=% observed=%', v_expected, v_observed;
  end if;

  select count(*) into v_mismatch
  from public.lf_activos a
  left join private.lf_skill_artifacts s
    on s.skill_code='creating-integral-user-stories'
   and s.artifact_code=a.metadata->>'source_artifact_code'
   and s.is_current=true
  where a.archived_at is null
    and a.codigo_activo in (
      'PERFIL-SCREEN-DECOMPOSER-LF',
      'PERFIL-STORY-CORE-AUTHOR-LF',
      'PERFIL-FIELD-CONTRACT-AUDITOR-LF',
      'PERFIL-CROSS-CUTTING-ENRICHER-LF',
      'PERFIL-STORY-TEST-DERIVER-LF'
    )
    and (
      a.tipo_activo<>'PERFIL'
      or a.estado_operativo<>'READ_ONLY'
      or coalesce(a.metadata->>'runtime_enabled','false')<>'false'
      or a.metadata->>'source_mode'<>'EMBEDDED_SKILL_PROFILE'
      or a.metadata->>'runtime_binding_state'<>'BLOCKED_PENDING_PROFILE_TASK_RUNTIME_BINDING'
      or s.id is null
      or s.validation_status<>'PASS_WITH_EVIDENCE'
      or s.artifact_status<>'CANDIDATO_READ_ONLY'
      or a.metadata->>'source_artifact_sha256' is distinct from s.content_sha256
    );
  if v_mismatch <> 0 then
    raise exception 'STORY_PROFILE_BINDING_READBACK_MISMATCH count=%', v_mismatch;
  end if;
end
$$;
