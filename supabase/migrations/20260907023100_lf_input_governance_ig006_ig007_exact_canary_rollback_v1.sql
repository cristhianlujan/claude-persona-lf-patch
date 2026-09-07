-- Strategy 28 / Input Governance IG-006 + IG-007 exact-version mandatory rollback.
-- Paired with 20260907023000. Restores exact baseline guard and drops all canary-only functions.

do $preflight$
declare
  v_guard text;
  v_backup text;
  v_count integer;
begin
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'::regprocedure)
    into v_guard,v_backup;

  if position('lf.input_screen_canonical_graph_v1' in v_guard)=0
     or position('v_cached_graph is null and v_cached_graph_sha is null' in v_guard)=0 then
    raise exception 'S28_IG007_ROLLBACK_FORWARD_GUARD_NOT_PRESENT';
  end if;
  if encode(extensions.digest(convert_to(replace(v_backup,'fn_guard_input_family_assessment_insert_baseline_ig007_v1','fn_guard_input_family_assessment_insert'),'UTF8'),'sha256'),'hex')
     <> 'd000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574' then
    raise exception 'S28_IG007_ROLLBACK_BACKUP_BASELINE_SHA_DRIFT';
  end if;

  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
    'fn_input_rebind_assertion_cached_v1',
    'fn_input_v58_build_assertions_cached_v1',
    'fn_input_governance_curator_rebind_candidate_v1'
  );
  if v_count<>4 then raise exception 'S28_IG006_ROLLBACK_EXPECTED_FORWARD_OBJECTS_MISSING:%',v_count; end if;
end;
$preflight$;

do $rollback$
declare
  v_backup text;
begin
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'::regprocedure)
    into v_backup;
  v_backup:=replace(
    v_backup,
    'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()',
    'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert()'
  );
  execute v_backup;
end;
$rollback$;

drop function programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean);
drop function programacion.fn_input_v58_build_assertions_cached_v1(bigint,bigint,text,jsonb);
drop function programacion.fn_input_rebind_assertion_cached_v1(bigint,text,jsonb,jsonb);
drop function programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1();

do $verify$
declare
  v_rebind text;
  v_assertions text;
  v_rebind_assertion text;
  v_guard text;
  v_exec text;
  v_count integer;
begin
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),
         pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_rebind,v_assertions,v_rebind_assertion,v_guard,v_exec;

  if encode(extensions.digest(convert_to(v_rebind,'UTF8'),'sha256'),'hex') <> '1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79' then
    raise exception 'S28_IG006_ROLLBACK_REBIND_SHA_MISMATCH';
  end if;
  if encode(extensions.digest(convert_to(v_assertions,'UTF8'),'sha256'),'hex') <> 'd02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822' then
    raise exception 'S28_IG006_ROLLBACK_ASSERTIONS_SHA_MISMATCH';
  end if;
  if encode(extensions.digest(convert_to(v_rebind_assertion,'UTF8'),'sha256'),'hex') <> 'b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e' then
    raise exception 'S28_IG006_ROLLBACK_REBIND_ASSERTION_SHA_MISMATCH';
  end if;
  if encode(extensions.digest(convert_to(v_guard,'UTF8'),'sha256'),'hex') <> 'd000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574' then
    raise exception 'S28_IG007_ROLLBACK_GUARD_SHA_MISMATCH';
  end if;
  if position('fn_input_governance_curator_rebind_candidate_v1' in v_exec)>0 then
    raise exception 'S28_IG006_ROLLBACK_LIVE_EXECUTE_CONTAMINATED';
  end if;

  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
    'fn_input_rebind_assertion_cached_v1',
    'fn_input_v58_build_assertions_cached_v1',
    'fn_input_governance_curator_rebind_candidate_v1'
  );
  if v_count<>0 then raise exception 'S28_IG006_ROLLBACK_RESIDUE:%',v_count; end if;
end;
$verify$;
