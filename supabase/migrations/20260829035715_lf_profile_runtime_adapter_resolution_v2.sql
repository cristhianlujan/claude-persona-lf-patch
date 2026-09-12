alter table private.lf_profile_runtime_queue_v1
  add column if not exists lf_adapter_resolution jsonb not null default '[]'::jsonb;

alter table private.lf_profile_runtime_queue_v1
  drop constraint if exists lf_profile_runtime_queue_adapter_resolution_ck;

alter table private.lf_profile_runtime_queue_v1
  add constraint lf_profile_runtime_queue_adapter_resolution_ck
  check (jsonb_typeof(lf_adapter_resolution) = 'array');

comment on column private.lf_profile_runtime_queue_v1.lf_adapter_resolution is
  'Router/orchestrator decision for every governed adapter binding on this profile execution. Each bound adapter must be APPLY or SKIP with a non-empty reason; runtime verifies against v_lf_router_adapter_bindings before model execution.';
