create table if not exists private.lf_profile_runtime_queue_v1 (
  request_id uuid primary key default gen_random_uuid(),
  operation_code text not null default 'EJECUCION_PERFIL_LF' check (operation_code = 'EJECUCION_PERFIL_LF'),
  profile_code text not null check (btrim(profile_code) <> ''),
  profile_slug text not null check (profile_slug ~ '^[a-z0-9_]+$'),
  profile_source_paths jsonb not null check (jsonb_typeof(profile_source_paths) = 'array' and jsonb_array_length(profile_source_paths) > 0),
  input_literal text not null check (btrim(input_literal) <> ''),
  input_image_base64 text,
  input_image_media_type text,
  input_image_sha256 text,
  status text not null default 'PENDING' check (status in ('PENDING','RUNNING','SUCCEEDED','BLOCKED','FAILED')),
  requested_by text not null default 'CHATGPT',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  github_comment_id bigint,
  github_run_id bigint,
  github_run_attempt integer,
  github_sha text,
  runtime_provider text,
  runtime_model_id text,
  result_package jsonb,
  raw_output jsonb,
  receipt jsonb,
  runtime_attestation jsonb,
  error_code text,
  error_detail text,
  constraint lf_profile_runtime_queue_image_triplet_ck check (
    (input_image_base64 is null and input_image_media_type is null and input_image_sha256 is null)
    or
    (input_image_base64 is not null and input_image_media_type in ('image/png','image/jpeg','image/webp') and input_image_sha256 ~ '^[0-9a-f]{64}$')
  )
);

create index if not exists lf_profile_runtime_queue_status_created_idx
  on private.lf_profile_runtime_queue_v1 (status, created_at);

revoke all on table private.lf_profile_runtime_queue_v1 from public, anon, authenticated;
comment on table private.lf_profile_runtime_queue_v1 is 'Private zero-cost profile runtime request/result queue. Public GitHub trigger carries request_id only; prompts/images/results remain private.';
