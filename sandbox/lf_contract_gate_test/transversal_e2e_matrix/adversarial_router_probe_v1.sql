-- LF TRANSVERSAL Router adversarial probe v1
-- READ ONLY: calls STABLE lf_router_resolve_v1 only. No DDL/DML.
-- Validates the canonical ROUTER mode against five malformed/unsupported variants.

with routes as (
  select asset_type,action_code,operation_code,requires_existing_target,requires_missing_target
  from public.lf_router_action_registry
  where status='ACTIVE' and operation_resolution='STATIC' and operation_code is not null
),
target_map(asset_type,target_hint) as (values
  ('ADAPTER','ADAPTER-LF-SHELL-PROFILE-20260827'),
  ('DOC','ACT-0001'),
  ('PERFIL','PERFIL-UI-ARCHITECT'),
  ('SKILL','ACT-0046'),
  ('OPERATION_CODE',null::text)
),
cases as (
  select r.*,
         case when r.requires_existing_target then tm.target_hint else null end target_hint
  from routes r left join target_map tm using(asset_type)
),
modes(mode,is_canonical) as (values
  ('ROUTER',true),
  ('BYPASS',false),
  ('router',false),
  ('ROUTER ',false),
  (' ROUTER',false),
  ('UNSUPPORTED_MODE',false)
),
probes as (
  select c.asset_type,c.action_code,c.operation_code,c.requires_existing_target,c.target_hint,
         m.mode,m.is_canonical,
         public.lf_router_resolve_v1(
           case when c.requires_missing_target
             then 'unique transversal creation zqxv 20260913'
             else 'transversal adversarial route probe 20260913'
           end,
           c.target_hint,
           c.action_code,
           c.asset_type,
           m.mode
         ) as j
  from cases c cross join modes m
),
per_route as (
  select asset_type,action_code,operation_code,
    max((j->>'required_policy_count')::int) filter(where is_canonical) canonical_required,
    max((j->>'resolved_policy_count')::int) filter(where is_canonical) canonical_resolved,
    max(j->>'status') filter(where is_canonical) canonical_status,
    max(j->>'blocking_code') filter(where is_canonical) canonical_block,
    count(*) filter(where not is_canonical and coalesce((j->>'required_policy_count')::int,0)=0) invalid_modes_zero_required,
    count(*) filter(where not is_canonical and j->>'status'='READY_TO_EXECUTE') invalid_modes_ready,
    count(*) filter(where not is_canonical and j->>'status'='INPUT_GOVERNANCE_REQUIRED') invalid_modes_other_gate_block,
    count(*) filter(where not is_canonical and j->>'status'='BLOCKED') invalid_modes_blocked,
    string_agg(distinct coalesce(j->>'blocking_code','<NONE>'),',') filter(where not is_canonical) invalid_block_codes
  from probes
  group by asset_type,action_code,operation_code
)
select *,case
  when invalid_modes_ready=5 and invalid_modes_zero_required=5 then 'BYPASS_AND_READY'
  when invalid_modes_zero_required=5 and invalid_modes_other_gate_block=5 then 'POLICY_FILTER_BYPASS_BUT_OTHER_GATE_BLOCKS'
  when invalid_modes_blocked=5 then 'BLOCKED_BEFORE_POLICY_SURFACE'
  else 'MIXED_REVIEW'
end as adversarial_verdict
from per_route
order by asset_type,action_code;

-- Independent target-authority probe used by the same matrix:
-- SELECT public.lf_router_resolve_v1(
--   'ejecutar skill ACT-0043', 'ACT-0036', 'SKILL_EXECUTION', 'SKILL', 'ROUTER'
-- );
-- Current live readback resolves ACT-0036 and READY_TO_EXECUTE, proving that an
-- explicit target_hint can override the target named in request_text.
