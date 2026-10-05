-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.3 / PAULO-050
-- Reuses M2.8 fn_input_deterministic_assess; no parallel digest engine.

begin;

alter table programacion.input_family_assessments
  add column deterministic_sha256 text
  check (deterministic_sha256 is null or deterministic_sha256 ~ '^[0-9a-f]{64}$');

comment on column programacion.input_family_assessments.deterministic_sha256 is
'M6.3 result_sha256 emitted by fn_input_deterministic_assess for the persisted run/family deterministic subject.';

create or replace function programacion.fn_input_family_deterministic_assess_v1(
  p_run_id bigint,
  p_family_code text,
  p_assessment jsonb
) returns jsonb
language plpgsql volatile security definer
set search_path = pg_catalog, programacion
as $fn$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_family text := upper(nullif(btrim(p_family_code),''));
  v_graph jsonb;
  v_contract jsonb;
  v_subject jsonb;
  v_result jsonb;
begin
  if p_run_id is null or v_family is null or jsonb_typeof(p_assessment) <> 'object' then
    raise exception 'M63_DETERMINISTIC_DIGEST_INPUT_REQUIRED';
  end if;

  select r.pantalla_id, r.version_id
    into v_pantalla_id, v_version_id
  from programacion.input_readiness_runs r
  where r.id = p_run_id;

  if v_pantalla_id is null or v_version_id is null then
    raise exception 'M63_DETERMINISTIC_DIGEST_RUN_NOT_FOUND:%', p_run_id;
  end if;

  select c.especificacion
    into v_contract
  from programacion.contratos c
  where c.version_id = v_version_id
    and c.contrato_codigo = 'INPUT_READINESS_CONTRACT'
    and c.estado = 'defined'
    and c.fail_closed
  order by c.id desc
  limit 1;

  if v_contract is null then
    raise exception 'M63_DETERMINISTIC_DIGEST_CONTRACT_NOT_FOUND:%', v_version_id;
  end if;

  v_graph := programacion.fn_input_screen_canonical_graph(v_pantalla_id, v_version_id);

  v_subject := jsonb_build_object(
    'pantalla_id', v_pantalla_id,
    'version_id', v_version_id,
    'source_class', 'DETERMINISTIC',
    'severity', p_assessment->>'severity',
    'applicability', p_assessment->>'applicability',
    'coverage_status', p_assessment->>'coverage_status',
    'well_defined_status', p_assessment->>'well_defined_status',
    'story_ready_status', p_assessment->>'story_ready_status',
    'implementation_ready_status', p_assessment->>'implementation_ready_status',
    'qa_ready_status', p_assessment->>'qa_ready_status',
    'production_ready_status', p_assessment->>'production_ready_status',
    'source_refs', coalesce(p_assessment->'source_refs','[]'::jsonb),
    'rationale', p_assessment->>'rationale',
    'blockers', coalesce(p_assessment->'blockers','[]'::jsonb),
    'negative_requirements', coalesce(p_assessment->'negative_requirements','[]'::jsonb),
    'test_obligations', coalesce(p_assessment->'test_obligations','[]'::jsonb),
    'freshness', coalesce(p_assessment->'freshness','{}'::jsonb),
    'curator_evidence', coalesce(p_assessment->'curator_evidence','{}'::jsonb),
    'curator_sha256', p_assessment->>'curator_sha256',
    'subject_coverage', coalesce(p_assessment->'subject_coverage','[]'::jsonb),
    'threat_coverage', coalesce(p_assessment->'threat_coverage','[]'::jsonb),
    'semantic_depth_sha256', p_assessment->>'semantic_depth_sha256'
  );

  v_result := programacion.fn_input_deterministic_assess(v_subject, v_family, v_graph, v_contract);

  if coalesce(v_result->>'result_sha256','') !~ '^[0-9a-f]{64}$' then
    raise exception 'M63_DETERMINISTIC_DIGEST_INVALID_RESULT:%:%', p_run_id, v_family;
  end if;

  return v_result;
end;
$fn$;

revoke all on function programacion.fn_input_family_deterministic_assess_v1(bigint,text,jsonb) from public;
grant execute on function programacion.fn_input_family_deterministic_assess_v1(bigint,text,jsonb) to postgres;

