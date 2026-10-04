-- PASE-ATOM-F07-008 exact semantic rollback.
-- Restores the pre-repair entry_contract projection for the exact 12 rows observed
-- before the repair. Registry/current/operational state is never changed.
-- Audit timestamps intentionally advance; immutable evidence/history is preserved.

DO $rollback$
DECLARE
  v_apply_exec constant text := 'CHATGPT-PASE-F07-008-COHERENCE-REPAIR-20261004';
  v_rollback_exec constant text := 'CHATGPT-PASE-F07-008-COHERENCE-ROLLBACK-20261004';
  v_snapshot jsonb := $json$
  {
    "ASSURANCE_EVALUATOR":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"DECLARED_DEFERRED_UNTIL_PASE_F06_F09_F10_PLUS_EXPLICIT_HUMAN_GO","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK","required_entrypoint_signature":"public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text)"},
    "AUTHORITY_READBACK":{"owner":"LF_GOVERNANCE","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENFORCED","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "EVIDENCE_ANTIREPLAY":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENTRY_ENFORCED_NOT_CURRENT","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "EVIDENCE_LEDGER":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENTRY_ENFORCED_NOT_CURRENT","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "EVIDENCE_RESOLVER_REGISTRY":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENFORCED","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "GITHUB_RECONCILIATION":{"owner":"LF_GOVERNANCE","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENFORCED","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "MIGRATION_ORCHESTRATED_SAGA_V1":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENTRY_ENFORCED_NOT_CURRENT","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","updated_by_execution_id":"EXEC-SADM-MIGRATION-SAGA-REGISTRY-CUTOVER-20260930","direct_new_binding_policy":"BLOCK"},
    "MIGRATION_SOURCE_RECONCILIATION_V1":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENTRY_ENFORCED_NOT_CURRENT","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","updated_by_execution_id":"EXEC-SADM-MIGRATION-SOURCE-RECONCILIATION-REGISTRY-CUTOVER-20260930","direct_new_binding_policy":"BLOCK"},
    "MIGRATION_WRITE_AHEAD_V1":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENTRY_ENFORCED_NOT_CURRENT","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","updated_by_execution_id":"EXEC-SADM-MIGRATION-WRITE-AHEAD-REGISTRY-CUTOVER-20260930","direct_new_binding_policy":"BLOCK"},
    "PLAN_AUTHORITY_DRIFT_GUARD":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","guard_function":"public.fn_lf_capability_orchestrator_entry_guard_v1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"SOURCE_READY_NOT_REGISTERED","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "RUNTIME_DEPLOY_VERIFICATION":{"owner":"LF_GOVERNANCE","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENFORCED","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"},
    "TYPED_EVIDENCE_REGISTRY":{"owner":"SUPER_ADMIN","required":true,"guard_code":"ORCHESTRATOR_EXECUTION_GUARD_V1","schema_version":"LF_CAPABILITY_ENTRY_CONTRACT_V1","enforcement_state":"ENFORCED","required_entrypoint":"public.fn_lf_capability_bind_from_orchestrator_v1","direct_new_binding_policy":"BLOCK"}
  }
  $json$::jsonb;
  v_expected integer;
  v_ready integer;
  v_updated integer;
BEGIN
  v_expected := jsonb_object_length(v_snapshot);

  SELECT count(*) INTO v_ready
  FROM public.lf_activos a
  JOIN LATERAL jsonb_object_keys(v_snapshot) k(code) ON k.code=a.codigo_activo
  WHERE a.archived_at IS NULL
    AND a.updated_by_execution_id=v_apply_exec;

  IF v_ready <> v_expected THEN
    RAISE EXCEPTION 'BLOCK_F07_008_ROLLBACK_CURRENTNESS:%/%',v_ready,v_expected;
  END IF;

  WITH restored AS (
    UPDATE public.lf_activos a
    SET metadata=jsonb_set(a.metadata,'{entry_contract}',v_snapshot->a.codigo_activo,true),
        updated_by_execution_id=v_rollback_exec
    WHERE a.archived_at IS NULL
      AND a.updated_by_execution_id=v_apply_exec
      AND v_snapshot ? a.codigo_activo
    RETURNING a.codigo_activo
  )
  SELECT count(*) INTO v_updated FROM restored;

  IF v_updated <> v_expected THEN
    RAISE EXCEPTION 'BLOCK_F07_008_ROLLBACK_CARDINALITY:%/%',v_updated,v_expected;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_activos a
    JOIN LATERAL jsonb_object_keys(v_snapshot) k(code) ON k.code=a.codigo_activo
    WHERE a.archived_at IS NULL
      AND a.metadata->'entry_contract' IS DISTINCT FROM v_snapshot->a.codigo_activo
  ) THEN
    RAISE EXCEPTION 'BLOCK_F07_008_ROLLBACK_READBACK';
  END IF;
END
$rollback$;
