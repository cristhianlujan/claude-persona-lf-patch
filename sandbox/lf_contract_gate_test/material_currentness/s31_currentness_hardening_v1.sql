-- S31 CURRENTNESS_AUTHORITY hardening candidate.
-- Backlog: public.lf_audit_backlog ids 58,59.
-- Scope: source-only / rollback-only until independent review and exact-head CI.
-- No durable DB change, runtime, production, Golden, or capability-version mutation is authorized by this file.

create or replace function public.lf_currentness_material_prewrite_guard_v1(
  p_currentness_receipt jsonb,
  p_migration_source_authority jsonb,
  p_write_context jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, public
as $function$
declare
  v_decision text := coalesce(p_currentness_receipt->>'decision','');
  v_ready text := coalesce(p_currentness_receipt->>'ready','');
  v_completeness text := coalesce(p_currentness_receipt->>'dependency_completeness','');
  v_authority_ref text := coalesce(p_currentness_receipt->>'authority_ref','');
  v_current_revision text := coalesce(p_currentness_receipt->>'current_revision','');
  v_receipt_sha text := coalesce(p_currentness_receipt->>'receipt_sha256','');
  v_expected_authority_ref text := coalesce(p_write_context->>'authority_ref','');
  v_effective_revision text := coalesce(p_write_context->>'effective_revision','');
  v_target_ref text := coalesce(p_write_context->>'target_ref','');
  v_operation_kind text := coalesce(p_write_context->>'operation_kind','');
  v_migration_version text := coalesce(p_write_context->>'migration_version','');
  v_dep_kind text := coalesce(p_migration_source_authority->>'kind','');
  v_dep_provider text := coalesce(p_migration_source_authority->>'provider','');
  v_dep_state text := coalesce(p_migration_source_authority->>'state','');
  v_dep_sha text := coalesce(p_migration_source_authority->>'evidence_sha256','');
  v_existing_exact text := coalesce(p_migration_source_authority->>'existing_exact_parity','');
  v_remote_ahead text := coalesce(p_migration_source_authority->>'remote_ahead','');
  v_pending_count_text text := coalesce(p_migration_source_authority->>'pending_count','');
  v_pending_count integer;
  v_pending_version text := coalesce(p_migration_source_authority->>'pending_version','');
  v_source_first_allowed boolean := false;
begin
  if p_currentness_receipt is null or jsonb_typeof(p_currentness_receipt) <> 'object'
     or p_migration_source_authority is null or jsonb_typeof(p_migration_source_authority) <> 'object'
     or p_write_context is null or jsonb_typeof(p_write_context) <> 'object' then
    return jsonb_build_object(
      'schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1',
      'decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','INPUT_ENVELOPE_INVALID'
    );
  end if;

  if coalesce(p_currentness_receipt->>'authority_layer','') <> 'CURRENTNESS_AUTHORITY' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','CURRENTNESS_AUTHORITY_LAYER_INVALID');
  end if;

  if v_decision = 'STALE_AFFECTED' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','STALE_AFFECTED','ready',false,'reason','UPSTREAM_STALE_AFFECTED');
  end if;

  if v_decision = 'UNKNOWN_FAIL_CLOSED' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','UPSTREAM_UNKNOWN_FAIL_CLOSED');
  end if;

  if v_decision not in ('CURRENT','CURRENT_REBOUND') or v_ready <> 'true' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','CURRENTNESS_RECEIPT_NOT_READY');
  end if;

  if v_completeness <> 'COMPLETE' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','DEPENDENCY_COMPLETENESS_NOT_COMPLETE');
  end if;

  if v_receipt_sha !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','CURRENTNESS_RECEIPT_SHA_INVALID');
  end if;

  if v_expected_authority_ref = '' or v_authority_ref <> v_expected_authority_ref then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','AUTHORITY_REF_MISMATCH');
  end if;

  if v_effective_revision !~ '^[0-9a-f]{40}$' or v_current_revision <> v_effective_revision then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','EFFECTIVE_REVISION_MISMATCH');
  end if;

  if v_target_ref = '' or v_operation_kind not in ('MATERIAL_WRITE','MIGRATION_APPLY') then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','WRITE_CONTEXT_INVALID');
  end if;

  if v_dep_kind <> 'MIGRATION_SOURCE_AUTHORITY'
     or v_dep_provider <> 'LF_MIGRATION_SOURCE_PARITY'
     or v_dep_sha !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','MIGRATION_SOURCE_AUTHORITY_EVIDENCE_INVALID');
  end if;

  if v_pending_count_text !~ '^[0-9]+$' then
    return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','MIGRATION_PENDING_COUNT_INVALID');
  end if;
  v_pending_count := v_pending_count_text::integer;

  if v_dep_state = 'EXACT' then
    if v_existing_exact <> 'true' or v_remote_ahead <> 'false' or v_pending_count <> 0 or v_pending_version <> '' then
      return jsonb_build_object('schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1','decision','UNKNOWN_FAIL_CLOSED','ready',false,'reason','MIGRATION_EXACT_EVIDENCE_INCONSISTENT');
    end if;
  elsif v_dep_state = 'SOURCE_FIRST_PENDING' then
    v_source_first_allowed :=
      v_operation_kind = 'MIGRATION_APPLY'
      and v_existing_exact = 'true'
      and v_remote_ahead = 'false'
      and v_pending_count = 1
      and v_migration_version ~ '^20[0-9]{12}$'
      and v_pending_version = v_migration_version
      and v_target_ref = ('supabase/migrations/' || v_migration_version);

    if not v_source_first_allowed then
      return jsonb_build_object(
        'schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1',
        'decision','UNKNOWN_FAIL_CLOSED','ready',false,
        'reason','SOURCE_FIRST_PENDING_NOT_EXACT_APPLY_TARGET'
      );
    end if;
  else
    return jsonb_build_object(
      'schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1',
      'decision','UNKNOWN_FAIL_CLOSED','ready',false,
      'reason',case
        when v_dep_state = 'REMOTE_ONLY' then 'MIGRATION_LEDGER_AHEAD_OF_CANONICAL_SOURCE'
        when v_dep_state = 'MIXED' then 'MIGRATION_SOURCE_AUTHORITY_MIXED'
        else 'MIGRATION_SOURCE_AUTHORITY_UNKNOWN'
      end
    );
  end if;

  return jsonb_build_object(
    'schema_version','LF_CURRENTNESS_MATERIAL_PREWRITE_GUARD_V1',
    'authority_layer','CURRENTNESS_AUTHORITY',
    'decision',v_decision,
    'ready',true,
    'dependency_completeness','COMPLETE',
    'dependency_authority_state',v_dep_state,
    'source_first_exact_apply',v_source_first_allowed,
    'authority_ref',v_authority_ref,
    'effective_revision',v_effective_revision,
    'target_ref',v_target_ref,
    'operation_kind',v_operation_kind,
    'currentness_receipt_sha256',v_receipt_sha,
    'migration_source_authority_sha256',v_dep_sha
  );
end;
$function$;

revoke all on function public.lf_currentness_material_prewrite_guard_v1(jsonb,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.lf_currentness_material_prewrite_guard_v1(jsonb,jsonb,jsonb) to service_role;
