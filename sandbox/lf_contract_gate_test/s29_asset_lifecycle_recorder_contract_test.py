from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "gobernanza/procedimientos/lf_asset_lifecycle_operation_recorder_v1.sql"
text = SRC.read_text(encoding="utf-8")

checks = {
    "source_only_marker": "SOURCE_ONLY / NOT_DEPLOYED / CANDIDATE_READ_ONLY" in text,
    "security_invoker": "security invoker" in text.lower(),
    "scope_card_update": "ACTUALIZACION_CARD_LF" in text,
    "scope_retire": "RETIRO_ACTIVO_LF" in text,
    "no_strategy_retire": "v_execution.target_type not in ('PERFIL','CARD','ADAPTER','SKILL')" in text,
    "active_step_contract_required": "status = 'ACTIVE_ENFORCEMENT'" in text,
    "active_binding_required": "status = 'ACTIVE_ENFORCEMENT'" in text,
    "card_manifest_trust": "v_execution.manifest->'connector_trust_context'" in text,
    "card_revision_compare": "p_evidence_payload->>'carrier_revision' <> v_trust->>'revision_id'" in text,
    "card_identity_compare": "p_evidence_payload->>'card_code' <> v_execution.target_code" in text,
    "card_provider_guard": "v_trust->>'provider_guard' <> 'requiredRevisionId'" in text,
    "retire_server_asset_read": "from public.lf_activos" in text,
    "retire_server_relation_read": "from public.lf_activo_relaciones r" in text,
    "retire_unarchived_source_guard": "source_asset.archived_at is null" in text,
    "retire_server_count_compare": "RETIRE_SERVER_CONSUMER_COUNT_MISMATCH" in text,
    "retire_active_consumer_block": "RETIRE_SERVER_ACTIVE_INCOMING_CONSUMER" in text,
    "durable_blocked_attempt": "attempt_history" in text and "retry remains allowed" in text,
    "no_hard_delete": "delete from public.lf_activos" not in text.lower(),
    "no_archive_business_write": "update public.lf_activos" not in text.lower(),
    "no_router_write": "lf_router_action_registry" not in text,
    "public_revoked": "revoke all on function public.lf_record_asset_lifecycle_step_v1" in text,
    "service_role_only": "grant execute on function public.lf_record_asset_lifecycle_step_v1" in text and "to service_role" in text,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")

if failed:
    print("FAILED_CHECKS=" + ",".join(failed))
    sys.exit(1)

print(f"PASS_S29_ASSET_LIFECYCLE_RECORDER_SOURCE_CONTRACT={len(checks)}/{len(checks)}")
