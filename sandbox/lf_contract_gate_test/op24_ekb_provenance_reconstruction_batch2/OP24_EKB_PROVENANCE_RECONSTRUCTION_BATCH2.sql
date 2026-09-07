-- OP24 EKB provenance reconstruction batch 2 — candidate source only.
-- Must run only through governed EKB_PROVENANCE_REPAIR_LF after approval.
-- No learning-state, content, severity, lifecycle or authority mutation.

do $preflight$
declare
  v_count integer;
  v_bad integer;
begin
  select count(*) into v_count
  from transversal.error_knowledge
  where codigo in ('CI-004','EKB-P0-013','EKB-PR111-001','EKB-PR111-002','EKB-PR111-007');
  if v_count <> 5 then
    raise exception 'OP24_BATCH2_TARGET_CARDINALITY:%', v_count;
  end if;

  select count(*) into v_bad
  from transversal.error_knowledge
  where codigo in ('CI-004','EKB-P0-013','EKB-PR111-001','EKB-PR111-002','EKB-PR111-007')
    and source_ref is not null;
  if v_bad <> 0 then
    raise exception 'OP24_BATCH2_SOURCE_REF_ALREADY_SET:%', v_bad;
  end if;

  select count(*) into v_bad
  from transversal.error_knowledge
  where (codigo='CI-004' and position('4b64f2b46b27f4377d1e7133988ae79b9ac5ff5d' in coalesce(evidencia,''))=0)
     or (codigo='EKB-P0-013' and position('26611cad05c2986b367ed55d3f38a395d4a3cc0c' in coalesce(evidencia,''))=0)
     or (codigo='EKB-PR111-001' and position('a6bf03ac1660f09bf0e2d09b215b0e7f8c1fe6d2' in coalesce(evidencia,''))=0)
     or (codigo in ('EKB-PR111-002','EKB-PR111-007') and position('d8b2b9c8fa49cf4fcdcbb054d341fff1e2e8c730' in coalesce(evidencia,''))=0);
  if v_bad <> 0 then
    raise exception 'OP24_BATCH2_ROW_EVIDENCE_DRIFT:%', v_bad;
  end if;
end
$preflight$;

update transversal.error_knowledge
set source_ref = case codigo
  when 'CI-004' then 'github://cristhianlujan/claude-persona-lf-patch/commit/4b64f2b46b27f4377d1e7133988ae79b9ac5ff5d'
  when 'EKB-P0-013' then 'github://cristhianlujan/claude-persona-lf-patch/commit/26611cad05c2986b367ed55d3f38a395d4a3cc0c'
  when 'EKB-PR111-001' then 'github://cristhianlujan/claude-persona-lf-patch/commit/a6bf03ac1660f09bf0e2d09b215b0e7f8c1fe6d2'
  when 'EKB-PR111-002' then 'github://cristhianlujan/claude-persona-lf-patch/commit/d8b2b9c8fa49cf4fcdcbb054d341fff1e2e8c730'
  when 'EKB-PR111-007' then 'github://cristhianlujan/claude-persona-lf-patch/commit/d8b2b9c8fa49cf4fcdcbb054d341fff1e2e8c730'
  else source_ref
end,
updated_at = clock_timestamp()
where codigo in ('CI-004','EKB-P0-013','EKB-PR111-001','EKB-PR111-002','EKB-PR111-007')
  and source_ref is null;

do $post$
declare
  v_ok integer;
begin
  select count(*) into v_ok
  from transversal.error_knowledge
  where (codigo='CI-004' and source_ref='github://cristhianlujan/claude-persona-lf-patch/commit/4b64f2b46b27f4377d1e7133988ae79b9ac5ff5d')
     or (codigo='EKB-P0-013' and source_ref='github://cristhianlujan/claude-persona-lf-patch/commit/26611cad05c2986b367ed55d3f38a395d4a3cc0c')
     or (codigo='EKB-PR111-001' and source_ref='github://cristhianlujan/claude-persona-lf-patch/commit/a6bf03ac1660f09bf0e2d09b215b0e7f8c1fe6d2')
     or (codigo in ('EKB-PR111-002','EKB-PR111-007') and source_ref='github://cristhianlujan/claude-persona-lf-patch/commit/d8b2b9c8fa49cf4fcdcbb054d341fff1e2e8c730');
  if v_ok <> 5 then
    raise exception 'OP24_BATCH2_POSTCONDITION:%', v_ok;
  end if;
end
$post$;
