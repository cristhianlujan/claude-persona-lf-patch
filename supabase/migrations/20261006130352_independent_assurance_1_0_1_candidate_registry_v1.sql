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
      jsonb_set(
        jsonb_set(
          jsonb_set(
            manifest,
            '{version}',
            to_jsonb('1.0.1'::text),
            true
          ),
          '{contract,input}',
          to_jsonb('dependency_schema + producer_root/reviewer_root; roots may remain unqualified for same-schema compatibility or both be schema.function for qualified cross-schema closure + optional provider-bound data/author evidence + adjudicated exceptions'::text),
          true
        ),
        '{measurement,method}',
        to_jsonb('PG_PROC_STATIC_CLOSURE_V1 + PG_PROC_STATIC_CLOSURE_QUALIFIED_V1'::text),
        true
      ),
      '{measurement,cross_schema}',
      jsonb_build_object(
        'supported',true,
        'qualified_root_format','schema.function',
        'behavior','EXPLICIT_QUALIFIED_ROOTS_ONLY',
        'unqualified_cross_schema_search_path_calls','NOT_RESOLVED'
      ),
      true
    ),
    '{compatibility}',
    coalesce(manifest->'compatibility','{}'::jsonb)
      || jsonb_build_object(
        'backward_compatible_same_schema',true,
        'qualified_cross_schema_roots',true,
        'parallel_route',false,
        'new_judge_codes',false,
        'runtime_activation',false,
        'production_activation',false,
        'parallel_review_operation',false,
        'strategy_review_behavior_changed',false,
        'canonical_operation_revision_change',false
      ),
    true
  ),
  repeat('0',64),
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261006123000_independent_assurance_qualified_cross_schema_v1.sql',
  docs_ref,
  validator_ref,
  now(),
  'CHATGPT-T-INDEP-CROSS-SCHEMA-20261006'
from public.lf_capability_version_registry
where capability_code='INDEPENDENT_ASSURANCE' and version='1.0.0'
on conflict (capability_code,version) do nothing;