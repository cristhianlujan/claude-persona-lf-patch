-- OP24 EKB provenance reconstruction V1 — candidate DML only.
-- Source-first. Must be executed only through governed DB update flow and verified independently.
-- This source backfills source_ref for five historical EKB rows whose own evidence names
-- PR115@f40d8063 and whose exact commit has been independently resolved.
-- No new learning, no lifecycle promotion, no runtime/production authorization.

do $op24$
declare
  v_expected text[] := array[
    'EKB-P0-001',
    'EKB-P0-005',
    'EKB-P0-007',
    'EKB-P0-008',
    'EKB-P0-012'
  ];
  v_source_ref text := 'github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda';
  v_pre integer;
  v_updated integer;
begin
  select count(*) into v_pre
  from transversal.error_knowledge e
  where e.codigo = any(v_expected)
    and e.source_ref is null
    and e.evidencia like '%PR115@f40d8063%';

  if v_pre <> 5 then
    raise exception 'OP24_EKB_PROVENANCE_PRECONDITION_MISMATCH expected=5 observed=%', v_pre;
  end if;

  if exists (
    select 1
    from transversal.error_knowledge e
    where e.codigo = any(v_expected)
      and (
        e.source_ref is not null
        or e.evidencia not like '%PR115@f40d8063%'
      )
  ) then
    raise exception 'OP24_EKB_PROVENANCE_TARGET_DRIFT';
  end if;

  update transversal.error_knowledge e
     set source_ref = v_source_ref,
         updated_at = clock_timestamp()
   where e.codigo = any(v_expected)
     and e.source_ref is null
     and e.evidencia like '%PR115@f40d8063%';

  get diagnostics v_updated = row_count;
  if v_updated <> 5 then
    raise exception 'OP24_EKB_PROVENANCE_UPDATE_COUNT_MISMATCH expected=5 observed=%', v_updated;
  end if;

  if exists (
    select 1
    from transversal.error_knowledge e
    where e.codigo = any(v_expected)
      and e.source_ref is distinct from v_source_ref
  ) then
    raise exception 'OP24_EKB_PROVENANCE_POSTCONDITION_FAILED';
  end if;
end
$op24$;
