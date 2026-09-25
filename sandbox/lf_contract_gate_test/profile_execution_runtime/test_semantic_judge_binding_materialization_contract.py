#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260925031500_lf_profile_runtime_semantic_judge_binding_materialization_v1.sql"

sql = MIGRATION.read_text(encoding="utf-8")
low = sql.lower()

# One bounded solution: extend the existing PR #1016 freeze point only.
assert sql.count("create or replace function private.fn_lf_profile_runtime_freeze_router_envelope_v1()") == 1
assert "create or replace function public.lf_profile_execution_begin_v1" not in low
assert "create table" not in low
assert "insert into public.lf_activos" not in low
assert "update public.lf_activos" not in low
assert "update public.lf_operation_execution" not in low

# ACT-0001 remains the only resolver; no second Router/resolver is introduced.
assert sql.count("v_route := public.lf_router_resolve_v1(") == 1
assert "'router','act-0001'" in low
assert "'activation_source','router'" in low
assert "'operation_code','ejecucion_perfil_lf'" in low

# The semantic judge configuration is profile-owned and frozen in the existing
# LF_PROFILE_EXECUTION_BINDING_V1 carried by the immutable Router envelope.
for token in (
    "metadata->'semantic_judge_binding'",
    "lf_profile_semantic_judge_binding_v1",
    "semantic_judge_binding_state",
    "semantic_judge_binding_sha256",
    "semantic_judge_binding_ref",
    "semantic_judge_binding_target_code",
    "profile_execution_binding",
):
    assert token in low, token

# Profiles without a configured binding remain compatible until their own
# governed binding PR is applied; configured bindings fail closed on shape/path.
assert "'not_configured'" in low
assert "'configured'" in low
assert "hetzner_router_semantic_judge_binding_invalid" in low
assert "hetzner_router_semantic_judge_binding_path_invalid" in low

# Digest reuses the existing canonical JSON authority used elsewhere in LF.
assert "private.fn_payload_sha256_v7(v_semantic_judge_binding)" in low
assert "sha256:" in low
assert "supabase://public/lf_activos/" in low

# Target binding is exact to the Router-selected profile, not a runtime choice.
assert "case when v_semantic_judge_binding_state='configured' then new.profile_code else null end" in low
assert "router_execution_envelope#>>'{profile_execution_binding,semantic_judge_binding_target_code}'=profile_code" in low

# This PR intentionally does not implement the #1013 five-field top-level
# compatibility projection or populate V0.3/V0.6 bindings.
assert "lf_profile_execution_begin_v1" not in low
assert "perfil-systemic-root-cause-repair-lf" not in low
assert "systemic_root_cause_repair_lf_v0_6" not in low

print("SEMANTIC_JUDGE_BINDING_MATERIALIZATION_CONTRACT_PASS")
