# LF Transversal Assets — README Contract

Este índice existe para que cualquier agente o proceso pueda resolver una capability transversal antes de reinventarla.

## Regla de consumo

1. Consultar `public.lf_activos` y seleccionar el activo transversal vigente.
2. Abrir el `documentation.readme_ref`. Si falta, bloquear: un activo transversal activo sin README indexado no cumple el contrato de activación.
3. Seguir `Cómo consumirlo`, las superficies canónicas y los límites fail-closed.
4. No duplicar la capability.
5. Si cambia el contrato o la superficie canónica, actualizar README + inventario en el mismo cierre gobernado.

## Regla de activación

Todo activo transversal documentable en estado `ACTIVE_SHARED_ENFORCEMENT` o `ACTIVE_TRANSVERSAL_POLICY` debe tener un README consumible **y** `metadata.transversal_inventory.documentation.readme_ref` no vacío. `Validate LF Packs` verifica ambas obligaciones contra el inventario vivo.

## Activos

- `ACT-0001` — `DOC_ROUTER_OPERATIVO_GOBERNANZA_LF` → `sandbox/lf_contract_gate_test/transversal_assets/act_0001/README.md`
- `ASSURANCE_COMPLETENESS` — `TRANSVERSAL_ASSURANCE_COMPLETENESS` → `sandbox/lf_contract_gate_test/transversal_assets/assurance_completeness/README.md`
- `C05_GENERIC_EXECUTION_RELIABILITY` — `TRANSVERSAL_C05_GENERIC_EXECUTION_RELIABILITY` → `sandbox/lf_contract_gate_test/transversal_assets/c05_generic_execution_reliability/README.md`
- `CAPABILITY_VERSION_COMPATIBILITY` — `TRANSVERSAL_CAPABILITY_VERSION_COMPATIBILITY` → `sandbox/lf_contract_gate_test/transversal_assets/capability_version_compatibility/README.md`
- `CI_FAST_DEEP_LANE_ROUTER` — `TRANSVERSAL_CI_FAST_DEEP_LANE_ROUTER` → `sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md`
- `CONTEXT_BUDGET_GOVERNANCE` — `TRANSVERSAL_CONTEXT_BUDGET_GOVERNANCE` → `sandbox/lf_contract_gate_test/transversal_assets/context_budget_governance/README.md`
- `EVENT_CONTRACT_GOVERNANCE` — `TRANSVERSAL_EVENT_CONTRACT_GOVERNANCE` → `sandbox/lf_contract_gate_test/transversal_assets/event_contract_governance/README.md`
- `EVIDENCE_RESOLVER_REGISTRY` — `TRANSVERSAL_EVIDENCE_RESOLVER_REGISTRY` → `sandbox/lf_contract_gate_test/transversal_assets/evidence_resolver_registry/README.md`
- `EXECUTION_EVENT_READBACK_INDEX` — `TRANSVERSAL_EXECUTION_EVENT_READBACK_INDEX` → `sandbox/lf_contract_gate_test/transversal_assets/execution_event_readback_index/README.md`
- `GATE_CHECK_OBSERVABILITY` — `TRANSVERSAL_GATE_CHECK_OBSERVABILITY` → `sandbox/lf_contract_gate_test/gate_check_observability/README.md`
- `GITHUB_CONTRACT_GATE_LF` — `TRANSVERSAL_GITHUB_CONTRACT_GATE_LF` → `sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md`
- `INDEPENDENT_ASSURANCE` — `TRANSVERSAL_INDEPENDENT_ASSURANCE` → `sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/README.md`
- `MIGRATION_SOURCE_PARITY` — `TRANSVERSAL_MIGRATION_SOURCE_PARITY` → `sandbox/lf_contract_gate_test/transversal_assets/migration_source_parity/README.md`
- `OPERATION_EFFECT_GUARD` — `TRANSVERSAL_OPERATION_EFFECT_GUARD` → `sandbox/lf_contract_gate_test/transversal_assets/operation_effect_guard/README.md`
- `OPERATION_MATERIALIZATION_GUARD` — `TRANSVERSAL_OPERATION_MATERIALIZATION_GUARD` → `sandbox/lf_contract_gate_test/transversal_assets/operation_materialization_guard/README.md`
- `OPERATION_NEUTRAL_STEP_RECORDER` — `TRANSVERSAL_OPERATION_NEUTRAL_STEP_RECORDER` → `sandbox/lf_contract_gate_test/transversal_assets/operation_neutral_step_recorder/README.md`
- `OPERATION_STEP_CONTRACT_JUDGE_ENFORCEMENT` — `TRANSVERSAL_OPERATION_STEP_CONTRACT_JUDGE_ENFORCEMENT` → `sandbox/lf_contract_gate_test/transversal_assets/operation_step_contract_judge_enforcement/README.md`
- `PRE_EKB_GATE` — `TRANSVERSAL_PRE_EKB_GATE` → `sandbox/lf_contract_gate_test/pre_ekb_gate/README.md`
- `POL-LF-POLICY-CONSUMPTION` — `POL_LF_POLICY_CONSUMPTION` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md`
- `QUALIFICATION_FRAMEWORK` — `TRANSVERSAL_QUALIFICATION_FRAMEWORK` → `sandbox/lf_contract_gate_test/transversal_assets/qualification_framework/README.md`
- `QUALIFICATION_RECEIPTS` — `TRANSVERSAL_QUALIFICATION_RECEIPTS` → `sandbox/lf_contract_gate_test/transversal_assets/qualification_receipts/README.md`
- `QUALIFICATION_STORE_SECURITY` — `TRANSVERSAL_QUALIFICATION_STORE_SECURITY` → `sandbox/lf_contract_gate_test/transversal_assets/qualification_store_security/README.md`
- `REPOSITORY_GOVERNANCE_BUNDLE` — `TRANSVERSAL_REPOSITORY_GOVERNANCE_BUNDLE` → `sandbox/lf_contract_gate_test/transversal_assets/repository_governance_bundle/README.md`
- `ROUTER_DOWNSTREAM_AUTHORITY` — `TRANSVERSAL_ROUTER_DOWNSTREAM_AUTHORITY` → `sandbox/lf_contract_gate_test/transversal_assets/router_downstream_authority/README.md`
- `SCHEMA_FINGERPRINT_GUARD` — `TRANSVERSAL_SCHEMA_FINGERPRINT_GUARD` → `sandbox/lf_contract_gate_test/transversal_assets/schema_fingerprint_guard/README.md`
- `TRANSACTIONAL_EXECUTION_BEGIN` — `TRANSVERSAL_TRANSACTIONAL_EXECUTION_BEGIN` → `sandbox/lf_contract_gate_test/transversal_assets/transactional_execution_begin/README.md`
- `TYPED_EVIDENCE_REGISTRY` — `TRANSVERSAL_TYPED_EVIDENCE_REGISTRY` → `sandbox/lf_contract_gate_test/transversal_assets/typed_evidence_registry/README.md`
- `VALIDATION_EXEMPTION_ONE_USE` — `TRANSVERSAL_VALIDATION_EXEMPTION_ONE_USE` → `sandbox/lf_contract_gate_test/transversal_assets/validation_exemption_one_use/README.md`

- `OPERATION_LIFECYCLE_POLICY` — `TRANSVERSAL_OPERATION_LIFECYCLE_POLICY` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_operation_lifecycle/README.md`

- `POL-LF-OPERATION-LIFECYCLE` — `POL_LF_OPERATION_LIFECYCLE` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_operation_lifecycle/README.md`

- `POLICY_CONSUMPTION` — `TRANSVERSAL_POLICY_CONSUMPTION` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_policy_consumption/README.md`

- `POL-LF-SOURCE-RESOLUTION` — `POL_LF_SOURCE_RESOLUTION` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md`

- `SOURCE_RESOLUTION_POLICY` — `TRANSVERSAL_SOURCE_RESOLUTION_POLICY` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_source_resolution/README.md`

- `POL-LF-STATE-MODEL` — `POL_LF_STATE_MODEL` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_state_model/README.md`

- `STATE_MODEL_POLICY` — `TRANSVERSAL_STATE_MODEL_POLICY` → `sandbox/lf_contract_gate_test/transversal_assets/pol_lf_state_model/README.md`

## Campos mínimos del README

Cada README debe explicar: propósito, cuándo consumirlo, cómo consumirlo, superficies canónicas, fail-closed/límites, validación/readback, no duplicación y currentness.
