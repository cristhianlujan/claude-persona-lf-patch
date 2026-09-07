-- OP24 EKB provenance reconstruction batch10 — final explicit simple PR containers.
-- Candidate only. No durable write is authorized by this source.

with expected(codigo,expected_pr,evidence_sha256,source_ref) as (
  values
    ('EKB-P0-015','132','c13d561325be9f9bd2e7c5fb4ffac059ebf218906ee028b5145e4e030129b1f6','github://cristhianlujan/claude-persona-lf-patch/pull/132'),
    ('EKB-PR111-004','111','c7ec7e12e56a4d69f5c542ae33cce55456945435a43c60837b500a32ad98eb94','github://cristhianlujan/claude-persona-lf-patch/pull/111')
), eligible as (
  select e.codigo,e.source_ref
  from expected e
  join transversal.error_knowledge k on k.codigo=e.codigo
  where k.source_ref is null
    and regexp_replace(coalesce(k.pr,''),'[^0-9]','','g')=e.expected_pr
    and encode(extensions.digest(convert_to(k.evidencia,'UTF8'),'sha256'),'hex')=e.evidence_sha256
), cardinality_guard as (
  select count(*)=2 as ok from eligible
)
update transversal.error_knowledge k
set source_ref=e.source_ref,
    updated_at=clock_timestamp()
from eligible e, cardinality_guard g
where g.ok and k.codigo=e.codigo and k.source_ref is null;

-- Caller must verify exactly 2 rows changed and perform independent post-write readback.
