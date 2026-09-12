-- ARC-011 root fix: move every active remediation producer/consumer to analysis revision 1.4 atomically.
do $block$
declare
  r record;
  v_def text;
  v_old text:='INPUT_GOV_REMEDIATION_1_3';
  v_new text:='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX';
  v_expected text[]:=array[
    'fn_input_governance_bootstrap_materialize_v2',
    'fn_input_governance_materialize_gap_proposals_v1',
    'fn_input_governance_recurate_v2',
    'fn_input_governance_validate_gap_proposals_v1',
    'fn_input_governance_validate_v2',
    'fn_input_governance_validator_validate_v1'
  ];
  v_count int:=0;
begin
  for r in
    select p.oid,p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion'
      and p.proname=any(v_expected)
      and pg_get_functiondef(p.oid) like '%'||v_old||'%'
    order by p.proname
  loop
    v_def:=replace(pg_get_functiondef(r.oid),v_old,v_new);
    execute v_def;
    v_count:=v_count+1;
  end loop;

  if v_count<>cardinality(v_expected) then
    raise exception 'INPUT_GOV_ANALYSIS_REVISION_ATOMIC_COUNT_MISMATCH expected=% actual=%',cardinality(v_expected),v_count;
  end if;

  if exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion'
      and p.proname=any(v_expected)
      and pg_get_functiondef(p.oid) like '%'||v_old||'%'
  ) then
    raise exception 'INPUT_GOV_ANALYSIS_REVISION_OLD_LITERAL_REMAINS';
  end if;

  if exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion'
      and p.proname=any(v_expected)
      and pg_get_functiondef(p.oid) not like '%'||v_new||'%'
  ) then
    raise exception 'INPUT_GOV_ANALYSIS_REVISION_NEW_LITERAL_MISSING';
  end if;
end;
$block$;