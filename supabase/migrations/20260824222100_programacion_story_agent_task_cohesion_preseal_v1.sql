-- Story Creator: pre-SEALED functional cohesion control.
-- Reuses the existing functional-version contract and gate framework.
-- No new table, agent, orchestrator, execution pack, or numeric complexity threshold.

insert into programacion.gates(
  version_id, gate_codigo, fase, tipo, nombre, descripcion,
  ejecutor_componente_id, modo_verificacion, reintentos_max,
  bloqueante, evidencia_requerida, configuracion, estado
)
select
  v.id,
  'G_STORY_COHESION_PRESEAL',
  'preparation',
  'hard',
  'Story functional cohesion before seal',
  'Fail-closed pre-SEALED control. Story cohesion is derived from functional-unit annotations on the existing AC/INV/NEG contract; no universal AC/INV/NEG count threshold is used.',
  null,
  'deterministic',
  0,
  true,
  true,
  jsonb_build_object(
    'method','SEMANTIC_FUNCTIONAL_UNIT_CLUSTERING_V1',
    'derived_from',jsonb_build_array(
      'acceptance_criteria.functional_unit_code',
      'invariants.functional_unit_code',
      'negative_controls.functional_unit_code'
    ),
    'seal_allowed_status','COHESIVE',
    'review_status','REVIEW_SPLIT',
    'missing_evidence_status','INSUFFICIENT_EVIDENCE',
    'requires_complete_annotation',true,
    'requires_acceptance_per_unit',true,
    'no_numeric_thresholds',true
  ),
  'defined'
from programacion.versiones_agente v
where v.version_codigo='v0.9-roadmap-complete'
  and not exists (
    select 1
    from programacion.gates g
    where g.version_id=v.id
      and g.gate_codigo='G_STORY_COHESION_PRESEAL'
  );

