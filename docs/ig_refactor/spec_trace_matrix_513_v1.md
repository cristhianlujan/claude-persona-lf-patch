# M1.A6 — Spec 5.13 semantic traceability matrix v1

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M1.A6` / `PAULO-125` / L4  
**Contract:** `INPUT_READINESS_CONTRACT` id 37, revision 5.13  
**Data SHA256:** `213ee455e5089ebde99b0d07e2d13770e4d129d94c759a4a37487857c07c8832`  
**M0.11 classification SHA256:** `2104c02aaa2828cfc0476ca9307c9eacb88db0e1090d9641c1d9971a692fe118`  
**Live locator scan SHA256:** `435746d67c66fc9887e703c8d6dd97a1c313c43be50e0676967cc5377b99dcda`

## Result

- 60/60 contract clauses have exactly one target layer and target owner; 0 are unowned.
- Target distribution: CORE 5, SEMANTIC 11, READINESS_POLICY 19, ORCHESTRATION 11, EVIDENCE 12, PERSISTENCE 2.
- 18 clauses have a current function/trigger locator; this is a locator only, not semantic enforcement proof.
- 42 clauses have no direct current locator.
- `INPUT_GOVERNANCE_REGRESSION` currently contains 10 deterministic SHA/binding cases and 0 clause-level semantic tests.
- Therefore all 60 rows remain `PENDING_CLAUSE_SEMANTIC_TEST`. The `M7_1_*` references in the data file are integrity bindings, not semantic PASS.

## Interpretation rules

1. Target ownership is logical responsibility from M1.1–M1.3; it does not claim the current physical code is already separated.
2. Textual function/trigger matches are discovery locators only.
3. SHA/binding tests prove identity/integrity only; they never upgrade semantic coverage.
4. A clause with no direct locator is still owned and must be implemented/enforced by its target layer in later units.
5. Validator correctness follows M1.3: Curator claims/references may be compared, but Curator conclusions are not authoritative truth.

## Sources

- M0.11: `docs/input-governance/spec_matrix_513_preliminar_v1.json`, blob `d593d8899a49cf8ff300c01265090b4b7bcbf55c`.
- M1.1: `docs/input-governance/layers_v1.json`, blob `a82213026f687b4ac4578f4183222b00528591ac`.
- M1.2: `docs/input-governance/curator_contract_v1.json`, blob `e63baa25fb79d79fb2e4b4c038ceaafd22e423b3`.
- M1.3: `docs/input-governance/validator_contract_v1.json`, blob `795a157e3e65ec5a923593436cfdb5c82cdacc0e`.
- Full 60-row data: `docs/ig_refactor/spec_trace_matrix_513_v1.csv`.

## Negative/readback invariants

- exactly 60 distinct contract keys;
- 0 missing/unknown keys;
- 0 rows without `target_layer` or `target_owner`;
- SHA/binding coverage must remain separate from semantic clause-test coverage.

## Runtime impact

None. Documentation/evidence only. No runtime, migration, deploy, promotion, or production change; R17 is not applicable.
