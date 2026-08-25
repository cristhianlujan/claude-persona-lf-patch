-- INPUT_GOVERNANCE_AGENT: masking is not applicable to fields canonically classified
-- as non-sensitive and PII NONE. This changes evaluator semantics only; no field data is modified.
-- Fail closed if the expected predecessor source is not present exactly once.
do $migration$
declare
  v_def text;
  v_old text := $old$jsonb_build_object('check_code','MASKING','status',case when s.masking_rule is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.masking_rule')$old$;
  v_new text := $new$jsonb_build_object('check_code','MASKING','status',case when s.es_sensible is false and coalesce(s.pii_classification,'NONE')='NONE' then 'NOT_APPLICABLE' when s.masking_rule is not null then 'COMPLETE' else 'MISSING' end,'source_ref',case when s.es_sensible is false and coalesce(s.pii_classification,'NONE')='NONE' then 'lf_ops.campos.es_sensible+pii_classification' else 'lf_ops.campos.masking_rule' end,'rationale',case when s.es_sensible is false and coalesce(s.pii_classification,'NONE')='NONE' then 'Canonical field is non-sensitive and contains no PII; masking is not applicable.' else null end)$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_subject_depth_expected_v510'
    and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text';

  if v_def is null then
    raise exception 'INPUT_SUBJECT_DEPTH_V510_NOT_FOUND';
  end if;
  if length(v_def)-length(replace(v_def,v_old,'')) <> length(v_old) then
    raise exception 'INPUT_SUBJECT_DEPTH_MASKING_PREDECESSOR_NOT_EXACTLY_ONCE';
  end if;

  execute replace(v_def,v_old,v_new);
end;
$migration$;
