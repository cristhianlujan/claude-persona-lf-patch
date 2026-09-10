begin;

update public.lf_policy_versions
set status='SUPERSEDED',
    superseded_at=now(),
    updated_by_execution_id='EXEC-SOURCE-AUTHORITY-VISUAL-SUPPORT-20260910-001',
    updated_at=now()
where policy_code='POL-LF-SOURCE-RESOLUTION'
  and status='ACTIVE';

with p as (
  select jsonb_build_object(
    'rules', jsonb_build_array(
      'CANONICAL_ID_BEFORE_FREE_SEARCH',
      'REGISTERED_ALIAS_ONLY',
      'SOURCE_OF_TRUTH_BEFORE_REPOSITORY_CONTENT',
      'NO_SIMILARITY_BASED_AUTHORITY_INFERENCE',
      'CLASSIFY_SOURCE_FAMILY_BEFORE_HYDRATION',
      'CONTROLLED_FALLBACK_REQUIRES_EVIDENCE',
      'SUPABASE_IS_ONLY_OPERATIONAL_AUTHORITY',
      'GOOGLE_DRIVE_IS_NON_AUTHORITATIVE_STORAGE',
      'GOOGLE_DRIVE_IMAGE_VISUAL_SUPPORT_ALLOWED_WITH_SUPABASE_BINDING',
      'GOOGLE_DOCS_SHEETS_ARE_NOT_OPERATIONAL_SOURCES',
      'EXTERNAL_STORAGE_URL_MUST_NOT_BE_HYDRATED_FOR_OPERATIONAL_AUTHORITY',
      'VISUAL_SUPPORT_CANNOT_DECIDE_STATE_RULES_ROUTING_PERMISSIONS',
      'VISUAL_SUPPORT_REQUIRES_IMAGE_ASSET_AND_SUPABASE_BINDING',
      'TECHNICAL_REPOSITORY_CONTENT_REQUIRES_EXPLICIT_SUPABASE_BINDING'
    ),
    'scope','TRANSVERSAL_LF_GOVERNANCE',
    'version','v1.4-transversal-supabase-authority-visual-support',
    'authority','SUPABASE',
    'policy_kind','SOURCE_RESOLUTION_POLICY',
    'resolution_order',jsonb_build_array(
      'ACT-0001','public.v_lf_fuente_operativa','CANONICAL_ID','REGISTERED_ALIAS','CANONICAL_BINDING','SOURCE_ARTIFACT','CONTROLLED_FALLBACK'
    ),
    'family_strategies',jsonb_build_object(
      'MIGRATION',jsonb_build_object(
        'flow',jsonb_build_array('SUPABASE_LEDGER_VERSION_NAME_STATE','EXACT_GITHUB_MIGRATION_PATH_PR_HEAD','CANONICAL_PARITY_VALIDATOR','BROADER_SEARCH_IF_UNRESOLVED','ZIP_LAST_RESORT_ONLY'),
        'rules',jsonb_build_array('SUPABASE_FIRST_MIGRATIONS','NO_ZIP_MIGRATIONS'),
        'zip_exception_required_fields',jsonb_build_array('zip_reason','files_needed','direct_routes_attempted','why_direct_failed')
      ),
      'EXISTING_ARTIFACT',jsonb_build_object(
        'modes',jsonb_build_array('EVALUATE_EXISTING','REMEDIATE_EXISTING'),
        'required',jsonb_build_array('source_artifact_ref','source_image_sha256','source_dimensions'),
        'on_missing','FAIL_CLOSED',
        'downstream_authorized',false,
        'visual_support_source_policy',jsonb_build_object(
          'google_drive_image_allowed',true,
          'requires_supabase_binding',true,
          'allowed_asset_types',jsonb_build_array('IMAGE_ASSET'),
          'authority',false,
          'may_support_visual_evaluation',true,
          'may_decide_operational_state',false,
          'may_supply_rules_or_permissions',false
        ),
        'remediate_additional_required',jsonb_build_array('authorized_delta','target_component_id','visual_evidence','acceptance_criteria')
      )
    ),
    'operational_authority_contract',jsonb_build_object(
      'authority_system','SUPABASE',
      'operational_source','public.v_lf_fuente_operativa',
      'google_drive',jsonb_build_object(
        'role','STORAGE_OR_VISUAL_SUPPORT',
        'authority',false,
        'operational_read',false,
        'visual_support_read',true,
        'visual_support_requires_asset_type','IMAGE_ASSET',
        'visual_support_requires_supabase_binding',true,
        'hydrate_for_operational_decision',false
      ),
      'google_docs_sheets',jsonb_build_object(
        'role','STORAGE_OR_HUMAN_MIRROR',
        'authority',false,
        'operational_read',false,
        'visual_support_read',false,
        'hydrate_for_operational_decision',false
      ),
      'github',jsonb_build_object(
        'role','TECHNICAL_IMPLEMENTATION_ARTIFACT',
        'authority',false,
        'requires_supabase_binding',true
      ),
      'legacy_import_fields',jsonb_build_object('role','LINEAGE_ONLY','authority',false)
    )
  ) as payload
)
insert into public.lf_policy_versions(
  policy_code,policy_version,policy_payload,policy_sha,status,effective_at,superseded_at,source_ref,created_by_execution_id,updated_by_execution_id
)
select
  'POL-LF-SOURCE-RESOLUTION',
  'v1.4-transversal-supabase-authority-visual-support',
  p.payload,
  encode(digest(p.payload::text,'sha256'),'hex'),
  'ACTIVE',
  now(),
  null,
  'supabase://public/lf_policy_versions/POL-LF-SOURCE-RESOLUTION/v1.4-transversal-supabase-authority-visual-support',
  'EXEC-SOURCE-AUTHORITY-VISUAL-SUPPORT-20260910-001',
  'EXEC-SOURCE-AUTHORITY-VISUAL-SUPPORT-20260910-001'
from p;

update public.lf_activos
set metadata = coalesce(metadata,'{}'::jsonb)
  || jsonb_build_object(
       'storage_refs', coalesce(metadata->'storage_refs','{}'::jsonb)
         || jsonb_build_object(
              'google_drive', coalesce(metadata->'storage_refs'->'google_drive','{}'::jsonb)
                || jsonb_build_object(
                     'role','VISUAL_SUPPORT_ONLY',
                     'authority',false,
                     'operational_read_allowed',false,
                     'visual_support_read_allowed',true,
                     'visual_support_requires_supabase_binding',true,
                     'policy_version','v1.4-transversal-supabase-authority-visual-support',
                     'normalized_at',now()
                   )
            ),
       'source_governance',coalesce(metadata->'source_governance','{}'::jsonb)
         || jsonb_build_object(
              'operational_authority','SUPABASE',
              'operational_source_ref','supabase://public/lf_activos/'||codigo_activo,
              'drive_role','VISUAL_SUPPORT_ONLY',
              'drive_authority',false,
              'drive_visual_support_read_allowed',true,
              'drive_operational_read_allowed',false,
              'policy_code','POL-LF-SOURCE-RESOLUTION',
              'policy_version','v1.4-transversal-supabase-authority-visual-support'
            )
     ),
    updated_by_execution_id='EXEC-SOURCE-AUTHORITY-VISUAL-SUPPORT-20260910-001'
where archived_at is null
  and tipo_activo='IMAGE_ASSET'
  and formato_nativo='PNG'
  and metadata->'storage_refs' ? 'google_drive';

commit;
