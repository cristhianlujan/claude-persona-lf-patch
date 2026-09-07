-- OP24 EKB provenance reconstruction batch6 — PR93 container-level provenance.
-- Candidate only. No durable write is authorized by this source.
-- Each row is guarded by codigo + structured pr=93 + exact evidence SHA-256.

with expected(codigo,evidence_sha256,source_ref) as (
  values
    ('AUD-010','0e33c73bd77d83fa2e7245bc6344c25b8cfd2f36f81fbb8260b24ea5a82c8873','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('CFG-001','72d6208a99f0ae4378efbcf8586dcd30f7d392a65c6e5d41f3908aa36c002420','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('CI-001','e02b5e49fae515ea048cd67690dc806b304868d5d2513310cc1cd05140473444','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('GOV-002','cd44af2ebd1c5815f1c191fcc71d2370fc76783d4409fdde577a85f76bdfe625','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('GOV-003','c04f4a1cfb04a9dbc3018856ebf2ae8654356ad7165ed89e278a69d5c19a492d','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SEC-001','53efa88e4c03cd5c9959830e4c5ca56c9bb97c3e9d9f0350df7ec1ef90e652fc','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SEC-003','dfe75647a116bcb9109ae7064a294a7e4b951824804eaab53c17f5760f3f1e1b','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SQL-003','0c38ba95e372af3369ab0f86afe522421b9be29f87bf42549a0e7263e343e5b1','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SQL-014','87ba7c598600f98955fcde3dec99529e549106ded5fb3c2830a9d3b7fcadd362','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SRC-002','24543e08df027fe1f0af0ac4483d97622a3e68e1a9dac8e68ef513d737fdf384','github://cristhianlujan/claude-persona-lf-patch/pull/93')
), eligible as (
  select e.codigo,e.source_ref
  from expected e
  join transversal.error_knowledge k on k.codigo=e.codigo
  where k.source_ref is null
    and regexp_replace(coalesce(k.pr,''),'[^0-9]','','g')='93'
    and encode(extensions.digest(convert_to(k.evidencia,'UTF8'),'sha256'),'hex')=e.evidence_sha256
), cardinality_guard as (
  select count(*)=10 as ok from eligible
)
update transversal.error_knowledge k
set source_ref=e.source_ref,
    updated_at=clock_timestamp()
from eligible e, cardinality_guard g
where g.ok
  and k.codigo=e.codigo
  and k.source_ref is null;

-- Caller must verify exactly 10 rows changed and perform independent post-write readback.
