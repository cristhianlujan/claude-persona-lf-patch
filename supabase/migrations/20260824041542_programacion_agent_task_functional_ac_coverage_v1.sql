create or replace function programacion.fn_guard_functional_version()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  v_payload jsonb;
  v_digest text;
  v_parent public.lf_functional_versions%rowtype;
  v_sup public.lf_functional_versions%rowtype;
  v_codes text[];
  v_missing_rule_codes text[] := '{}'::text[];
begin
  if tg_op='DELETE' then
    raise exception 'functional versions are append-only';
  end if;
  if tg_op='UPDATE' and old.status='SEALED' then
    raise exception 'sealed functional version % is immutable; create a superseding version',old.id;
  end if;
  if tg_op='INSERT' and new.status<>'DRAFT' then
    raise exception 'functional version must be born DRAFT';
  end if;
  if length(btrim(new.artifact_code))=0
     or length(btrim(new.objective))=0
     or length(btrim(new.created_by_execution_id))=0 then
    raise exception 'artifact_code, objective, created_by_execution_id required';
  end if;
  if jsonb_typeof(new.acceptance_criteria)<>'array' or jsonb_array_length(new.acceptance_criteria)=0 then
    raise exception 'acceptance_criteria must be non-empty array';
  end if;
  if jsonb_typeof(new.invariants)<>'array' or jsonb_array_length(new.invariants)=0 then
    raise exception 'invariants must be non-empty array';
  end if;
  if jsonb_typeof(new.negative_controls)<>'array' or jsonb_array_length(new.negative_controls)=0 then
    raise exception 'negative_controls must be non-empty array';
  end if;

  v_codes:=programacion.fn_p0_json_codes(new.acceptance_criteria,'AC');
  if cardinality(v_codes)<>jsonb_array_length(new.acceptance_criteria) then
    raise exception 'every acceptance criterion needs unique AC-* code';
  end if;
  v_codes:=programacion.fn_p0_json_codes(new.invariants,'INV');
  if cardinality(v_codes)<>jsonb_array_length(new.invariants) then
    raise exception 'every invariant needs unique INV-* code';
  end if;
  v_codes:=programacion.fn_p0_json_codes(new.negative_controls,'NEG');
  if cardinality(v_codes)<>jsonb_array_length(new.negative_controls) then
    raise exception 'every negative control needs unique NEG-* code';
  end if;
  if not programacion.fn_p0_array_is_canonical(new.source_rule_codes,false) then
    raise exception 'source_rule_codes must be sorted unique non-empty';
  end if;

  if new.artifact_type in ('STORY_SPEC','STORY') then
    if new.story_code is null or new.artifact_code<>new.story_code then
      raise exception '% requires artifact_code=story_code',new.artifact_type;
    end if;
  elsif new.story_code is not null then
    raise exception 'CANONICAL_SPEC must not carry story_code';
  end if;

  if new.artifact_type='STORY' then
    if new.parent_spec_version_id is null then
      raise exception 'STORY requires parent CANONICAL_SPEC version';
    end if;
    select * into v_parent from public.lf_functional_versions where id=new.parent_spec_version_id;
    if v_parent.id is null or v_parent.artifact_type<>'CANONICAL_SPEC' or v_parent.status<>'SEALED' then
      raise exception 'parent_spec_version_id must reference SEALED CANONICAL_SPEC';
    end if;
  elsif new.parent_spec_version_id is not null then
    raise exception '% must not carry parent_spec_version_id',new.artifact_type;
  end if;

  if new.supersedes_version_id is null then
    if new.version_no<>1 then
      raise exception 'initial functional version must be version 1';
    end if;
    if new.amendment_reason_code is not null or new.amendment_ref is not null then
      raise exception 'initial functional version cannot carry amendment metadata';
    end if;
  else
    select * into v_sup from public.lf_functional_versions where id=new.supersedes_version_id;
    if v_sup.id is null
       or v_sup.status<>'SEALED'
       or v_sup.artifact_code<>new.artifact_code
       or new.version_no<>v_sup.version_no+1 then
      raise exception 'supersedes_version_id must reference previous SEALED version of same artifact';
    end if;
    if length(btrim(coalesce(new.amendment_reason_code,'')))=0
       or length(btrim(coalesce(new.amendment_ref,'')))=0 then
      raise exception 'superseding functional version requires amendment_reason_code and amendment_ref';
    end if;
  end if;

  if new.status='DRAFT' then
    if new.content_sha256 is not null or new.sealed_at is not null then
      raise exception 'DRAFT functional version cannot carry seal';
    end if;
  else
    if tg_op<>'UPDATE' or old.status<>'DRAFT' then
      raise exception 'SEALED requires DRAFT -> SEALED transition';
    end if;

    if new.artifact_type in ('STORY_SPEC','STORY') then
      select coalesce(array_agg(rule_code order by rule_code),'{}'::text[])
        into v_missing_rule_codes
      from unnest(new.source_rule_codes) as src(rule_code)
      where not exists (
        select 1
        from jsonb_array_elements(new.acceptance_criteria) ac
        where ac->>'source_rule_code'=src.rule_code
           or (
             jsonb_typeof(ac->'source_rule_codes')='array'
             and exists (
               select 1
               from jsonb_array_elements_text(ac->'source_rule_codes') x(value)
               where x.value=src.rule_code
             )
           )
           or (
             jsonb_typeof(ac->'source_refs')='array'
             and exists (
               select 1
               from jsonb_array_elements_text(ac->'source_refs') x(value)
               where x.value=src.rule_code
             )
           )
      );
      if cardinality(v_missing_rule_codes)>0 then
        raise exception 'FUNCTIONAL_AC_SOURCE_RULE_COVERAGE_INCOMPLETE: %',v_missing_rule_codes;
      end if;
    end if;

    v_payload:=jsonb_build_object(
      'schema_version',1,
      'artifact_code',new.artifact_code,
      'artifact_type',new.artifact_type,
      'story_code',new.story_code,
      'parent_spec_version_id',new.parent_spec_version_id,
      'version_no',new.version_no,
      'objective',new.objective,
      'acceptance_criteria',new.acceptance_criteria,
      'invariants',new.invariants,
      'negative_controls',new.negative_controls,
      'source_rule_codes',to_jsonb(new.source_rule_codes),
      'supersedes_version_id',new.supersedes_version_id,
      'amendment_reason_code',new.amendment_reason_code,
      'amendment_ref',new.amendment_ref
    );
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload);
    if new.content_sha256 is not null and new.content_sha256<>v_digest then
      raise exception 'functional version digest mismatch';
    end if;
    new.content_sha256:=v_digest;
    new.sealed_at:=coalesce(new.sealed_at,now());
  end if;
  return new;
end;
$function$;
