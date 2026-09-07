-- OP24 EKB provenance reconstruction batch4 — candidate only.
-- Exact self-evidence only; no sibling/lote inheritance.
-- No durable write is authorized by this source before governed approval.

with expected(codigo, marker, source_ref) as (
  values
    (
      'AUD-012',
      'a6bf03ac1660f09bf0e2d09b215b0e7f8c1fe6d2',
      'github://cristhianlujan/claude-persona-lf-patch/commit/a6bf03ac1660f09bf0e2d09b215b0e7f8c1fe6d2'
    ),
    (
      'EKB-P0-006',
      '84f8234440fe5f2dcfd163fa2b99b1318b2aa776',
      'github://cristhianlujan/claude-persona-lf-patch/commit/84f8234440fe5f2dcfd163fa2b99b1318b2aa776'
    ),
    (
      'EKB-PR111-003',
      'baa06972161de32a8c334c4f2e686a4ff74a241afad5c64edc2cbb23066c2a72',
      'github://cristhianlujan/claude-persona-lf-patch/blob/ded3426ca1ea821e0b0aaa84b3ae35cdb8a2c515/sandbox/lf_contract_gate_test/story_creator_visual_screen_reading_architecture/release-v1.2/STORY_CREATOR_VISUAL_SCREEN_READING_RFC8785_CANONICALIZER_v1.2.mjs'
    )
), eligible as (
  select e.codigo,e.source_ref
  from expected e
  join transversal.error_knowledge k on k.codigo=e.codigo
  where k.source_ref is null
    and position(e.marker in coalesce(k.evidencia,'')) > 0
), cardinality_guard as (
  select count(*)=3 as ok from eligible
)
update transversal.error_knowledge k
set source_ref=e.source_ref,
    updated_at=clock_timestamp()
from eligible e,cardinality_guard g
where g.ok
  and k.codigo=e.codigo
  and k.source_ref is null;

-- Caller must verify 3/3 and perform independent post-rollback readback.
