with cap as (
  select
    r.capability_code,
    r.status,
    c.version,
    c.manifest_sha256,
    v.release_state,
    v.manifest
  from public.lf_capability_registry r
  join public.lf_capability_current c using(capability_code)
  join public.lf_capability_version_registry v
    on v.capability_code=c.capability_code
   and v.version=c.version
   and v.manifest_sha256=c.manifest_sha256
  where r.capability_code='PRIVACY_MINIMALITY_GUARD'
    and r.status='ACTIVE'
    and v.release_state='RELEASED'
),
spec as (
  select jsonb_build_object(
    'schema_version','ENGINEERING_ACTION_SPEC_V3',
    'status','READY',
    'precision','EXPLICIT_CURRENT_CAPABILITY_READBACK',
    'checkpoint_code','GENERIC_CONTRACT',
    'action_kind','READBACK_ONCE',
    'recipe_mode','READBACK_EXACT',
    'requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'target',jsonb_build_object(
      'checkpoint','GENERIC_CONTRACT',
      'declared_assets',jsonb_build_array('PRIVACY_MINIMALITY_GUARD'),
      'declared_events','[]'::jsonb,
      'declared_objects',jsonb_build_array(
        'public.lf_capability_registry',
        'public.lf_capability_current',
        'public.lf_capability_version_registry'
      ),
      'declared_artifacts','[]'::jsonb
    ),
    'expected','PRIVACY_MINIMALITY_GUARD ACTIVE + CURRENT + RELEASED with versioned need+authority+minimality contract and explicit OVERTRACKING negative contract',
    'verification_queries',jsonb_build_array(
      'select r.capability_code,r.status,c.version,v.release_state,v.manifest_sha256,v.manifest->''contract'' contract from public.lf_capability_registry r join public.lf_capability_current c using(capability_code) join public.lf_capability_version_registry v on v.capability_code=c.capability_code and v.version=c.version and v.manifest_sha256=c.manifest_sha256 where r.capability_code=''PRIVACY_MINIMALITY_GUARD'''
    ),
    'action_steps',jsonb_build_array(
      'READ_DECLARED_AUTHORITY_ONCE',
      'ASSERT_ACTIVE_CURRENT_RELEASED_AND_VERSIONED_CONTRACT',
      'PERSIST_DONE_ON_PASS',
      'USE_RETURNED_BOOTSTRAP'
    ),
    'handler_requirement',jsonb_build_object(
      'deliverable','PRIVACY_MINIMALITY_GUARD',
      'live_capability_exists',true,
      'persisted_design_found',true,
      'current_version',version,
      'current_manifest_sha256',manifest_sha256,
      'required_before_execution','[]'::jsonb,
      'next_action','READBACK_AND_CLOSE_GENERIC_CONTRACT'
    ),
    'forbidden',jsonb_build_array(
      'INFER_CONTRACT_FROM_CHECKPOINT_TITLE',
      'REGISTER_CAPABILITY_WITHOUT_VERSIONED_CONTRACT',
      'PROMOTE_CURRENT_WITHOUT_EXACT_MANIFEST',
      'RECREATE_ALREADY_CURRENT_DELIVERABLE'
    )
  ) as action_spec,
  version,
  manifest_sha256
  from cap
)
update programacion.engineering_plan_units pu
set unit_metadata=
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              coalesce(pu.unit_metadata,'{}'::jsonb),
              '{action_specs_v1,GENERIC_CONTRACT}',
              spec.action_spec,
              true
            ),
            '{source_pack_v2,checkpoint_inputs,GENERIC_CONTRACT,missing}',
            '[]'::jsonb,
            true
          ),
          '{source_pack_v2,checkpoint_inputs,GENERIC_CONTRACT,missing_typed}',
          '[]'::jsonb,
          true
        ),
        '{source_pack_v2,checkpoint_inputs,GENERIC_CONTRACT,resolved_authorities_v1}',
        coalesce(
          pu.unit_metadata#>'{source_pack_v2,checkpoint_inputs,GENERIC_CONTRACT,resolved_authorities_v1}',
          '{}'::jsonb
        ) || jsonb_build_object(
          'PRIVACY_MINIMALITY_GUARD',
          jsonb_build_object(
            'version',spec.version,
            'manifest_sha256',spec.manifest_sha256,
            'status','ACTIVE',
            'release_state','RELEASED',
            'authority','public.lf_capability_current'
          )
        ),
        true
      ),
      '{source_pack_v2,checkpoint_inputs,GENERIC_CONTRACT,materialized_at}',
      to_jsonb(clock_timestamp()),
      true
    ),
    '{source_pack_v2,checkpoint_inputs,GENERIC_CONTRACT,materialized_by}',
    to_jsonb('T_PRIVACY_ACTION_SPEC_CURRENT_RECONCILE_V1'::text),
    true
  )
from spec
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='T-PRIVACY';
