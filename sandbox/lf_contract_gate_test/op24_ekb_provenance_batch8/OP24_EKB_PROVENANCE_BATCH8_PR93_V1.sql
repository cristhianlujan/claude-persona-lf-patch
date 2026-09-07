-- OP24 EKB provenance reconstruction batch8 — final simple PR93 episodes.
-- Candidate only. No durable write is authorized by this source.

with expected(codigo,evidence_sha256,source_ref) as (
  values
    ('GOV-008','7e2c633f74d0403acabe8fac9ed6bcbf5f92c74421c19f22879e7b9fcafbe8ff','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('RTE-006','8885791858521c9046b0ae62e40429b0aa783014d34199e50a314ab5f8caf2df','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('UX-001','3ecbacd2fbc7dc3b4a1bccb6bbe3f7dfc1166e5242aa3f1ca2f27f192f4bee5a','github://cristhianlujan/claude-persona-lf-patch/pull/93')
), eligible as (
  select e.codigo,e.source_ref
  from expected e join transversal.error_knowledge k on k.codigo=e.codigo
  where k.source_ref is null
    and regexp_replace(coalesce(k.pr,''),'[^0-9]','','g')='93'
    and encode(extensions.digest(convert_to(k.evidencia,'UTF8'),'sha256'),'hex')=e.evidence_sha256
), cardinality_guard as (
  select count(*)=3 as ok from eligible
)
update transversal.error_knowledge k
set source_ref=e.source_ref,
    updated_at=clock_timestamp()
from eligible e, cardinality_guard g
where g.ok and k.codigo=e.codigo and k.source_ref is null;

-- Caller must verify exactly 3 rows changed and perform independent post-write readback.
