-- OP24 EKB provenance reconstruction batch7 — PR93 container-level provenance.
-- Candidate only. No durable write is authorized by this source.
-- Each row is guarded by codigo + structured pr=93 + exact evidence SHA-256.

with expected(codigo,evidence_sha256,source_ref) as (
  values
    ('AUD-005','8855e2f4bbf53a16679a2491d5a0a9eca5c7245fefa2ecfdf59d2bf062b91cc9','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('AUD-006','2f281725150c420d1e20fb0505118d75da644f4ce59b5b95f493f0d8ab7dbd77','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('AUD-007','39e74bf6212bbbebb430f418cdec535f6d7cec6c4c4e623404d5542ef82b0d5e','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('CFG-003','6f4d85bd7def37889b5fa295a8c942c2c839153fcd273e98027f3c5f8f5cfbda','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('CI-002','ab668719aef93ce61630fd6d1dee3014ab65f99fd7f9228e65216e110414d97b','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SEC-004','d2f2f0ae6496e6b7e5e6339488d02567fd51be18007bda7112cd034cd3385aa2','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SEC-005','3cee3d9171ff8ca70f2317e11a75b19ccf4ba5b9b8fc65c2aef66bf8a25c6f2b','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SQL-001','de2b6788a083a2d7948d4122b9d87dcbb3582af1a2304e591ab622d2f1d0b53f','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SQL-005','0caa006073bc40432ca660264aeaf735225888f2f7adb13e41d9a96152c4d128','github://cristhianlujan/claude-persona-lf-patch/pull/93'),
    ('SQL-012','185d3d3ea76296f1f974306a326e61dacfee3bb67580307de61ca3676ee33a0e','github://cristhianlujan/claude-persona-lf-patch/pull/93')
), eligible as (
  select e.codigo,e.source_ref
  from expected e join transversal.error_knowledge k on k.codigo=e.codigo
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
