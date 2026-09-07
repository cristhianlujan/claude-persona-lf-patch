-- OP24 EKB provenance reconstruction batch5 — PR93 container-level provenance.
-- Candidate only. No durable write is authorized by this source.
-- Each row is guarded by codigo + structured pr=93 + exact evidence SHA-256.

with expected(codigo,evidence_sha256,source_ref) as (
  values
    ('DEV-001','401babb93a55a890b57532091aa8b112a4bab5f3788b35d16275481fa0e8153a','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('OBS-001','d2dfe2e7106598566523fe592b0f368c1a64999d16926a7d1d6bb235794e1ed1','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('RTE-001','b9ef3af870753748e4a508b6f589b34c65fca5f37e228690dd67548943b74b06','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('RTE-002','99dc38988f6bc0f10bf6a5613eff6a8aba5e0dfb6ba1d41d96e3f7881b6ee35f','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('RTE-004','db840a85f4af3cbd186ace6c580ae1aeb27693e31e30381faf6eb29abef652c5','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SEC-002','248d26970f870a5157c407bad47e8671395c2925eadf0e3492735a94868817a3','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SEC-006','689dfed6dcff5072797d4aedf8f909a7b5df3952bc852723a5a7da9a856631e7','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SQL-006','e5c4e7460d2b992c12d7b09bb7e2694fe7c4826c6d1e26bfe8cb9bfc76e31dcb','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SRC-003','a8d2cb698a4925110d839fcfdfae1fc431a8d847561040e74ee258c9806d0004','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('TOOL-001','f7a07b59a36da5e8a1bf0abd7b5eeb88f6a60e763d7d6495a03732b457c1cd0f','github://cristhianlujan/claude-persona-lf-patch/pull/93')
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
