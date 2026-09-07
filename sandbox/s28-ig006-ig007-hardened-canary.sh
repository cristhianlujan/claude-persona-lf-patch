#!/usr/bin/env bash
set -euo pipefail
: "${SUPABASE_DB_PASSWORD:?LF_SUPABASE_DB_PASSWORD missing}"
PROJECT="${SUPABASE_PROJECT_ID:-mhwmirqcgxxukpctffuv}"
HOST="${SUPABASE_POOLER_HOST:-aws-1-us-east-1.pooler.supabase.com}"
F=20260907023000
R=20260907023100
FF=supabase/migrations/20260907023000_lf_input_governance_ig006_ig007_exact_canary_forward_v1.sql
RF=supabase/migrations/20260907023100_lf_input_governance_ig006_ig007_exact_canary_rollback_v1.sql
MIRROR="${RUNNER_TEMP:-/tmp}/s28-ig006-hardened-mirror"
BR=1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79
BA=d02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822
BRA=b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e
BG=d000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574
BE=3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588
export FF RF BR BA BRA BG

python3 - <<'PY'
import os
from pathlib import Path
f=Path(os.environ['FF']).read_text(); r=Path(os.environ['RF']).read_text()
need_f=['fn_guard_input_family_assessment_insert_baseline_ig007_v1','fn_input_rebind_assertion_cached_v1','fn_input_v58_build_assertions_cached_v1','fn_input_governance_curator_rebind_candidate_v1','lf.input_screen_canonical_graph_v1']
need_r=['S28_IG007_ROLLBACK_BACKUP_BASELINE_SHA_DRIFT','drop function programacion.fn_input_governance_curator_rebind_candidate_v1','drop function programacion.fn_input_v58_build_assertions_cached_v1','drop function programacion.fn_input_rebind_assertion_cached_v1','drop function programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1',os.environ['BR'],os.environ['BA'],os.environ['BRA'],os.environ['BG']]
missing=[f'forward:{x}' for x in need_f if x not in f]+[f'rollback:{x}' for x in need_r if x not in r]
if missing: raise SystemExit('FAIL_STATIC_ROLLBACK_GUARD:'+','.join(missing))
print('PASS_STATIC_ROLLBACK_FINALIZER_GUARD')
PY

export PGHOST="$HOST" PGPORT=5432 PGUSER="postgres.${PROJECT}" PGPASSWORD="$SUPABASE_DB_PASSWORD" PGDATABASE=postgres PGSSLMODE=require
psql_do(){ docker run --rm -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE postgres:17.6 psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }

psql_do "do \$p\$
declare f int; r int; n int; a text; b text; c text; d text; e text;
begin
  perform 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure;
  perform 'programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure;
  select count(*) filter(where version='$F'),count(*) filter(where version='$R') into f,r
    from supabase_migrations.schema_migrations where version in ('$F','$R');
  if f<>0 or r<>0 then raise exception 'S28_PREFLIGHT_VERSION_PRESENT:f=% r=%',f,r; end if;
  select count(*) into n from pg_proc p join pg_namespace x on x.oid=p.pronamespace
    where x.nspname='programacion' and p.proname in (
      'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
      'fn_input_rebind_assertion_cached_v1','fn_input_v58_build_assertions_cached_v1',
      'fn_input_governance_curator_rebind_candidate_v1');
  if n<>0 then raise exception 'S28_PREFLIGHT_CANDIDATE_RESIDUE:%',n; end if;
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),
         pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),
         pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into a,b,c,d,e;
  if encode(extensions.digest(convert_to(a,'UTF8'),'sha256'),'hex')<>'$BR' then raise exception 'S28_PREFLIGHT_REBIND_SHA'; end if;
  if encode(extensions.digest(convert_to(b,'UTF8'),'sha256'),'hex')<>'$BA' then raise exception 'S28_PREFLIGHT_ASSERTIONS_SHA'; end if;
  if encode(extensions.digest(convert_to(c,'UTF8'),'sha256'),'hex')<>'$BRA' then raise exception 'S28_PREFLIGHT_REBIND_ASSERTION_SHA'; end if;
  if encode(extensions.digest(convert_to(d,'UTF8'),'sha256'),'hex')<>'$BG' then raise exception 'S28_PREFLIGHT_GUARD_SHA'; end if;
  if encode(extensions.digest(convert_to(e,'UTF8'),'sha256'),'hex')<>'$BE' then raise exception 'S28_PREFLIGHT_EXECUTE_SHA'; end if;
  raise notice 'S28_PREFLIGHT_BASELINE_PASS';
end; \$p\$;"

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
remote_count="$(find "$MIRROR/supabase/migrations" -maxdepth 1 -type f -name '20????????????_*.sql' | wc -l | tr -d ' ')"
test "$remote_count" -ge 100
test -f "$MIRROR/supabase/migrations/20260906185000_lf_input_governance_downstream_graph_reuse_candidate_v1.sql"
test -f "$MIRROR/supabase/migrations/20260906185100_lf_input_governance_graph_reuse_regression_v1.sql"
! find "$MIRROR/supabase/migrations" -maxdepth 1 -type f -name "${F}_*.sql" | grep -q .
! find "$MIRROR/supabase/migrations" -maxdepth 1 -type f -name "${R}_*.sql" | grep -q .
echo "PASS_REMOTE_MIRROR count=$remote_count"

