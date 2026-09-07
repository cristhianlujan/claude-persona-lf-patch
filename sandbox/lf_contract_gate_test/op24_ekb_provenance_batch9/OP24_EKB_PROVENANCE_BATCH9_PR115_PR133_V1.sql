-- OP24 EKB provenance reconstruction batch9 — explicit PR115/PR133 container provenance.
-- Candidate only. No durable write is authorized by this source.

with expected(codigo,expected_pr,evidence_sha256,source_ref) as (
  values
    ('AUD-020','133','53baccee78f22ef1974a6f3f9a2a56b6f20bc2954277fd23cfde9398c955d3f4','github://cristhianlujan/claude-persona-lf-patch/pull/133'),
    ('CLI-001','115','ccac33fee708baedeb103dce84ebe30113e480f770ae20014f0665d0432b406f','github://cristhianlujan/claude-persona-lf-patch/pull/115'),
    ('EKB-P0-016','133','f29635990f1da1c39e5928cfe6d8904f3363f61f6a8318ece36c3e091f6dd9ba','github://cristhianlujan/claude-persona-lf-patch/pull/133'),
    ('EKB-P0-019','133','1879f168d3d258c6be3d960ab5a6e6d462bbcb436ce125af16636476546f503f','github://cristhianlujan/claude-persona-lf-patch/pull/133'),
    ('PERF-001','133','a8ccaba24e36fa3a13859e1272e51a6e8de101871e4bb8298cbc6ff418bdfd63','github://cristhianlujan/claude-persona-lf-patch/pull/133'),
    ('RTE-007','133','e3d3d4b859c272fb661ff31f15d8dd159dce2200cdcc8eca1e1f182c11e9b292','github://cristhianlujan/claude-persona-lf-patch/pull/133')
), eligible as (
  select e.codigo,e.source_ref
  from expected e
  join transversal.error_knowledge k on k.codigo=e.codigo
  where k.source_ref is null
    and regexp_replace(coalesce(k.pr,''),'[^0-9]','','g')=e.expected_pr
    and encode(extensions.digest(convert_to(k.evidencia,'UTF8'),'sha256'),'hex')=e.evidence_sha256
), cardinality_guard as (
  select count(*)=6 as ok from eligible
)
update transversal.error_knowledge k
set source_ref=e.source_ref,
    updated_at=clock_timestamp()
from eligible e, cardinality_guard g
where g.ok and k.codigo=e.codigo and k.source_ref is null;

-- Caller must verify exactly 6 rows changed and perform independent post-write readback.
