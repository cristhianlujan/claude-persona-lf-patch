-- OP24 EKB provenance reconstruction batch3 — candidate only.
-- No durable write is authorized by this source. Intended for rollback-only verification first.

with expected(codigo, expected_marker, source_ref) as (
  values
    ('EKB-P0-001','PR115@f40d8063','github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda'),
    ('EKB-P0-005','PR115@f40d8063','github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda'),
    ('EKB-P0-007','PR115@f40d8063','github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda'),
    ('EKB-P0-008','PR115@f40d8063','github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda'),
    ('EKB-P0-012','PR115@f40d8063','github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda')
), eligible as (
  select e.codigo,e.source_ref
  from expected e
  join transversal.error_knowledge k on k.codigo=e.codigo
  where k.source_ref is null
    and position(e.expected_marker in coalesce(k.evidencia,'')) > 0
), cardinality_guard as (
  select case when count(*)=5 then true else false end as ok from eligible
)
update transversal.error_knowledge k
set source_ref=e.source_ref,
    updated_at=clock_timestamp()
from eligible e, cardinality_guard g
where g.ok
  and k.codigo=e.codigo
  and k.source_ref is null;

-- Caller must verify exactly 5 rows changed and independently read back all targets.
