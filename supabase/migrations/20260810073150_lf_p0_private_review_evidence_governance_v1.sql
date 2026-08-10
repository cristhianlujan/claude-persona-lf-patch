create table if not exists private.lf_p0_review_evidence_objects_v1 (
  evidence_object_id uuid primary key default gen_random_uuid(),
  review_id text not null,
  execution_id text not null,
  object_role text not null check (object_role in ('SOURCE_IMAGE','VISUAL_OUTPUT','CROPS_ZIP','PACKET_MANIFEST','PACKET_ZIP')),
  object_name text not null,
  mime_type text not null,
  content_bytes bigint not null check (content_bytes > 0),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  content bytea not null,
  data_classification text not null check (data_classification in ('INTERNAL','CONFIDENTIAL','SENSITIVE')),
  source_head_sha text not null check (source_head_sha ~ '^[0-9a-f]{40}$'),
  retention_policy text not null default 'UNTIL_TERMINAL_REVIEW',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (review_id, object_role, content_sha256),
  check (octet_length(content) = content_bytes),
  check (encode(digest(content, 'sha256'), 'hex') = content_sha256)
);

create index if not exists lf_p0_review_evidence_objects_v1_review_idx
  on private.lf_p0_review_evidence_objects_v1 (review_id, created_at);

create table if not exists private.lf_p0_human_review_challenges_v1 (
  challenge_id text primary key,
  review_id text not null,
  execution_id text not null,
  source_head_sha text not null check (source_head_sha ~ '^[0-9a-f]{40}$'),
  visual_output_sha256 text not null check (visual_output_sha256 ~ '^[0-9a-f]{64}$'),
  packet_manifest_sha256 text not null check (packet_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  required_reviewer_role text not null check (required_reviewer_role in ('P0_VISUAL_ADJUDICATOR','P0_SECURITY_REVIEWER','P0_PRIVACY_REVIEWER')),
  reviewer_actions jsonb not null,
  evidence_store_ref text not null,
  issued_at timestamptz not null,
  expires_at timestamptz not null,
  data_classification text not null check (data_classification in ('INTERNAL','CONFIDENTIAL','SENSITIVE')),
  dual_review_required boolean not null default false,
  created_at timestamptz not null default now(),
  check (expires_at > issued_at),
  check (jsonb_typeof(reviewer_actions) = 'array'),
  check (jsonb_array_length(reviewer_actions) = 7)
);

create table if not exists private.lf_p0_human_review_decisions_v1 (
  decision_id uuid primary key default gen_random_uuid(),
  challenge_id text not null references private.lf_p0_human_review_challenges_v1(challenge_id) on delete restrict,
  review_id text not null,
  reviewer_identity text not null,
  reviewer_role text not null check (reviewer_role in ('P0_VISUAL_ADJUDICATOR','P0_SECURITY_REVIEWER','P0_PRIVACY_REVIEWER')),
  action text not null check (action in ('CONFIRM_OBSERVATION','CORRECT_WITH_ADJUDICATION','REQUEST_NEW_CAPTURE','REQUEST_ADDITIONAL_CONTEXT','REJECT_AND_BLOCK','ESCALATE_SECURITY','ESCALATE_PRIVACY')),
  external_comment_id bigint not null check (external_comment_id > 0),
  external_comment_created_at timestamptz not null,
  authenticated_provider text not null,
  authenticated_readback jsonb not null,
  created_at timestamptz not null default now(),
  unique (challenge_id, external_comment_id)
);

revoke all on private.lf_p0_review_evidence_objects_v1 from public, anon, authenticated;
revoke all on private.lf_p0_human_review_challenges_v1 from public, anon, authenticated;
revoke all on private.lf_p0_human_review_decisions_v1 from public, anon, authenticated;

grant select, insert on private.lf_p0_review_evidence_objects_v1 to service_role;
grant select, insert on private.lf_p0_human_review_challenges_v1 to service_role;
grant select, insert on private.lf_p0_human_review_decisions_v1 to service_role;

comment on table private.lf_p0_review_evidence_objects_v1 is 'Private durable append-only byte store for governed P0 human-review evidence. No anon/authenticated exposure.';
comment on table private.lf_p0_human_review_challenges_v1 is 'Immutable P0 human-review challenge ledger; decisions are stored separately.';
comment on table private.lf_p0_human_review_decisions_v1 is 'Append-only authenticated external human-review decisions bound to P0 challenges.';
