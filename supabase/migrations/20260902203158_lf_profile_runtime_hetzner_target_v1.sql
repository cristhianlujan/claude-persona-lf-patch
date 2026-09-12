alter table private.lf_profile_runtime_queue_v1
  add column if not exists runtime_target text not null default 'GITHUB_ACTIONS',
  add column if not exists runtime_request_envelope jsonb;

alter table private.lf_profile_runtime_queue_v1
  drop constraint if exists lf_profile_runtime_queue_runtime_target_ck;

alter table private.lf_profile_runtime_queue_v1
  add constraint lf_profile_runtime_queue_runtime_target_ck
  check (runtime_target in ('GITHUB_ACTIONS','HETZNER'));

alter table private.lf_profile_runtime_queue_v1
  drop constraint if exists lf_profile_runtime_queue_hetzner_envelope_ck;

alter table private.lf_profile_runtime_queue_v1
  add constraint lf_profile_runtime_queue_hetzner_envelope_ck
  check (
    runtime_target <> 'HETZNER'
    or (
      runtime_request_envelope is not null
      and jsonb_typeof(runtime_request_envelope) = 'object'
    )
  );

create index if not exists lf_profile_runtime_queue_hetzner_pending_idx
  on private.lf_profile_runtime_queue_v1 (created_at, request_id)
  where status = 'PENDING' and runtime_target = 'HETZNER';

comment on column private.lf_profile_runtime_queue_v1.runtime_target is
  'Explicit runtime consumer. Existing rows default to GITHUB_ACTIONS; HETZNER is opt-in canary until promoted.';
comment on column private.lf_profile_runtime_queue_v1.runtime_request_envelope is
  'Exact governed request envelope consumed by the Hetzner Profile Runtime API. Required when runtime_target=HETZNER.';