cp "$FF" "$MIRROR/supabase/migrations/$(basename "$FF")"
supabase --workdir "$MIRROR" db push --db-url "$DB_URL" --dry-run 2>&1 | tee "${RUNNER_TEMP:-/tmp}/ig006-forward-dry.log"
grep -q "$F" "${RUNNER_TEMP:-/tmp}/ig006-forward-dry.log"
! grep -q "$R" "${RUNNER_TEMP:-/tmp}/ig006-forward-dry.log"
supabase --workdir "$MIRROR" --yes db push --db-url "$DB_URL"

psql_do "do \$v\$
declare f int; r int; n int; g text; bk text;
begin
  select count(*) filter(where version='$F'),count(*) filter(where version='$R') into f,r
    from supabase_migrations.schema_migrations where version in ('$F','$R');
  if f<>1 or r<>0 then raise exception 'S28_FORWARD_LEDGER:f=% r=%',f,r; end if;
  select count(*) into n from pg_proc p join pg_namespace x on x.oid=p.pronamespace
    where x.nspname='programacion' and p.proname in (
      'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
      'fn_input_rebind_assertion_cached_v1','fn_input_v58_build_assertions_cached_v1',
      'fn_input_governance_curator_rebind_candidate_v1');
  if n<>4 then raise exception 'S28_FORWARD_OBJECTS:%',n; end if;
  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'::regprocedure)
    into g,bk;
  if position('lf.input_screen_canonical_graph_v1' in g)=0 then raise exception 'S28_FORWARD_GUARD_NOT_CANDIDATE'; end if;
  if encode(extensions.digest(convert_to(replace(bk,'fn_guard_input_family_assessment_insert_baseline_ig007_v1','fn_guard_input_family_assessment_insert'),'UTF8'),'sha256'),'hex')<>'$BG' then
    raise exception 'S28_FORWARD_BACKUP_SHA';
  end if;
  raise notice 'S28_FORWARD_REVERSIBILITY_PASS';
end; \$v\$;"

runner="${RUNNER_TEMP:-/tmp}/s28-ig006-runner.sql"
git show 5b9ff7f7c870e21b1daf53e21e62bdbb31266cbe:sandbox/s28-input-governance-ig006-ig007-exact-canary-20260907.sql > "$runner"
python3 - "$runner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
anchor='-- Durable readback: all test identities must have rolled back.\n'
extra="""-- IG-A additional current controls.\nbegin; set local statement_timeout='120s'; select pg_temp.s28_ig_exact_case(57,'ONB_004') as s28_ig_exact_result; rollback;\nbegin; set local statement_timeout='120s'; select pg_temp.s28_ig_exact_case(3,'ONB_003') as s28_ig_exact_result; rollback;\nbegin; set local statement_timeout='120s'; select pg_temp.s28_ig_exact_case(2,'ONB_002') as s28_ig_exact_result; rollback;\ndo $stale$ declare x bigint; v boolean; begin foreach x in array array[218::bigint,210::bigint,186::bigint,191::bigint] loop v:=programacion.fn_input_readiness_run_is_current_cached_v2(x); if v is distinct from false then raise exception 'S28_IGA_STALE_FALSE_CLOSE:run=% current=%',x,v; end if; end loop; raise notice 'S28_IGA_STALE_CONTROLS_PASS runs=218,210,186,191 false_close=0'; end; $stale$;\n\n"""
if anchor not in s: raise SystemExit('FAIL_RUNNER_ANCHOR')
p.write_text(s.replace(anchor,extra+anchor,1))
PY

log="${RUNNER_TEMP:-/tmp}/s28-ig006-canary.log"
docker run --rm -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE -v "$runner:/runner.sql:ro" postgres:17.6 psql -X -qAt -v ON_ERROR_STOP=1 -f /runner.sql 2>&1 | tee "$log"
grep -q 'S28_IGA_STALE_CONTROLS_PASS' "$log"
grep -q 'S28_IG_EXACT_CANARY_PASS' "$log"
python3 - "$log" <<'PY'
import json,math,sys
rows=[]
for line in open(sys.argv[1],encoding='utf-8'):
    line=line.strip()
    if line.startswith('{') and 'screen_code' in line: rows.append(json.loads(line))
if len(rows)!=5: raise SystemExit(f'FAIL_IGA_RESULT_CARDINALITY:{len(rows)}')
if any(r.get('result')!='PASS' for r in rows): raise SystemExit('FAIL_IGA_NONPASS_RESULT')
def pct(v,p):
    x=sorted(float(i) for i in v); k=(len(x)-1)*p; a=math.floor(k); b=math.ceil(k)
    return x[a] if a==b else x[a]+(x[b]-x[a])*(k-a)
cur=[r['curator_ms'] for r in rows]; val=[r['validator_total_ms'] for r in rows]
print('IGA_CURRENT_SCREENS_PASS=5/5')
print('IGA_PORTFOLIO_SAMPLE_CURATOR_P50_MS=%.3f'%pct(cur,.5))
print('IGA_PORTFOLIO_SAMPLE_CURATOR_P95_MS=%.3f'%pct(cur,.95))
print('IGA_PORTFOLIO_SAMPLE_VALIDATOR_TOTAL_P50_MS=%.3f'%pct(val,.5))
print('IGA_PORTFOLIO_SAMPLE_VALIDATOR_TOTAL_P95_MS=%.3f'%pct(val,.95))
for r in sorted(rows,key=lambda z:z['screen_code']): print('IGA_CASE='+json.dumps(r,sort_keys=True,separators=(',',':')))
PY

echo S28_IG006_IG007_FORWARD_CANARY_PASS_AWAITING_EXACT_ROLLBACK
