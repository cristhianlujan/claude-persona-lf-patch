-- INPUT_GOVERNANCE_AGENT L3C Change Impact CORE3
-- LF EMPRESA / B2B-CARGA-001. Read-only. No SCOPED_PASS authorization.
-- CORE1 bounded artifact reconciliation must not inherit unrelated API blocker by default.
-- CORE2 functional capability change must escalate globally.
-- CORE3 unsupported new semantics must require human/canonical authority.

with observed as (
  select
    p.permission_id,
    p.permission_code,
    p.name as permission_name,
    p.resource_type,
    p.action_code,
    p.status as permission_status,
    e.element_id,
    e.element_code,
    e.element_role,
    e.component_token_id,
    e.semantic_binding_status,
    e.source_refs,
    programacion.fn_input_api_contract_resolution(43) as api
  from lf_ops.permisos p
  join lf_ops.pantalla_elementos e
    on e.pantalla_id=43
   and e.element_code='B2B_CARGA001_EXPORT_HISTORY'
  where p.permission_code='B2B_LOAD_HISTORY_EXPORT'
), core as (
  select 'CORE1_ARTIFACT_COPY_RECONCILIATION'::text as case_code,
         (
           permission_name='Exportar historial'
           and action_code='EXPORT'
           and resource_type='LOAD_HISTORY'
           and element_code='B2B_CARGA001_EXPORT_HISTORY'
           and semantic_binding_status='RESOLVED_ID'
           and source_refs ? 'permission:B2B_LOAD_HISTORY_EXPORT'
           and source_refs ? 'action:EXPORT'
           and coalesce((api->>'has_behavioral_contract')::boolean,false)=false
         ) as pass,
         'SCOPED_CANDIDATE'::text as expected_decision,
         'Existing canonical copy/action/permission/component are internally consistent; unrelated missing API contract remains globally open but is not itself evidence that the artifact-only copy delta changes API semantics.'::text as rationale
  from observed
  union all
  select 'CORE2_ACTION_EXPORT_TO_DELETE',
         (action_code='EXPORT' and resource_type='LOAD_HISTORY'),
         'GLOBAL_ESCALATE',
         'Changing the element capability from canonical EXPORT to DELETE would contradict the observed permission/action authority and must broaden to ACTIONS+PERMISSIONS+SECURITY/API review.'
  from observed
  union all
  select 'CORE3_NEW_UNSUPPORTED_SEMANTICS',
         (
           coalesce((api->>'has_behavioral_contract')::boolean,false)=false
           and coalesce((api->>'has_resolvable_operation_schema_authority')::boolean,false)=false
         ),
         'HUMAN_REQUIRED',
         'Because no behavioral API contract or resolvable schema authority exists, inventing a new endpoint/schema/permission/token cannot be auto-authorized.'
  from observed
)
select jsonb_build_object(
  'benchmark','INPUT_GOV_CHANGE_IMPACT_L3C_CORE3_V1',
  'total',count(*),
  'passed',count(*) filter(where pass),
  'failed',count(*) filter(where not pass),
  'cases',jsonb_agg(jsonb_build_object('case_code',case_code,'pass',pass,'expected_decision',expected_decision,'rationale',rationale) order by case_code),
  'authorization',jsonb_build_object('scoped_pass_authorized',false,'downstream_authorized',false,'production_authorized',false)
) as core_summary
from core;
