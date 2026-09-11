#!/usr/bin/env bash
set -euo pipefail

: "${PGPASSWORD:?LF_SUPABASE_DB_PASSWORD must be mapped to PGPASSWORD}"
: "${SUPABASE_PROJECT_ID:=mhwmirqcgxxukpctffuv}"
: "${SUPABASE_POOLER_HOST:=aws-1-us-east-1.pooler.supabase.com}"
: "${S26_EXECUTION_ID:=EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-SEMANTIC-REPROJECTION-20260911-001}"
: "${S26_EXPECTED_TARGET_CODE:=PERFIL-UI-ARCHITECT}"
: "${S26_EXPECTED_TARGET_PATH:=profiles/ui_architect/SKILL.md}"
: "${S26_EXPECTED_NEXT_STEP:=pre_write_execution_binding_gate}"

export PGHOST="$SUPABASE_POOLER_HOST"
export PGPORT=5432
export PGUSER="postgres.${SUPABASE_PROJECT_ID}"
export PGDATABASE=postgres
export PGSSLMODE=require
export PGCONNECT_TIMEOUT=15

command -v psql >/dev/null 2>&1 || { echo 'BLOCK_S26_DB_PREFLIGHT_PSQL_MISSING' >&2; exit 2; }

psql_base=(psql -X -v ON_ERROR_STOP=1 -Atq)

query() {
  "${psql_base[@]}" -c "BEGIN READ ONLY; $1; COMMIT;" | sed '/^BEGIN$/d;/^COMMIT$/d'
}

identity="$(query "select concat_ws('|',execution_id,operation_code,target_type,target_code,target_repo,target_path,status) from public.lf_operation_execution where execution_id='${S26_EXECUTION_ID}'")"
expected_prefix="${S26_EXECUTION_ID}|ACTUALIZACION_PERFIL_LF|PERFIL|${S26_EXPECTED_TARGET_CODE}|cristhianlujan/claude-persona-lf-patch|${S26_EXPECTED_TARGET_PATH}|"
[[ "$identity" == "$expected_prefix"* ]] || { echo "BLOCK_S26_DB_PREFLIGHT_EXECUTION_IDENTITY observed=${identity}" >&2; exit 3; }

next_step="$(query "select s.step_id from public.lf_operation_steps s where s.operation_code='ACTUALIZACION_PERFIL_LF' and s.active=true and s.required=true and not exists (select 1 from public.lf_operation_execution_steps e where e.execution_id='${S26_EXECUTION_ID}' and e.step_id=s.step_id) order by s.execution_order asc limit 1")"
[[ "$next_step" == "$S26_EXPECTED_NEXT_STEP" ]] || { echo "BLOCK_S26_DB_PREFLIGHT_NEXT_STEP expected=${S26_EXPECTED_NEXT_STEP} observed=${next_step}" >&2; exit 4; }

record_fn="$(query "select coalesce(to_regprocedure('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)')::text,'')")"
[[ -n "$record_fn" ]] || { echo 'BLOCK_S26_DB_PREFLIGHT_RECORD_FUNCTION_MISSING' >&2; exit 5; }

router_fn="$(query "select coalesce(to_regprocedure('public.lf_router_resolve_v1(text,text,text,text,text)')::text,'')")"
[[ -n "$router_fn" ]] || { echo 'BLOCK_S26_DB_PREFLIGHT_ROUTER_FUNCTION_MISSING' >&2; exit 6; }

required_keys="$(query "select coalesce((select string_agg(value,',' order by ord) from jsonb_array_elements_text(required_evidence_keys) with ordinality as x(value,ord)),'') from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_PERFIL_LF' and step_id='${S26_EXPECTED_NEXT_STEP}' and status='ACTIVE_ENFORCEMENT' limit 1")"
for key in execution_id target_code target_path write_plan pre_write_gate_passed bound_revision execution_bound_to_target_before_change; do
  [[ ",${required_keys}," == *",${key},"* ]] || { echo "BLOCK_S26_DB_PREFLIGHT_REQUIRED_KEY_MISSING key=${key} observed=${required_keys}" >&2; exit 7; }
done

recorded_count="$(query "select count(*) from public.lf_operation_execution_steps where execution_id='${S26_EXECUTION_ID}'")"
[[ "$recorded_count" =~ ^[0-9]+$ ]] || { echo 'BLOCK_S26_DB_PREFLIGHT_STEP_COUNT_INVALID' >&2; exit 8; }

printf '{"status":"PASS","transport":"POSTGRES_POOLER_DIRECT","read_only":true,"execution_id":"%s","recorded_step_count":%s,"next_step":"%s","record_function":"%s","router_function":"%s"}\n' \
  "$S26_EXECUTION_ID" "$recorded_count" "$next_step" "$record_fn" "$router_fn"
