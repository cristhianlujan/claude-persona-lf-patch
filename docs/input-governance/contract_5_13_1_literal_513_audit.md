# CONTRACT-5.13.1 — repository literal 5.13 audit

Read-only grep against main `2b1ff2cd8985b747319079979882de2c383082bb`.
No file listed here is modified by this audit.

## Live behavior represented by applied migration source

These are the literal revision comparisons/writes that correspond to the five live DB functions updated atomically by CONTRACT-5.13.1:

- `supabase/migrations/20260928204503_lf_input_governance_contract_v513.sql:97`
  - semantic-coherence compatibility comparison `not in ('5.12','5.13')`.
- `supabase/migrations/20260928204503_lf_input_governance_contract_v513.sql:117`
  - semantic-depth compatibility comparison ending at 5.13.
- `supabase/migrations/20260928204503_lf_input_governance_contract_v513.sql:129`
  - stage-boundary compatibility comparison ending at 5.13.
- `supabase/migrations/20260928204503_lf_input_governance_contract_v513.sql:141`
  - NA/semantic compatibility comparison `('5.12','5.13')`.
- `supabase/migrations/20260928204503_lf_input_governance_contract_v513.sql:153`
  - second 5.12/5.13 compatibility patch in the original 5.13 cutover.
- `supabase/migrations/20261004225200_ig_m2_8_deterministic_assess_v1.sql:12`
  - deterministic assessor requires exactly 5.13.
- `supabase/migrations/20261004225200_ig_m2_8_deterministic_assess_v1.sql:25`
  - deterministic payload writes literal `contract_revision='5.13'`.
- `supabase/migrations/20261004230700_ig_m2_8_deterministic_assess_parity_v2.sql:13`
  - current successor source still requires exactly 5.13.
- `supabase/migrations/20261004230700_ig_m2_8_deterministic_assess_parity_v2.sql:28`
  - current successor source still writes literal 5.13 into the deterministic payload.

The Draft migration does not edit these applied migration files. It replaces the five live function definitions statically.

## Runner / fixture / profile references

Executable/test-side pins found by repository grep:

- `sandbox/lf_contract_gate_test/profile_execution_runtime/run_n15_consumer_compatibility_tests.py:22`
  - `revision = "5.13"`.
- `sandbox/lf_contract_gate_test/profile_execution_runtime/run_n15_consumer_compatibility_tests.py:126`
  - negative assertion that the worker has no local 5.13/5.12 revision pin.
- `sandbox/ig_cv/fixtures/m1_a9_contract_clause_preimage_v1.sql:32`
  - fixture literal revision 5.13.
- `sandbox/ig_cv/fixtures/m1_a9_contract_clause_preimage_v1.sql:47`
  - fixture comparison `v_contract_revision not in ('5.12','5.13')`.
- `sandbox/ig_cv/evidence/n15_consumer_compatibility_matrix_v1.json:13`
  - evidence snapshot revision 5.13.

Reference/profile snapshots that intentionally describe the existing 5.13 baseline:

- `sandbox_runs/ig_reference_corpus_v1.md:20-22,29,84`
- `sandbox_runs/ig_reference_corpus_v1.json:33,51,68,83`
- `sandbox_runs/ig_golden_t0/m0_6_paulo_114_golden_baseline_t0_manifest_v1.json:10`
- `docs/input-governance/m0_6_paulo_114_golden_baseline_t0_block_v1.json:8,15,29-30`
- `docs/ig_refactor/spec_traversal_checklist_v1.md:5,42,113`
- `docs/ig_refactor/spec_traversal_checklist_v1.json:9`
- `docs/input-governance/curator_contract_v1.md:10,20,137`
- `docs/input-governance/curator_contract_v1.json:13,19`
- `docs/input-governance/validator_contract_v1.md:5,30`
- `docs/input-governance/validator_contract_v1.json:7`
- `docs/input-governance/typed_uncertainty_contract_v1.md:9,94`
- `docs/input-governance/typed_uncertainty_contract_v1.json:6,59`
- `docs/input-governance/spec_matrix_513_preliminar_v1.md:1,5`
- `docs/input-governance/spec_matrix_513_preliminar_v1.json:6`
- `docs/input-governance/input_readiness_spec_split_5_13_v1.json:6`
- `docs/input-governance/README.md:13`
- `docs/input-governance/ADR_M10_6_RUNTIME_AND_REGISTRY_AUTHORITY_V1.md:38`
- `gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md:6`

No literal `5.13` was found under `supabase/functions/`, `prompts/`, `profiles/`, or `agents/`.
The Input Governance runtime candidate judge also has no 5.13 revision pin.

## Functions intentionally unchanged

Live readback confirms no 5.13.1 edit is needed for:

- `fn_guard_input_family_assessment_insert()`: compares run pin/evidence revision to the resolved live contract revision; no 5.13 literal allowlist.
- `fn_guard_input_family_assessment_update()`: compares run/evidence revision to the resolved live revision. Its only literal revision branch is `('5.7','5.8','5.9')` for an older semantic-depth rule.
- `fn_input_contract_clause_v1(bigint,text,text[])`: revision-agnostic; returns the live revision and SHA.
- `fn_input_governance_execute(integer,text)`: no literal 5.13 comparison; it resolves current run/contract state dynamically.

No Cristhian-owned code outside the five explicitly authorized live function definitions is edited by #1818.
