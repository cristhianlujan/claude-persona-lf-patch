create table if not exists private.lf_p0_external_durable_evidence_v1 (
  external_evidence_ref text primary key,
  review_id text not null,
  execution_id text not null,
  object_role text not null check (object_role in ('PACKET_ZIP','SOURCE_IMAGE','VISUAL_OUTPUT','CROPS_ARCHIVE','PACKET_MANIFEST')),
  provider text not null check (provider in ('GOOGLE_DRIVE')),
  provider_object_id text not null,
  provider_parent_id text,
  provider_url text not null,
  mime_type text not null,
  content_bytes bigint not null check (content_bytes > 0),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  source_head_sha text not null check (source_head_sha ~ '^[0-9a-f]{40}$'),
  data_classification text not null check (data_classification in ('INTERNAL','CONFIDENTIAL','SENSITIVE')),
  provider_shared boolean not null,
  owner_only_verified boolean not null,
  authenticated_download_readback_verified boolean not null,
  readback_metadata jsonb not null default '{}'::jsonb,
  retention_policy text not null default 'UNTIL_TERMINAL_REVIEW',
  verified_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  unique (review_id, object_role, content_sha256)
);

revoke all on private.lf_p0_external_durable_evidence_v1 from public, anon, authenticated;
grant select, insert on private.lf_p0_external_durable_evidence_v1 to service_role;

comment on table private.lf_p0_external_durable_evidence_v1 is 'Append-only registry for P0 evidence durably stored in an authenticated private external provider and independently downloaded/hash-verified.';

insert into private.lf_p0_external_durable_evidence_v1 (
  external_evidence_ref,
  review_id,
  execution_id,
  object_role,
  provider,
  provider_object_id,
  provider_parent_id,
  provider_url,
  mime_type,
  content_bytes,
  content_sha256,
  source_head_sha,
  data_classification,
  provider_shared,
  owner_only_verified,
  authenticated_download_readback_verified,
  readback_metadata,
  retention_policy
)
values (
  'P0-EXT-REV-P0-LF-ONBOARDING-STEP1-20260810-PACKET-ZIP',
  'REV-P0-LF-ONBOARDING-STEP1-20260810',
  'EXEC-P0-4-LF-ONBOARDING-STEP1-20260810',
  'PACKET_ZIP',
  'GOOGLE_DRIVE',
  '1iWOdJzelzONvORRorZOon6FDUw7qBX1j',
  '1vnZ7UAph4wS4SvnKmAnY2uR4_pbA8Jc6',
  'https://drive.google.com/file/d/1iWOdJzelzONvORRorZOon6FDUw7qBX1j/view',
  'application/zip',
  1872814,
  '8f768e7a996881d82549698c6bd3bb415b2d9b6d655568a2bd3f02e85bd8438a',
  'a51ec8f64e6e0f86d5be2c569abb6f5cff7e5c35',
  'CONFIDENTIAL',
  false,
  true,
  true,
  jsonb_build_object(
    'drive_shared', false,
    'drive_owner_only_permission', true,
    'drive_reported_size', 1872814,
    'downloaded_size', 1872814,
    'downloaded_sha256', '8f768e7a996881d82549698c6bd3bb415b2d9b6d655568a2bd3f02e85bd8438a',
    'zip_integrity_test', 'PASS'
  ),
  'UNTIL_TERMINAL_REVIEW'
);
