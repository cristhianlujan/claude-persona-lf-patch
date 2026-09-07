#!/usr/bin/env bash
set -euo pipefail
: "${SUPABASE_DB_PASSWORD:?LF_SUPABASE_DB_PASSWORD missing}"
PROJECT="${SUPABASE_PROJECT_ID:-mhwmirqcgxxukpctffuv}"
HOST="${SUPABASE_POOLER_HOST:-aws-1-us-east-1.pooler.supabase.com}"
F=20260907023000
R=20260907023100
RF=supabase/migrations/20260907023100_lf_input_governance_ig006_ig007_exact_canary_rollback_v1.sql
MIRROR="${RUNNER_TEMP:-/tmp}/s28-ig006-rollback-mirror"
BR=1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79
BA=d02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822
BRA=b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e
BG=d000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574
BE=3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588
export PGHOST="$HOST" PGPORT=5432 PGUSER="postgres.${PROJECT}" PGPASSWORD="$SUPABASE_DB_PASSWORD" PGDATABASE=postgres PGSSLMODE=require
psql_q(){ docker run --rm -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE postgres:17.6 psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }

state="$(psql_q "select count(*) filter(where version='$F')||':'||count(*) filter(where version='$R') from supabase_migrations.schema_migrations where version in ('$F','$R');")"
case "$state" in
  0:0)
    echo S28_EXACT_ROLLBACK_NOT_REQUIRED_NO_FORWARD
    exit 0
    ;;
  1:1)
    echo S28_EXACT_ROLLBACK_ALREADY_CLOSED
    ;;
  1:0)
    DB_URL="$(python3 - <<'PY'
import os
from urllib.parse import quote
print(f"postgresql://postgres.{os.environ['SUPABASE_PROJECT_ID']}:{quote(os.environ['SUPABASE_DB_PASSWORD'],safe='')}@{os.environ['SUPABASE_POOLER_HOST']}:5432/postgres?sslmode=require")
PY
)"
    rm -rf "$MIRROR"
    mkdir -p "$MIRROR/supabase"
    cp supabase/config.toml "$MIRROR/supabase/config.toml"
    supabase --workdir "$MIRROR" --yes migration fetch --db-url "$DB_URL"
    test -f "$MIRROR/supabase/migrations/${F}_lf_input_governance_ig006_ig007_exact_canary_forward_v1.sql"
    ! find "$MIRROR/supabase/migrations" -maxdepth 1 -type f -name "${R}_*.sql" | grep -q .
    cp "$RF" "$MIRROR/supabase/migrations/$(basename "$RF")"
    supabase --workdir "$MIRROR" db push --include-all --db-url "$DB_URL" --dry-run 2>&1 | tee "${RUNNER_TEMP:-/tmp}/ig006-rollback-dry.log"
    grep -q "$R" "${RUNNER_TEMP:-/tmp}/ig006-rollback-dry.log"
    supabase --workdir "$MIRROR" --yes db push --include-all --db-url "$DB_URL"
    echo S28_EXACT_ROLLBACK_APPLIED
    ;;
  *)
    echo "FAIL_EXACT_ROLLBACK_LEDGER_STATE:$state" >&2
    exit 1
    ;;
esac

psql_q "do \$z\$
declare f int; r int; n int; t int; a text; b text; c text; d text; e text;
begin
  select count(*) filter(where version='$F'),count(*) filter(where version='$R') into f,r
    from supabase_migrations.schema_migrations where version in ('$F','$R');
  if f<>1 or r<>1 then raise exception 'S28_ROLLBACK_LEDGER:f=% r=%',f,r; end if;
  select count(*) into n from pg_proc p join pg_namespace x on x.oid=p.pronamespace
    where x.nspname='programacion' and p.proname in (
      'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
      'fn_input_rebind_assertion_cached_v1','fn_input_v58_build_assertions_cached_v1',
      'fn_input_governance_curator_rebind_candidate_v1');
  if n<>0 then raise exception 'S28_ROLLBACK_FUNCTION_RESIDUE:%',n; end if;
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),
         pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into a,b,c,d,e;
  if encode(extensions.digest(convert_to(a,'UTF8'),'sha256'),'hex')<>'$BR' then raise exception 'S28_ROLLBACK_REBIND_SHA'; end if;
  if encode(extensions.digest(convert_to(b,'UTF8'),'sha256'),'hex')<>'$BA' then raise exception 'S28_ROLLBACK_ASSERTIONS_SHA'; end if;
  if encode(extensions.digest(convert_to(c,'UTF8'),'sha256'),'hex')<>'$BRA' then raise exception 'S28_ROLLBACK_REBIND_ASSERTION_SHA'; end if;
  if encode(extensions.digest(convert_to(d,'UTF8'),'sha256'),'hex')<>'$BG' then raise exception 'S28_ROLLBACK_GUARD_SHA'; end if;
  if encode(extensions.digest(convert_to(e,'UTF8'),'sha256'),'hex')<>'$BE' then raise exception 'S28_ROLLBACK_EXECUTE_SHA'; end if;
  select count(*) into t from programacion.input_readiness_runs
    where curator_identity like 'INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IGEXACT_%'
       or validator_identity like 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:S28IGEXACT_%';
  if t<>0 then raise exception 'S28_ROLLBACK_TEST_RUN_RESIDUE:%',t; end if;
  raise notice 'S28_MANDATORY_EXACT_ROLLBACK_ZERO_RESIDUE_PASS';
end; \$z\$;"