create or replace function programacion.fn_story_cohesion_assessment_v1(
  p_acceptance_criteria jsonb,
  p_invariants jsonb,
  p_negative_controls jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_missing_count integer:=0;
  v_invalid_code_count integer:=0;
  v_unit_count integer:=0;
  v_units_without_acceptance integer:=0;
  v_units jsonb:='[]'::jsonb;
  v_status text;
begin
  if jsonb_typeof(p_acceptance_criteria) is distinct from 'array'
     or jsonb_typeof(p_invariants) is distinct from 'array'
     or jsonb_typeof(p_negative_controls) is distinct from 'array'
     or jsonb_array_length(p_acceptance_criteria)=0
     or jsonb_array_length(p_invariants)=0
     or jsonb_array_length(p_negative_controls)=0
  then
    return jsonb_build_object(
      'schema_version',1,
      'method','SEMANTIC_FUNCTIONAL_UNIT_CLUSTERING_V1',
      'status','INSUFFICIENT_EVIDENCE',
      'reason','AC_INV_NEG_ARRAYS_REQUIRED',
      'unit_count',0,
      'missing_annotation_count',0,
      'invalid_unit_code_count',0,
      'units_without_acceptance_count',0,
      'thresholds_used',false,
      'units','[]'::jsonb
    );
  end if;

  with controls as (
    select 'AC'::text as kind, e as item from jsonb_array_elements(p_acceptance_criteria) e
    union all
    select 'INV'::text as kind, e as item from jsonb_array_elements(p_invariants) e
    union all
    select 'NEG'::text as kind, e as item from jsonb_array_elements(p_negative_controls) e
  ), normalized as (
    select
      kind,
      item,
      nullif(btrim(item->>'functional_unit_code'),'') as unit_code
    from controls
  )
  select
    count(*) filter (where unit_code is null),
    count(*) filter (where unit_code is not null and unit_code !~ '^FU-[A-Z0-9][A-Z0-9_-]*$'),
    count(distinct unit_code) filter (where unit_code is not null)
  into v_missing_count,v_invalid_code_count,v_unit_count
  from normalized;

  with controls as (
    select 'AC'::text as kind, e as item from jsonb_array_elements(p_acceptance_criteria) e
    union all
    select 'INV'::text as kind, e as item from jsonb_array_elements(p_invariants) e
    union all
    select 'NEG'::text as kind, e as item from jsonb_array_elements(p_negative_controls) e
  ), normalized as (
    select
      kind,
      item,
      nullif(btrim(item->>'functional_unit_code'),'') as unit_code
    from controls
  ), unit_rollup as (
    select
      unit_code,
      count(*) filter (where kind='AC') as acceptance_count,
      count(*) filter (where kind='INV') as invariant_count,
      count(*) filter (where kind='NEG') as negative_count,
      coalesce(
        jsonb_agg(item->>'code' order by item->>'code') filter (where kind='AC'),
        '[]'::jsonb
      ) as acceptance_refs,
      coalesce(
        jsonb_agg(item->>'code' order by item->>'code') filter (where kind='INV'),
        '[]'::jsonb
      ) as invariant_refs,
      coalesce(
        jsonb_agg(item->>'code' order by item->>'code') filter (where kind='NEG'),
        '[]'::jsonb
      ) as negative_refs
    from normalized
    where unit_code is not null
    group by unit_code
  )
  select
    count(*) filter (where acceptance_count=0),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'functional_unit_code',unit_code,
          'acceptance_count',acceptance_count,
          'invariant_count',invariant_count,
          'negative_count',negative_count,
          'acceptance_refs',acceptance_refs,
          'invariant_refs',invariant_refs,
          'negative_refs',negative_refs,
          'independently_testable_candidate',acceptance_count>0
        )
        order by unit_code
      ),
      '[]'::jsonb
    )
  into v_units_without_acceptance,v_units
  from unit_rollup;

  if v_missing_count>0 or v_invalid_code_count>0 or v_unit_count=0 or v_units_without_acceptance>0 then
    v_status:='INSUFFICIENT_EVIDENCE';
  elsif v_unit_count=1 then
    v_status:='COHESIVE';
  else
    v_status:='REVIEW_SPLIT';
  end if;

  return jsonb_build_object(
    'schema_version',1,
    'method','SEMANTIC_FUNCTIONAL_UNIT_CLUSTERING_V1',
    'status',v_status,
    'unit_count',v_unit_count,
    'missing_annotation_count',v_missing_count,
    'invalid_unit_code_count',v_invalid_code_count,
    'units_without_acceptance_count',v_units_without_acceptance,
    'thresholds_used',false,
    'units',v_units
  );
end;
$function$;

create or replace function programacion.fn_story_cohesion_assessment_v1(
  p_functional_version_id bigint
)
returns jsonb
language sql
stable
set search_path to 'pg_catalog','public','programacion'
as $function$
  select case
    when f.id is null then null
    else programacion.fn_story_cohesion_assessment_v1(
      f.acceptance_criteria,
      f.invariants,
      f.negative_controls
    ) || jsonb_build_object(
      'functional_version_id',f.id,
      'artifact_code',f.artifact_code,
      'artifact_type',f.artifact_type,
      'story_code',f.story_code,
      'functional_status',f.status
    )
  end
  from (select p_functional_version_id as requested_id) q
  left join public.lf_functional_versions f on f.id=q.requested_id;
$function$;

create or replace function programacion.fn_guard_story_cohesion_preseal_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  v_assessment jsonb;
  v_gate_cfg jsonb;
