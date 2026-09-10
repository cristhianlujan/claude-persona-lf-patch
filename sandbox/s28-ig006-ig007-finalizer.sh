#!/usr/bin/env bash
set -euo pipefail
: "${SUPABASE_DB_PASSWORD:?LF_SUPABASE_DB_PASSWORD missing}"
MODE="${1:-restore}"
PROJECT="${SUPABASE_PROJECT_ID:-mhwmirqcgxxukpctffuv}"
HOST="${SUPABASE_POOLER_HOST:-aws-1-us-east-1.pooler.supabase.com}"
F=20260907023000
R=20260907023100
BR=1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79
BA=d02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822
BRA=b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e
BG=d000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574
BE=3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588
export PGHOST="$HOST" PGPORT=5432 PGUSER="postgres.${PROJECT}" PGPASSWORD="$SUPABASE_DB_PASSWORD" PGDATABASE=postgres PGSSLMODE=require
psql_do(){ docker run --rm -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE postgres:17.6 psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }

if [[ "$MODE" == "restore" ]]; then
  psql_do "do \$s\$
  declare f int; r int; n int; bn int; a text; b text; c text; g text; e text; bk text;
  begin
    select count(*) filter(where version='$F'),count(*) filter(where version='$R') into f,r
      from supabase_migrations.schema_migrations where version in ('$F','$R');
    select count(*) into n from pg_proc p join pg_namespace x on x.oid=p.pronamespace
      where x.nspname='programacion' and p.proname in (
        'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
        'fn_input_rebind_assertion_cached_v1',
        'fn_input_v58_build_assertions_cached_v1',
        'fn_input_governance_curator_rebind_candidate_v1');
    select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),
           pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),
           pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),
           pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
           pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
      into a,b,c,g,e;
    if encode(extensions.digest(convert_to(a,'UTF8'),'sha256'),'hex')<>'$BR'
       or encode(extensions.digest(convert_to(b,'UTF8'),'sha256'),'hex')<>'$BA'
       or encode(extensions.digest(convert_to(c,'UTF8'),'sha256'),'hex')<>'$BRA'
       or encode(extensions.digest(convert_to(e,'UTF8'),'sha256'),'hex')<>'$BE' then
      raise exception 'S28_SAFETY_NON_GUARD_BASELINE_DRIFT';
    end if;
    if f=1 and r=0 then
      if n<>4 or position('lf.input_screen_canonical_graph_v1' in g)=0 then
        raise exception 'S28_SAFETY_FORWARD_STATE_NOT_EXACT:f=% r=% objects=%',f,r,n;
      end if;
      select count(*) into bn from pg_proc p join pg_namespace x on x.oid=p.pronamespace
        where x.nspname='programacion' and p.proname='fn_guard_input_family_assessment_insert_baseline_ig007_v1'
          and pg_get_function_identity_arguments(p.oid)='';
      if bn<>1 then raise exception 'S28_SAFETY_BACKUP_CARDINALITY:%',bn; end if;
      select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'::regprocedure) into bk;
      if encode(extensions.digest(convert_to(replace(bk,'fn_guard_input_family_assessment_insert_baseline_ig007_v1','fn_guard_input_family_assessment_insert'),'UTF8'),'sha256'),'hex')<>'$BG' then
        raise exception 'S28_SAFETY_BACKUP_SHA_DRIFT';
      end if;
      bk:=replace(bk,
        'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()',
        'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert()');
      execute bk;
      drop function programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean);
      drop function programacion.fn_input_v58_build_assertions_cached_v1(bigint,bigint,text,jsonb);
      drop function programacion.fn_input_rebind_assertion_cached_v1(bigint,text,jsonb,jsonb);
      drop function programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1();
      raise notice 'S28_SAFETY_RESTORE_APPLIED_LEDGER_OPEN';
    elsif (f=0 and r=0) or (f=1 and r=1) then
      if n<>0 or encode(extensions.digest(convert_to(g,'UTF8'),'sha256'),'hex')<>'$BG' then
        raise exception 'S28_SAFETY_BASELINE_EXPECTED_DIRTY:f=% r=% objects=%',f,r,n;
      end if;
      raise notice 'S28_SAFETY_RESTORE_NOT_REQUIRED:f=% r=%',f,r;
    else
      raise exception 'S28_SAFETY_LEDGER_STATE_UNSUPPORTED:f=% r=%',f,r;
    end if;
  end; \$s\$;"
elif [[ "$MODE" == "readback" ]]; then
  psql_do "do \$z\$
  declare f int; r int; n int; t int; a text; b text; c text; g text; e text;
  begin
    select count(*) filter(where version='$F'),count(*) filter(where version='$R') into f,r
      from supabase_migrations.schema_migrations where version in ('$F','$R');
    if not ((f=0 and r=0) or (f=1 and r=1)) then raise exception 'S28_FINAL_LEDGER_NOT_CLOSED:f=% r=%',f,r; end if;
    select count(*) into n from pg_proc p join pg_namespace x on x.oid=p.pronamespace
      where x.nspname='programacion' and p.proname in (
        'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
        'fn_input_rebind_assertion_cached_v1',
        'fn_input_v58_build_assertions_cached_v1',
        'fn_input_governance_curator_rebind_candidate_v1');
    if n<>0 then raise exception 'S28_FINAL_FUNCTION_RESIDUE:%',n; end if;
    select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),
           pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),
           pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),
           pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
           pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
      into a,b,c,g,e;
    if encode(extensions.digest(convert_to(a,'UTF8'),'sha256'),'hex')<>'$BR'
       or encode(extensions.digest(convert_to(b,'UTF8'),'sha256'),'hex')<>'$BA'
       or encode(extensions.digest(convert_to(c,'UTF8'),'sha256'),'hex')<>'$BRA'
       or encode(extensions.digest(convert_to(g,'UTF8'),'sha256'),'hex')<>'$BG'
       or encode(extensions.digest(convert_to(e,'UTF8'),'sha256'),'hex')<>'$BE' then
      raise exception 'S28_FINAL_BASELINE_SHA_MISMATCH';
    end if;
    select count(*) into t from programacion.input_readiness_runs
      where curator_identity like 'INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IGEXACT_%'
         or validator_identity like 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:S28IGEXACT_%';
    if t<>0 then raise exception 'S28_FINAL_TEST_RUN_RESIDUE:%',t; end if;
    raise notice 'S28_FINAL_ZERO_RESIDUE_PASS:f=% r=%',f,r;
  end; \$z\$;"
else
  echo "unsupported mode: $MODE" >&2
  exit 2
fi
