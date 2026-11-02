#!/usr/bin/env bash
# H1-C2 / PG-01 GitHub OIDC authority — RED/GREEN on a DISPOSABLE, Supabase-shaped cluster.
#  1. synthetic: Deno auth_test.ts (crypto + claim policy, local RS256 key)
#  2. integration: Edge handler -> public RPC (as service_role via authenticator) -> PostgreSQL
#  3. regression: unchanged PG-01 legacy suite (test_pg01_authority_attestations_v1.sql) with this migration applied
# None of these is an authentic GitHub/Supabase PASS. Never point this at a hosted database.
# Usage (repo root): PGBIN=<pg17.6 bin> DENO=<deno> [DENO_FLAGS=...] bash <this file>
set -euo pipefail
PGBIN=${PGBIN:?PGBIN required}; DENO=${DENO:-deno}; DENO_FLAGS=${DENO_FLAGS:-}
DIR=$(dirname "$0"); FN=supabase/functions/lf-pg01-oidc-authority-v1
MIG_ATT=$(ls supabase/migrations/*_lf_pg01_authority_attestations_v1.sql | tail -1)
MIG_OIDC=$(ls supabase/migrations/*_lf_pg01_oidc_authority_v1.sql | tail -1)
PORT=${PORT:-55436}; WORK=$(mktemp -d)
trap '"$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
rnd(){ head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9'; }
PW_PG=$(rnd); PW_AUTH=$(rnd)

echo "== 1. synthetic boundary (Deno) =="
$DENO test $DENO_FLAGS -A "$FN/auth_test.ts" 2>&1 | grep -E "PASSED|FAILED|passed|failed" | sed 's/\x1b\[[0-9;]*m//g'

"$PGBIN/initdb" -D "$WORK/data" -U supabase_admin -A trust --no-sync >/dev/null
printf 'local all supabase_admin trust\nhost all all 127.0.0.1/32 scram-sha-256\n' > "$WORK/data/pg_hba.conf"
"$PGBIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=127.0.0.1" -l "$WORK/pg.log" -w start >/dev/null
SU(){ "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$WORK" -p $PORT -U supabase_admin -d postgres "$@"; }
PG(){ PGPASSWORD=$PW_PG "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h 127.0.0.1 -p $PORT -U postgres -d postgres "$@"; }
VERSION=$(SU -Atc "show server_version")

# Supabase shape: postgres NOSUPERUSER CREATEROLE owns app schemas; authority groups ADMIN-only; authenticator -> service_role.
SU >/dev/null <<SQL
CREATE ROLE postgres LOGIN CREATEROLE NOSUPERUSER PASSWORD '$PW_PG';
CREATE SCHEMA private AUTHORIZATION postgres; GRANT CREATE ON SCHEMA public TO postgres;
CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
\i $DIR/pg01_authority_programacion_fixture.sql
ALTER ROLE authenticator LOGIN NOINHERIT PASSWORD '$PW_AUTH'; GRANT service_role TO authenticator;
DO \$g\$ DECLARE r text; BEGIN FOREACH r IN ARRAY ARRAY['programacion_builder','programacion_auditor','programacion_verifier','programacion_human_authority','programacion_promoter'] LOOP
 EXECUTE format('GRANT %I TO postgres WITH ADMIN TRUE, INHERIT FALSE, SET FALSE',r); END LOOP; END \$g\$;
SQL
PG >/dev/null <<SQL
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY,context_payload jsonb NOT NULL,context_sha256 text NOT NULL,created_by_execution_id text NOT NULL);
CREATE TABLE private.lf_evidence_ledger_v1(receipt_id uuid PRIMARY KEY,execution_id text,capability_code text,gate_code text,receipt_kind text,
 subject_type text,subject_ref text,subject_sha256 text,source_head_sha text,verification_state text,created_by_execution_id text);
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY,operation_code text,status text,manifest jsonb,created_by_execution_id text DEFAULT 'UNKNOWN');
CREATE TABLE public.lf_operation_execution_steps(execution_id text,step_id text,status text,evidence_payload jsonb,created_by_execution_id text DEFAULT 'UNKNOWN');
GRANT USAGE ON SCHEMA private TO service_role;
GRANT SELECT,INSERT,UPDATE ON public.lf_operation_execution, public.lf_operation_execution_steps TO service_role;
SQL
PG -f "$MIG_ATT" >/dev/null
PG -f "$MIG_OIDC" >/dev/null && echo "MIGRATION_APPLIED_AS_NON_SUPERUSER_POSTGRES"
PG -Atc "select r.rolname from pg_proc p join pg_roles r on r.oid=p.proowner where p.proname='fn_lf_pg01_oidc_record_core_v1'" | sed 's/^/CORE_OWNER=/'
PG -Atc "select string_agg(l.rolname||'>'||g.rolname||':set='||m.set_option||':inh='||m.inherit_option||':adm='||m.admin_option,' ') from pg_auth_members m join pg_roles g on g.oid=m.roleid join pg_roles l on l.oid=m.member where g.rolname='lf_pg01_oidc_recorder' or l.rolname='lf_pg01_oidc_recorder'" | sed 's/^/RECORDER_MEMBERSHIPS=/'
if PG -f "$MIG_OIDC" >/dev/null 2>"$WORK/rerun.err"; then echo "FAIL rerun not fail-closed"; exit 1; else grep -o 'PG01_OIDC_RECORDER_ALREADY_EXISTS' "$WORK/rerun.err" | sed 's/^/RERUN_FAIL_CLOSED=/'; fi

PG >/dev/null <<'SQL'
INSERT INTO private.lf_decision_context_asof_v1 SELECT ('aaaaaaaa-0000-4000-8000-00000000000'||i)::uuid, p, encode(sha256(convert_to(p::text,'UTF8')),'hex'),
  CASE WHEN i=3 THEN 'EXEC-ANALYSIS-GHA-RUN-1077-R1' ELSE 'PROFILE' END
 FROM (SELECT i, jsonb_build_object('snapshot',i) p FROM generate_series(1,3) i) q;
INSERT INTO private.lf_evidence_ledger_v1(receipt_id,subject_type,subject_ref,subject_sha256,source_head_sha,verification_state,created_by_execution_id)
SELECT r,'PROGRAMMING_ANALYSIS_PACKAGE','PROGRAMMING_ANALYSIS_PACKAGE/'||c.context_id,coalesce(v.sha0,c.context_sha256),head,'VERIFIED',anchor FROM (VALUES
 ('11111111-0000-4000-8000-000000000001'::uuid,1,NULL::text,repeat('1',40),'LEDGER-X'),
 ('11111111-0000-4000-8000-000000000003'::uuid,1,repeat('f',64),repeat('1',40),'LEDGER-X'),
 ('11111111-0000-4000-8000-000000000004'::uuid,1,NULL,'not-a-head','LEDGER-X'),
 ('11111111-0000-4000-8000-000000000005'::uuid,1,NULL,repeat('1',40),'PROFILE'),
 ('11111111-0000-4000-8000-000000000006'::uuid,3,NULL,repeat('1',40),'LEDGER-X'),
 ('11111111-0000-4000-8000-000000000007'::uuid,2,NULL,repeat('1',40),'LEDGER-X')) v(r,i,sha0,head,anchor)
JOIN private.lf_decision_context_asof_v1 c ON c.context_id=('aaaaaaaa-0000-4000-8000-00000000000'||v.i)::uuid;
INSERT INTO public.lf_operation_execution VALUES
 ('J1','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','COMPLETED',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','subject_type','PROGRAMMING_ANALYSIS_PACKAGE',
  'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/aaaaaaaa-0000-4000-8000-000000000001','subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001'),
  'source_head_sha',repeat('1',40),'subject_receipt_id','11111111-0000-4000-8000-000000000001','producer_execution_id','PROFILE'),'ORCH');
INSERT INTO public.lf_operation_execution SELECT 'J2',operation_code,'IN_PROGRESS',manifest,'ORCH' FROM public.lf_operation_execution WHERE execution_id='J1';
INSERT INTO public.lf_operation_execution SELECT 'J4',operation_code,status,manifest||jsonb_build_object('source_head_sha',repeat('9',40)),'ORCH' FROM public.lf_operation_execution WHERE execution_id='J1';
INSERT INTO public.lf_operation_execution_steps VALUES('J1','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','J1'),('J1','judge_record','STEP_PASS_WITH_EVIDENCE','{}','J1');
SQL
CTX(){ PG -Atc "select context_sha256 from private.lf_decision_context_asof_v1 where context_id='aaaaaaaa-0000-4000-8000-00000000000$1'"; }

echo "== 2. integration (Edge handler -> RPC -> PostgreSQL $VERSION) =="
PG01_IT_PSQL="$PGBIN/psql" PG01_IT_HOST=127.0.0.1 PG01_IT_PORT=$PORT PG01_IT_AUTH_PW=$PW_AUTH PG01_IT_SU=supabase_admin \
PG01_IT_CTX1_SHA=$(CTX 1) PG01_IT_CTX2_SHA=$(CTX 2) PG01_IT_CTX3_SHA=$(CTX 3) PG01_IT_SU_HOST="$WORK" \
 $DENO test $DENO_FLAGS -A "$FN/integration_test.ts" > "$WORK/it.txt" 2>&1 || true
sed 's/\x1b\[[0-9;]*m//g' "$WORK/it.txt" | grep -E "^(PASS|FAIL) |PG01_OIDC_INTEGRATION|passed|failed"

echo "== 3. legacy regression with this migration applied (superuser harness, unchanged suite) =="
SUITE="$DIR/test_pg01_authority_attestations_v1.sql"
# Same suite; after it loads the attestation migration it also loads this migration (BEGIN/COMMIT stripped the same way).
awk -v mig="$MIG_OIDC" '{print} /^\\gexec$/ && !done {print "TRUNCATE src_lines;"; print "\\copy src_lines(line) FROM '\''" mig "'\'' WITH (FORMAT csv, DELIMITER E'\''\\x01'\'', QUOTE E'\''\\x02'\'', ESCAPE E'\''\\x03'\'')"; print "SELECT replace(replace(string_agg(coalesce(line,'\'''\''),E'\''\\n'\'' ORDER BY n),E'\''\\nBEGIN;\\n'\'',E'\''\\n'\''),E'\''\\nCOMMIT;'\'',E'\''\\n'\'') FROM src_lines"; print "\\gexec"; done=1}' "$SUITE" > "$WORK/reg.sql"
# the legacy suite expects a superuser named postgres: run it in a separate disposable cluster
"$PGBIN/initdb" -D "$WORK/reg" -U postgres -A trust --no-sync >/dev/null
"$PGBIN/pg_ctl" -D "$WORK/reg" -o "-p $((PORT+1)) -k $WORK -c listen_addresses=''" -l "$WORK/reg.log" -w start >/dev/null
"$PGBIN/psql" -X -h "$WORK" -p $((PORT+1)) -U postgres -d postgres -f "$WORK/reg.sql" 2>&1 | grep -ioE "PG01_AUTHORITY_ATTESTATION_TESTS_PASSED:[0-9]+|TEST_FAIL.*|error:.*" | head -3
"$PGBIN/pg_ctl" -D "$WORK/reg" -m immediate stop >/dev/null
echo "SERVER_VERSION=$VERSION"
grep -q "PG01_OIDC_INTEGRATION_PASSED" "$WORK/it.txt"
