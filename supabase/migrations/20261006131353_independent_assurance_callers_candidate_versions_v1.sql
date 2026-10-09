insert into public.lf_capability_version_registry(
  capability_code,version,version_major,version_minor,version_patch,
  release_state,supersedes_version,manifest,manifest_sha256,
  source_ref,docs_ref,validator_ref,created_at,created_by_execution_id
)
select
  capability_code,
  '1.0.1',1,0,1,
  'RELEASED','1.0.0',
  jsonb_set(
    jsonb_set(
      manifest,
      '{version}',
      to_jsonb('1.0.1'::text),
      true
    ),
    '{dependencies,INDEPENDENT_ASSURANCE}',
    jsonb_build_object(
      'version','1.0.1',
      'manifest_sha256','b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'
    ),
    true
  ) || jsonb_build_object(
    'supersession_reason','Dependency pin advanced to backward-compatible INDEPENDENT_ASSURANCE 1.0.1; classifier semantics unchanged.'
  ),
  repeat('0',64),
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261006123000_independent_assurance_qualified_cross_schema_v1.sql',
  docs_ref,
  validator_ref,
  now(),
  'SAFE-CHANGE-ADMISSION-IA-PIN-20261006'
from public.lf_capability_version_registry
where capability_code='SAFE_CHANGE_ADMISSION' and version='1.0.0'
on conflict (capability_code,version) do nothing;

insert into public.lf_capability_version_registry(
  capability_code,version,version_major,version_minor,version_patch,
  release_state,supersedes_version,manifest,manifest_sha256,
  source_ref,docs_ref,validator_ref,created_at,created_by_execution_id
)
select
  capability_code,
  '1.0.2',1,0,2,
  'RELEASED','1.0.1',
  (
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              manifest,
              '{version}',
              to_jsonb('1.0.2'::text),
              true
            ),
            '{contract,baseline_oracle_contract,required_version}',
            to_jsonb('1.0.1'::text),
            true
          ),
          '{contract,baseline_oracle_contract,required_manifest_sha256}',
          to_jsonb('b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'::text),
          true
        ),
        '{dependencies,independent_assurance,version}',
        to_jsonb('1.0.1'::text),
        true
      ),
      '{dependencies,independent_assurance,manifest_sha256}',
      to_jsonb('b12c44ca0e07d2da4fdcb27f7e8e8da311dfcdaf390e645d45a3cf407a31e6c1'::text),
      true
    )
    || jsonb_build_object(
      'delivery',
        coalesce(manifest->'delivery','{}'::jsonb)
        || jsonb_build_object(
          'source_commit','7175968a49ca45b03bac44af4f5fa263140f42a0',
          'source_blob_sha1','f68b7a46f7f1800896a9eb3f76caddd86bb2aa7c'
        ),
      'currentness',
        coalesce(manifest->'currentness','{}'::jsonb)
        || jsonb_build_object(
          'source_commit','7175968a49ca45b03bac44af4f5fa263140f42a0',
          'source_blob_sha1','f68b7a46f7f1800896a9eb3f76caddd86bb2aa7c'
        ),
      'rollback',
        coalesce(manifest->'rollback','{}'::jsonb)
        || jsonb_build_object('mode','PROMOTE_PREVIOUS_VERSION_1_0_1'),
      'migration',
        coalesce(manifest->'migration','{}'::jsonb)
        || jsonb_build_object('id','T_REVJUDGE_REVERSIBLE_CANDIDATE_VERIFICATION_V1_0_2'),
      'supersession_reason',
        'Dependency pin advanced to backward-compatible INDEPENDENT_ASSURANCE 1.0.1; candidate verification semantics unchanged.'
    )
  ),
  repeat('0',64),
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261006123000_independent_assurance_qualified_cross_schema_v1.sql',
  docs_ref,
  validator_ref,
  now(),
  'T-REVJUDGE-IA-PIN-20261006'
from public.lf_capability_version_registry
where capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' and version='1.0.1'
on conflict (capability_code,version) do nothing;