create or replace function programacion.fn_guard_input_family_deterministic_digest_insert_v1()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, programacion
as $fn$
declare v_result jsonb;
begin
  v_result := programacion.fn_input_family_deterministic_assess_v1(new.run_id,new.family_code,to_jsonb(new));
  new.deterministic_sha256 := v_result->>'result_sha256';
  if coalesce(new.deterministic_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'M63_DETERMINISTIC_DIGEST_INSERT_INVALID:%:%', new.run_id, new.family_code;
  end if;
  return new;
end;
$fn$;

revoke all on function programacion.fn_guard_input_family_deterministic_digest_insert_v1() from public;
grant execute on function programacion.fn_guard_input_family_deterministic_digest_insert_v1() to postgres;

create or replace function programacion.fn_guard_input_family_deterministic_digest_update_v1()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, programacion
as $fn$
begin
  if new.deterministic_sha256 is distinct from old.deterministic_sha256 then
    raise exception 'M63_DETERMINISTIC_DIGEST_IMMUTABLE:%:%', old.run_id, old.family_code;
  end if;
  return new;
end;
$fn$;

revoke all on function programacion.fn_guard_input_family_deterministic_digest_update_v1() from public;
grant execute on function programacion.fn_guard_input_family_deterministic_digest_update_v1() to postgres;

create temporary table _m63_target_runs(run_id bigint primary key) on commit drop;
insert into _m63_target_runs(run_id)
select max(id)
from programacion.input_readiness_runs
where pantalla_id in (1,2,3,5,43,51,52,53,54,55,56,57,58)
group by pantalla_id;

lock table programacion.input_family_assessments in access exclusive mode;

-- Preserve every existing UPDATE guard for every field except the new digest-only backfill.
drop trigger if exists trg_input_family_assessment_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_update
before update on programacion.input_family_assessments
for each row
when ((to_jsonb(new) - 'deterministic_sha256') is distinct from (to_jsonb(old) - 'deterministic_sha256'))
execute function programacion.fn_guard_input_family_assessment_update();

update programacion.input_family_assessments a
set deterministic_sha256 = (
  programacion.fn_input_family_deterministic_assess_v1(a.run_id,a.family_code,to_jsonb(a))->>'result_sha256'
)
from _m63_target_runs t
where t.run_id = a.run_id
  and a.deterministic_sha256 is null;

-- Restore the original full-row guard before commit.
drop trigger trg_input_family_assessment_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_update
before update on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_family_assessment_update();

do $verify$
declare v_nulls integer; v_bad_sha integer; v_bad_runs integer;
begin
  select count(*) into v_nulls
  from programacion.input_family_assessments a
  join _m63_target_runs t on t.run_id=a.run_id
  where a.deterministic_sha256 is null;

  select count(*) into v_bad_sha
  from programacion.input_family_assessments a
  join _m63_target_runs t on t.run_id=a.run_id
  where a.deterministic_sha256 !~ '^[0-9a-f]{64}$';

  select count(*) into v_bad_runs
  from (
    select a.run_id
    from programacion.input_family_assessments a
    join _m63_target_runs t on t.run_id=a.run_id
    group by a.run_id
    having count(*)<>47 or count(distinct a.family_code)<>47
  ) q;

  if v_nulls<>0 then raise exception 'M63_DETERMINISTIC_DIGEST_BACKFILL_NULLS:%',v_nulls; end if;
  if v_bad_sha<>0 then raise exception 'M63_DETERMINISTIC_DIGEST_BACKFILL_BAD_SHA:%',v_bad_sha; end if;
  if v_bad_runs<>0 then raise exception 'M63_DETERMINISTIC_DIGEST_BACKFILL_FAMILY_CARDINALITY:%',v_bad_runs; end if;
end;
$verify$;

drop trigger if exists trg_input_family_assessment_zz_deterministic_digest_insert on programacion.input_family_assessments;
create trigger trg_input_family_assessment_zz_deterministic_digest_insert
before insert on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_family_deterministic_digest_insert_v1();

drop trigger if exists trg_input_family_assessment_zz_deterministic_digest_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_zz_deterministic_digest_update
before update on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_family_deterministic_digest_update_v1();

commit;
