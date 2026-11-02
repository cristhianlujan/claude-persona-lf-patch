#!/usr/bin/env bash
# H1-C2 / PG-01 — RED/GREEN for supabase/migrations/*_lf_pg01_external_authority_logins_v1.sql
# DISPOSABLE PostgreSQL ONLY. Creates a throw-away cluster, never touches a hosted DB.
# Real TCP sessions with SCRAM authentication: every authority case uses its OWN connection
# (no SET SESSION AUTHORIZATION). Passwords are random per run and never written to disk.
# Usage (repo root): PGBIN=/usr/lib/postgresql/17/bin bash <this file>
set -euo pipefail
ROOT=$(pwd)
PGBIN=${PGBIN:-$(dirname "$(command -v postgres || echo /usr/lib/postgresql/17/bin/postgres)")}
DIR=$(dirname "$0")
MIG_PROV=$(ls supabase/migrations/*_lf_pg01_external_authority_logins_v1.sql | tail -1)
MIG_ATT=$(ls supabase/migrations/*_lf_pg01_authority_attestations_v1.sql | tail -1)
PORT=${PORT:-55433}
WORK=$(mktemp -d); trap '"$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
rnd(){ head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' ; }
PW_PG=$(rnd); PW_AUTH=$(rnd); PW_VER=$(rnd); PW_AUD=$(rnd)

"$PGBIN/initdb" -D "$WORK/data" -U supabase_admin -A trust --no-sync >/dev/null
cat > "$WORK/data/pg_hba.conf" <<EOF
local all supabase_admin trust
host  all all 127.0.0.1/32 scram-sha-256
EOF
"$PGBIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=127.0.0.1 -c password_encryption=scram-sha-256" -l "$WORK/pg.log" -w start >/dev/null
SU(){ "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$WORK" -p $PORT -U supabase_admin -d postgres "$@"; }
AS(){ local u=$1 pw=$2; shift 2; PGPASSWORD=$pw PGCONNECT_TIMEOUT=5 "$PGBIN/psql" -X -q -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -p $PORT -U "$u" -d postgres "$@"; }
VERSION=$(SU -Atc "show server_version")

# ---- Supabase-shaped bootstrap: postgres is NOT superuser; authority groups granted to it ADMIN-only ----
SU <<SQL
CREATE ROLE postgres LOGIN CREATEROLE NOSUPERUSER PASSWORD '$PW_PG';
CREATE SCHEMA private; CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
\i $DIR/pg01_authority_programacion_fixture.sql
ALTER ROLE authenticator LOGIN NOINHERIT PASSWORD '$PW_AUTH';
GRANT service_role TO authenticator;
GRANT CREATE ON DATABASE postgres TO postgres;
DO \$g\$ DECLARE r text; BEGIN FOREACH r IN ARRAY ARRAY['programacion_builder','programacion_auditor','programacion_verifier','programacion_human_authority','programacion_promoter'] LOOP
 EXECUTE format('GRANT %I TO postgres WITH ADMIN TRUE, INHERIT FALSE, SET FALSE',r); END LOOP; END \$g\$;
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY,context_payload jsonb NOT NULL,context_sha256 text NOT NULL,created_by_execution_id text NOT NULL);
CREATE TABLE private.lf_evidence_ledger_v1(receipt_id uuid PRIMARY KEY,execution_id text,capability_code text,gate_code text,receipt_kind text,
 subject_type text,subject_ref text,subject_sha256 text,source_head_sha text,verification_state text,created_by_execution_id text);
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY,operation_code text,status text,manifest jsonb,created_by_execution_id text DEFAULT 'UNKNOWN');
CREATE TABLE public.lf_operation_execution_steps(execution_id text,step_id text,status text,evidence_payload jsonb,created_by_execution_id text DEFAULT 'UNKNOWN');
GRANT USAGE ON SCHEMA private TO service_role;
GRANT SELECT,INSERT,UPDATE ON public.lf_operation_execution, public.lf_operation_execution_steps TO service_role;
\i $MIG_ATT
INSERT INTO private.lf_decision_context_asof_v1 SELECT ('aaaaaaaa-0000-4000-8000-00000000000'||i)::uuid, p, encode(sha256(convert_to(p::text,'UTF8')),'hex'),'PROFILE'
 FROM (SELECT i, jsonb_build_object('snapshot',i) p FROM generate_series(1,2) i) q;
INSERT INTO private.lf_evidence_ledger_v1(receipt_id,subject_type,subject_ref,subject_sha256,source_head_sha,verification_state,created_by_execution_id)
SELECT r,'PROGRAMMING_ANALYSIS_PACKAGE','PROGRAMMING_ANALYSIS_PACKAGE/'||c.context_id,coalesce(v.sha0,c.context_sha256),head,'VERIFIED',anchor FROM (VALUES
 ('11111111-0000-4000-8000-000000000001'::uuid,1,NULL::text,repeat('1',40),'LEDGER-X'),
 ('11111111-0000-4000-8000-000000000002'::uuid,2,NULL,repeat('1',40),'LEDGER-X'),
 ('11111111-0000-4000-8000-000000000003'::uuid,1,repeat('f',64),repeat('1',40),'LEDGER-X'),
 ('11111111-0000-4000-8000-000000000004'::uuid,1,NULL,'not-a-head','LEDGER-X'),
 ('11111111-0000-4000-8000-000000000005'::uuid,1,NULL,repeat('1',40),'PROFILE')) v(r,i,sha0,head,anchor)
JOIN private.lf_decision_context_asof_v1 c ON c.context_id=('aaaaaaaa-0000-4000-8000-00000000000'||v.i)::uuid;
INSERT INTO public.lf_operation_execution VALUES
 ('J1','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','COMPLETED',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','subject_type','PROGRAMMING_ANALYSIS_PACKAGE',
  'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/aaaaaaaa-0000-4000-8000-000000000001','subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001'),
  'source_head_sha',repeat('1',40),'subject_receipt_id','11111111-0000-4000-8000-000000000001','producer_execution_id','PROFILE'),'ORCH');
INSERT INTO public.lf_operation_execution SELECT 'J2',operation_code,'IN_PROGRESS',manifest,'ORCH' FROM public.lf_operation_execution WHERE execution_id='J1';
INSERT INTO public.lf_operation_execution SELECT 'J4',operation_code,status,manifest||jsonb_build_object('source_head_sha',repeat('9',40)),'ORCH' FROM public.lf_operation_execution WHERE execution_id='J1';
INSERT INTO public.lf_operation_execution_steps VALUES('J1','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','J1'),('J1','judge_record','STEP_PASS_WITH_EVIDENCE','{}','J1');
SQL

PASS=0; FAIL=0; LOG="$WORK/results.txt"
# expect <case> <ERE pattern over "OK:<stdout>" or "ERR:<stderr>"> <user> <pw> <sql>
expect(){ local c=$1 pat=$2 u=$3 pw=$4 sql=$5 out
  if out=$(AS "$u" "$pw" -c "$sql" 2>&1); then out="OK:$out"; else out="ERR:$out"; fi
  out=$(echo "$out" | tr '\n' ' ')
  if [[ "$out" =~ $pat ]]; then PASS=$((PASS+1)); echo "PASS $c" | tee -a "$LOG"
  else FAIL=$((FAIL+1)); echo "FAIL $c :: $out" | tee -a "$LOG"; fi; }
V="INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES"
C1="'aaaaaaaa-0000-4000-8000-000000000001'"
VER(){ echo "BEGIN; SET LOCAL ROLE programacion_verifier; $V('11111111-0000-4000-8000-00000000000$1',$C1); COMMIT;"; }
ATT(){ echo "BEGIN; SET LOCAL ROLE programacion_auditor; INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('$1'); COMMIT;"; }

echo "== RED (before provisioning) =="
expect RED0_verifier_login_absent 'ERR:.*(password authentication failed|does not exist)' lf_pg01_verifier_login "$PW_VER" "select 1"
expect RED0_auditor_login_absent  'ERR:.*(password authentication failed|does not exist)' lf_pg01_auditor_login "$PW_AUD" "select 1"
expect RED0_postgres_cannot_set_verifier 'ERR:.*permission denied' postgres "$PW_PG" "$(VER 1)"
expect RED0_service_role_cannot_verify 'ERR:.*permission denied' authenticator "$PW_AUTH" "SET ROLE service_role; $V('11111111-0000-4000-8000-000000000001',$C1)"

echo "== APPLY provisioning migration as non-superuser postgres =="
expect APPLY_as_postgres '^OK' postgres "$PW_PG" "$(cat "$MIG_PROV")"
expect APPLY_rerun_fail_closed 'ERR:.*PG01_EXTERNAL_LOGIN_ALREADY_EXISTS_REVIEW_MANUALLY' postgres "$PW_PG" "$(cat "$MIG_PROV")"
expect CAT_exact_memberships '^OK:lf_pg01_auditor_login>programacion_auditor:true:false:false lf_pg01_verifier_login>programacion_verifier:true:false:false *$' postgres "$PW_PG" \
 "select l.rolname||'>'||g.rolname||':'||m.set_option||':'||m.inherit_option||':'||m.admin_option from pg_auth_members m join pg_roles g on g.oid=m.roleid join pg_roles l on l.oid=m.member where l.rolname like 'lf_pg01_%' order by 1"
expect CAT_creator_membership_admin_only '^OK:postgres>lf_pg01_auditor_login:false:false:true postgres>lf_pg01_verifier_login:false:false:true *$' postgres "$PW_PG" \
 "select l.rolname||'>'||g.rolname||':'||m.set_option||':'||m.inherit_option||':'||m.admin_option from pg_auth_members m join pg_roles g on g.oid=m.roleid join pg_roles l on l.oid=m.member where g.rolname like 'lf_pg01_%' order by 1"
expect RED_self_grant_set_rejected 'ERR:.*PG01_EXTERNAL_LOGIN_ADMIN_MEMBERSHIP_NOT_ADMIN_ONLY' postgres "$PW_PG" \
 "SET createrole_self_grant='set'; $(sed -e 's/lf_pg01_verifier_login/lf_pg01_x_verifier_login/g; s/lf_pg01_auditor_login/lf_pg01_x_auditor_login/g' "$MIG_PROV")"
expect CAT_self_grant_attempt_left_no_roles '^OK:0 *$' postgres "$PW_PG" "select count(*) from pg_roles where rolname like 'lf_pg01_x_%'"
expect RED1_null_password_cannot_login 'ERR:.*password authentication failed' lf_pg01_verifier_login "$PW_VER" "select 1"

echo "== admin sets secrets out-of-band (simulated; random, not persisted) =="
SU -c "ALTER ROLE lf_pg01_verifier_login PASSWORD '$PW_VER'; ALTER ROLE lf_pg01_auditor_login PASSWORD '$PW_AUD';" >/dev/null

echo "== negatives with real independent sessions =="
expect N_verifier_direct_insert_noinherit 'ERR:.*permission denied' lf_pg01_verifier_login "$PW_VER" "$V('11111111-0000-4000-8000-000000000001',$C1)"
expect N_verifier_cannot_become_auditor 'ERR:.*permission denied' lf_pg01_verifier_login "$PW_VER" "SET ROLE programacion_auditor"
expect N_auditor_cannot_become_verifier 'ERR:.*permission denied' lf_pg01_auditor_login "$PW_AUD" "SET ROLE programacion_verifier"
expect N_auditor_cannot_verify 'ERR:.*permission denied' lf_pg01_auditor_login "$PW_AUD" "BEGIN; SET LOCAL ROLE programacion_auditor; $V('11111111-0000-4000-8000-000000000001',$C1); COMMIT;"
expect N_service_role_set_verifier 'ERR:.*permission denied' authenticator "$PW_AUTH" "SET ROLE service_role; SET ROLE programacion_verifier"
expect N_service_role_impersonate_login 'ERR:.*permission denied' authenticator "$PW_AUTH" "SET ROLE service_role; SET SESSION AUTHORIZATION lf_pg01_verifier_login"
expect N_postgres_chain_impersonation 'ERR:.*(permission denied|shared/control-plane session principal postgres)' postgres "$PW_PG" \
 "GRANT lf_pg01_verifier_login TO postgres WITH SET TRUE; BEGIN; SET LOCAL ROLE lf_pg01_verifier_login; SET LOCAL ROLE programacion_verifier; $V('11111111-0000-4000-8000-000000000001',$C1); COMMIT;"
AS postgres "$PW_PG" -c "REVOKE lf_pg01_verifier_login FROM postgres" >/dev/null 2>&1 || true
expect N_subject_mismatch 'ERR:.*PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH' lf_pg01_verifier_login "$PW_VER" "$(VER 2)"
expect N_hash_mismatch 'ERR:.*PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH' lf_pg01_verifier_login "$PW_VER" "$(VER 3)"
expect N_head_invalid 'ERR:.*PG01_SUBJECT_VERIFY_HEAD_INVALID' lf_pg01_verifier_login "$PW_VER" "$(VER 4)"
expect N_producer_not_independent 'ERR:.*PG01_SUBJECT_VERIFY_ANCHORED_BY_PRODUCER' lf_pg01_verifier_login "$PW_VER" "$(VER 5)"
expect N_receipt_missing 'ERR:.*PG01_SUBJECT_VERIFY_RECEIPT_MISSING' lf_pg01_verifier_login "$PW_VER" "$(VER 9)"

echo "== GREEN 1: verifier session =="
expect G1_verify_ok '^OK' lf_pg01_verifier_login "$PW_VER" "$(VER 1)"
expect G1_readback '^OK:lf_pg01_verifier_login\|programacion_verifier\|LF_SUPABASE_READBACK_V1 *$' lf_pg01_verifier_login "$PW_VER" \
 "BEGIN; SET LOCAL ROLE programacion_verifier; SELECT session_principal||'|'||authority_role||'|'||resolver_id FROM private.lf_pg01_subject_verifications_v1; COMMIT;"
expect N_replay_verification 'ERR:.*duplicate key' lf_pg01_verifier_login "$PW_VER" "$(VER 1)"
expect N_update_verification 'ERR:.*permission denied' lf_pg01_verifier_login "$PW_VER" "BEGIN; SET LOCAL ROLE programacion_verifier; UPDATE private.lf_pg01_subject_verifications_v1 SET source_head_sha=repeat('2',40); COMMIT;"

echo "== verifier == auditor attacks (role swap by admin) =="
AS postgres "$PW_PG" -c "GRANT programacion_auditor TO lf_pg01_verifier_login WITH ADMIN FALSE, INHERIT FALSE, SET TRUE" >/dev/null
expect N_same_login_dual_authority 'ERR:.*cross-authority membership' lf_pg01_verifier_login "$PW_VER" "$(ATT J1)"
AS postgres "$PW_PG" -c "REVOKE programacion_verifier FROM lf_pg01_verifier_login" >/dev/null
expect N_same_principal_as_verifier 'ERR:.*PG01_REVIEW_ATTEST_SAME_PRINCIPAL_AS_VERIFIER' lf_pg01_verifier_login "$PW_VER" "$(ATT J1)"
AS postgres "$PW_PG" -c "REVOKE programacion_auditor FROM lf_pg01_verifier_login; GRANT programacion_verifier TO lf_pg01_verifier_login WITH ADMIN FALSE, INHERIT FALSE, SET TRUE" >/dev/null

echo "== auditor negatives + GREEN 2 =="
expect N_judge_not_completed 'ERR:.*PG01_REVIEW_ATTEST_JUDGE_INVALID' lf_pg01_auditor_login "$PW_AUD" "$(ATT J2)"
expect N_judge_head_mismatch 'ERR:.*PG01_REVIEW_ATTEST_SUBJECT_NOT_VERIFIED' lf_pg01_auditor_login "$PW_AUD" "$(ATT J4)"
expect N_judge_unknown 'ERR:.*PG01_REVIEW_ATTEST_JUDGE_INVALID' lf_pg01_auditor_login "$PW_AUD" "$(ATT NOPE)"
expect G2_attest_ok '^OK' lf_pg01_auditor_login "$PW_AUD" "$(ATT J1)"
expect N_replay_attestation 'ERR:.*duplicate key' lf_pg01_auditor_login "$PW_AUD" "$(ATT J1)"
# readback via the disposable superuser: by design neither postgres nor service_role can read attestations
SU -Atc "SELECT session_principal||'|'||verifier_session_principal||'|'||producer_execution_id||'|'||(manifest_sha256=private.fn_lf_pg01_judge_digest_v1('J1')->>'manifest_sha256') FROM private.lf_pg01_review_attestations_v1" > "$WORK/rb.txt"
if [[ "$(cat "$WORK/rb.txt")" == "lf_pg01_auditor_login|lf_pg01_verifier_login|PROFILE|true" ]]; then
  PASS=$((PASS+1)); echo "PASS G2_readback_two_principals (superuser readback)" | tee -a "$LOG"
else FAIL=$((FAIL+1)); echo "FAIL G2_readback_two_principals :: $(cat "$WORK/rb.txt")" | tee -a "$LOG"; fi
expect N_service_role_read_attestations 'ERR:.*permission denied' authenticator "$PW_AUTH" "SET ROLE service_role; SELECT 1 FROM private.lf_pg01_review_attestations_v1"

echo "== RESIDUAL trust boundary (documented, expected to SUCCEED; see PROG-ADR-AUTH-001) =="
# postgres holds ADMIN on the logins (implicit creator grant, same as lf_runtime_readback_oidc_writer),
# so whoever holds the postgres credential can rotate a login secret and then act as that login.
PW_STOLEN=$(rnd)
expect RESIDUAL_postgres_can_rotate_login_secret '^OK' postgres "$PW_PG" "ALTER ROLE lf_pg01_auditor_login PASSWORD '$PW_STOLEN'"
expect RESIDUAL_rotated_secret_authenticates '^OK:lf_pg01_auditor_login *$' lf_pg01_auditor_login "$PW_STOLEN" "select session_user"

TOTAL=$((PASS+FAIL))
echo "SERVER_VERSION=$VERSION PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ $FAIL -eq 0 ]] && echo "PG01_EXTERNAL_AUTHORITY_LOGINS_TESTS_PASSED:$PASS" || { echo "TEST_FAIL"; exit 1; }
