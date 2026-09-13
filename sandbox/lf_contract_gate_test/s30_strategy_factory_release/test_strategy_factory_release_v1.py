#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / 'gobernanza/contratos/contrato_estrategia_lf.yaml'
JUDGE = ROOT / 'gobernanza/judges/judge_contrato_estrategia_lf.yaml'
VALIDATOR = ROOT / 'gobernanza/judges/validate_strategy_contract_v032.py'
BASE_VALIDATOR = ROOT / 'gobernanza/judges/validate_strategy_contract.py'
CORE = ROOT / 'gobernanza/procedimientos/creacion_estrategia_lf_steps_core.yaml'
VALIDATION = ROOT / 'gobernanza/procedimientos/creacion_estrategia_lf_steps_validation.yaml'
MATRIX = ROOT / 'gobernanza/repositorios/matriz_repos_lf.yaml'
MIGRATION = ROOT / 'supabase/migrations/20260913035500_s30_strategy_factory_release_v1.sql'
CANARY = Path(__file__).with_name('strategy_factory_release_canary_v1.sql')

for path in (CONTRACT,JUDGE,VALIDATOR,BASE_VALIDATOR,CORE,VALIDATION,MATRIX,MIGRATION,CANARY):
    assert path.is_file(), path

contract = CONTRACT.read_text(encoding='utf-8')
judge = JUDGE.read_text(encoding='utf-8')
matrix = MATRIX.read_text(encoding='utf-8')
migration = MIGRATION.read_text(encoding='utf-8')
canary = CANARY.read_text(encoding='utf-8')

# Releasing the factory must never raise the artifact/runtime/impact ceiling.
for token in ('status: CANDIDATO_READ_ONLY','runtime_state: PLAN_ONLY','automatic_impact: BLOQUEADO'):
    assert token in contract, token
assert 'enable_runtime' in contract
assert 'automatic_production_promotion' in contract
assert 'enable_automatic_impact' in judge

# Repository authorization is narrow and operation-bound.
assert '- /strategies/' in matrix
assert 'required_operation: CREACION_ESTRATEGIA_LF' in matrix
assert 'status_ceiling: CANDIDATO_READ_ONLY' in matrix
assert 'runtime_state_ceiling: PLAN_ONLY' in matrix
assert 'impact_policy_ceiling: BLOQUEADO' in matrix
assert 'automatic_main_or_production_promotion: false' in matrix

# Runtime activation is an explicit status promotion of the already-governed control plane.
for token in (
    "policy_code='POL-STRATEGY-CREATION-001'",
    "status='ACTIVE'",
    "status='ACTIVE_ENFORCEMENT'",
    "status='PRODUCCION_CONTROLADA_READ_ONLY'",
    "v_count <> 43",
    "v_required <> 5 or v_resolved <> 4",
    "strategy_status'='CANDIDATO_READ_ONLY'",
    "runtime_state'='PLAN_ONLY'",
    "automatic_impact'='BLOQUEADO'",
):
    assert token in migration, token

# Read-only canary must prove Router readiness and the unchanged safety ceiling.
for token in (
    "READY_TO_EXECUTE",
    "CREACION_ESTRATEGIA_LF",
    "active_step_contracts=43",
    "active_judges=43",
    "active_bindings=43",
    "strategy_status_ceiling",
    "runtime_state_ceiling",
    "automatic_impact_ceiling",
    "release_pass",
):
    assert token in canary, token

print('S30_STRATEGY_FACTORY_RELEASE_V1_PASS')