begin
  if tg_op='UPDATE'
     and old.status='DRAFT'
     and new.status='SEALED'
     and new.artifact_type in ('STORY_SPEC','STORY')
  then
    select g.configuracion
      into v_gate_cfg
    from programacion.gates g
    join programacion.versiones_agente v on v.id=g.version_id
    where v.version_codigo='v0.9-roadmap-complete'
      and g.gate_codigo='G_STORY_COHESION_PRESEAL'
      and g.estado in ('defined','active')
    order by g.id desc
    limit 1;

    if v_gate_cfg is null
       or coalesce((v_gate_cfg->>'no_numeric_thresholds')::boolean,false) is not true
       or v_gate_cfg->>'seal_allowed_status'<>'COHESIVE'
    then
      raise exception 'STORY_COHESION_POLICY_MISSING';
    end if;

    v_assessment:=programacion.fn_story_cohesion_assessment_v1(
      new.acceptance_criteria,
      new.invariants,
      new.negative_controls
    );

    if v_assessment->>'status'='REVIEW_SPLIT' then
      raise exception 'STORY_COHESION_REVIEW_SPLIT_REQUIRED: %',v_assessment;
    elsif v_assessment->>'status'<>'COHESIVE' then
      raise exception 'STORY_COHESION_EVIDENCE_INCOMPLETE: %',v_assessment;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_lf_functional_versions_05_story_cohesion on public.lf_functional_versions;
create trigger trg_lf_functional_versions_05_story_cohesion
before update of status on public.lf_functional_versions
for each row
execute function programacion.fn_guard_story_cohesion_preseal_v1();

-- Self-tests: count alone must never force a split; multiple functional units must.
do $selftest$
declare
  v_ac jsonb;
  v_inv jsonb;
  v_neg jsonb;
  v_result jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'code','AC-T-'||lpad(g::text,3,'0'),
    'functional_unit_code','FU-ONE'
  ) order by g)
  into v_ac
  from generate_series(1,15) g;

  select jsonb_agg(jsonb_build_object(
    'code','INV-T-'||lpad(g::text,3,'0'),
    'functional_unit_code','FU-ONE'
  ) order by g)
  into v_inv
  from generate_series(1,20) g;

  select jsonb_agg(jsonb_build_object(
    'code','NEG-T-'||lpad(g::text,3,'0'),
    'functional_unit_code','FU-ONE'
  ) order by g)
  into v_neg
  from generate_series(1,20) g;

  v_result:=programacion.fn_story_cohesion_assessment_v1(v_ac,v_inv,v_neg);
  if v_result->>'status'<>'COHESIVE' or (v_result->>'unit_count')::integer<>1 then
    raise exception 'STORY_COHESION_SELFTEST_LARGE_COHESIVE_FAILED: %',v_result;
  end if;

  v_ac:=jsonb_build_array(
    jsonb_build_object('code','AC-A','functional_unit_code','FU-A'),
    jsonb_build_object('code','AC-B','functional_unit_code','FU-B')
  );
  v_inv:=jsonb_build_array(
    jsonb_build_object('code','INV-A','functional_unit_code','FU-A'),
    jsonb_build_object('code','INV-B','functional_unit_code','FU-B')
  );
  v_neg:=jsonb_build_array(
    jsonb_build_object('code','NEG-A','functional_unit_code','FU-A'),
    jsonb_build_object('code','NEG-B','functional_unit_code','FU-B')
  );

  v_result:=programacion.fn_story_cohesion_assessment_v1(v_ac,v_inv,v_neg);
  if v_result->>'status'<>'REVIEW_SPLIT' or (v_result->>'unit_count')::integer<>2 then
    raise exception 'STORY_COHESION_SELFTEST_SPLIT_FAILED: %',v_result;
  end if;

  v_ac:=jsonb_build_array(
    jsonb_build_object('code','AC-MISSING')
  );
  v_inv:=jsonb_build_array(
    jsonb_build_object('code','INV-MISSING','functional_unit_code','FU-ONE')
  );
  v_neg:=jsonb_build_array(
    jsonb_build_object('code','NEG-MISSING','functional_unit_code','FU-ONE')
  );

  v_result:=programacion.fn_story_cohesion_assessment_v1(v_ac,v_inv,v_neg);
  if v_result->>'status'<>'INSUFFICIENT_EVIDENCE' then
    raise exception 'STORY_COHESION_SELFTEST_MISSING_EVIDENCE_FAILED: %',v_result;
  end if;
end;
$selftest$;
