#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260918054000_lf_s30_operation_policy_context_admission_v1.sql"
SQL = MIGRATION.read_text(encoding="utf-8")

REQUIRED = [
    "POL-LF-POLICY-CONSUMPTION",
    "v1.2-context-admission",
    "lf-context-admission/v1",
    "TRANSVERSAL_BASE_SET_V1",
    "WRITE_MUTATION_SET_V1",
    "DB_MIGRATION_SET_V1",
    "REPOSITORY_CI_SET_V1",
    "HIGH_ASSURANCE_SET_V1",
    "STRATEGY_EXECUTION_SET_V1",
    "CURRENTNESS_AUTHORITY",
    "OPERATION_MATERIALIZATION_GUARD",
    "PRE_EKB_GATE",
    "GATE_CHECK_OBSERVABILITY",
    "EXECUTION_EVENT_READBACK_INDEX",
    "DB_WRITE_TRANSPORT",
    "MIGRATION_SOURCE_PARITY",
    "SCHEMA_FINGERPRINT_GUARD",
    "CI_FAST_DEEP_LANE_ROUTER",
    "REPOSITORY_GOVERNANCE_BUNDLE",
    "ASSURANCE_COMPLETENESS",
    "QUALIFICATION_FRAMEWORK",
    "QUALIFICATION_RECEIPTS",
    "INDEPENDENT_ASSURANCE",
    "EVIDENCE_RESOLVER_REGISTRY",
    "C05_GENERIC_EXECUTION_RELIABILITY",
    "fn_lf_router_preflight_v1",
    "limit v_ekb_limit",
    "ROUTER_CONTEXT_ADMISSION_V1",
    "private.lf_context_budget_events_v2",
    "UTF8_BYTES_DIV_4",
    "BLOCK_CONTEXT_BUDGET_HARD_LIMIT",
]
for token in REQUIRED:
    assert token in SQL, f"MISSING_CONTEXT_ADMISSION_TOKEN:{token}"

# The model-facing receipt must be references/identities, not hydrated policy/EKB documents.
assert "'policy_payloads',false" in SQL
assert "'full_ekb_entries',false" in SQL
assert "'full_readmes',false" in SQL
assert "'jit_only',true" in SQL
assert "'detail_mode','JIT_BY_CODE'" in SQL
assert "'max_items',12" in SQL
assert "'soft_limit_tokens',1500" in SQL
assert "'hard_limit_tokens',3000" in SQL

# Regression for the old overfetch: do not put prevention/validation/full evidence
# into the compact EKB item delivered by preflight.
compact_item_start = SQL.index("jsonb_build_object(\n        'codigo',k.codigo")
compact_item_end = SQL.index(") as item", compact_item_start)
compact_item = SQL[compact_item_start:compact_item_end]
for forbidden in ("prevencion", "validacion", "evidencia", "descripcion", "causa_raiz"):
    assert forbidden not in compact_item, f"EKB_COMPACT_ITEM_OVERFETCH:{forbidden}"

# Policy payloads stay in Supabase; runtime gets stable identity + SHA only.
policy_item_start = SQL.index("jsonb_build_object(\n           'policy_code',p.policy_code")
policy_item_end = SQL.index(") order by p.policy_role", policy_item_start)
policy_item = SQL[policy_item_start:policy_item_end]
assert "policy_payload" not in policy_item
for required_field in ("policy_code", "policy_version", "policy_sha", "policy_role", "required"):
    assert required_field in policy_item

# No optional set is sent blindly: each one carries applies_when and is evaluated
# outside the LLM using execution/operation facts.
assert SQL.count("'applies_when',jsonb_build_object(") == 5
for selector in (
    "target_types",
    "operation_families",
    "operation_domains",
    "operation_types",
    "requires_target_repo",
    "risk_classes",
):
    assert selector in SQL, f"APPLICABILITY_SELECTOR_MISSING:{selector}"

# The existing budget ledger is reused; no new budget/context table is created.
assert "create table" not in SQL.lower()
assert "create or replace function public.fn_lf_router_preflight_v1" in SQL
assert "insert into private.lf_context_budget_events_v2" in SQL

# The generic policy resolver remains data-driven, not a copied four-code whitelist.
generic_section = SQL[SQL.index("generic_policies as ("):SQL.index("expected as (")]
assert "tipo_activo='REGLA'" in generic_section
assert "nivel_control='TRANSVERSAL'" in generic_section
assert "router_required" in generic_section

print("S30_CONTEXT_ADMISSION_V1_CONTRACT_PASS")
