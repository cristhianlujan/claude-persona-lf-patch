from pathlib import Path

SQL = Path(__file__).with_name('transversal_validation_spine_candidate.sql').read_text()
LOWER = SQL.lower()

# Reuse-first / no new architecture.
for forbidden in (
    'create table',
    'create schema',
    "insert into public.lf_operation_registry",
    "insert into public.lf_router_action_registry",
):
    assert forbidden not in LOWER, f'forbidden new layer: {forbidden}'

# Must extend the canonical Strategy executor and EKB, not invent authority.
required = (
    'public.lf_strategy_execution_ekb_preflight_v1',
    "x.operation_code<>'EJECUCION_ESTRATEGIA_LF'",
    'transversal.prevention_rules',
    'transversal.error_knowledge',
    'PRV-GOV-010',
    'LF_STRATEGY_EKB_PREFLIGHT_HIGH_CRITICAL_UNCONTROLLED',
    'EKB_PREFLIGHT_ACTIVE_RULES_BOUND_TO_CONTROLS',
    'policy_and_quality_resolve',
    'pre_write_execution_binding_gate',
)
for token in required:
    assert token in SQL, f'missing required token: {token}'

# Fail closed on missing/unknown rules and unbound critical prevention.
for token in (
    'LF_STRATEGY_EKB_PREFLIGHT_APPLICABLE_RULES_REQUIRED',
    'LF_STRATEGY_EKB_PREFLIGHT_RULE_NOT_ACTIVE_OR_MISSING',
    'LF_STRATEGY_EKB_PREFLIGHT_HIGH_CRITICAL_UNCONTROLLED',
):
    assert token in SQL

# Do not misuse heterogeneous priority as severity.
assert 'Priority is not treated as severity' in SQL
assert "upper(coalesce(e.severidad,''))" in SQL

# No direct EKB write authority in preflight.
assert 'insert into transversal.error_knowledge' not in LOWER
assert 'insert into transversal.prevention_rules' not in LOWER
assert 'lf_write_pipeline_ekb_v1' not in SQL

print('PASS_TRANSVERSAL_VALIDATION_SPINE_CANDIDATE')
