create table if not exists private.lf_p0_evidence_upload_chunks_v1 (
  upload_id uuid not null,
  chunk_no integer not null check (chunk_no >= 0),
  chunk_base64 text not null check (length(chunk_base64) > 0),
  created_at timestamptz not null default now(),
  primary key (upload_id, chunk_no)
);
revoke all on private.lf_p0_evidence_upload_chunks_v1 from public, anon, authenticated;
grant select, insert, delete on private.lf_p0_evidence_upload_chunks_v1 to service_role;
comment on table private.lf_p0_evidence_upload_chunks_v1 is 'Private transient staging for chunked base64 evidence uploads; rows are deleted after cryptographic finalize.';
