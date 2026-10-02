# Story Implementation Package V1.1 — candidate validator

Status: `CANDIDATE / READ_ONLY / NO RUNTIME ACTIVATION`

Purpose: validate the derived Programming Agent consumer view without changing canonical Story Pack A–Q or creating parallel source/currentness/qualification engines.

## Authority

- Canonical evidence remains `STORY_PACK_A_Q`.
- This package is a derived consumer view for Programming Agent.
- Structured-output transport is owned by `PROFILE_STRUCTURED_OUTPUT_BOUNDARY`.
- Judge/gate enforcement remains owned by `OPERATION_STEP_CONTRACT_JUDGE_ENFORCEMENT`.
- Source resolution remains owned by `SOURCE_RESOLUTION_POLICY`.
- Currentness remains owned by `CURRENTNESS_AUTHORITY`.
- Qualification lifecycle/state remains owned by `QUALIFICATION_FRAMEWORK`.
- Deprecated Work Protocol V1 is prior art only and remains non-executable.

## SC-M2.4B deltas included

1. `hard_boundaries`: typed `allowed_path_patterns`, `protected_path_patterns`, `allowed_effects`, `authorization_refs`.
2. `blocked_if`: derived from typed unresolved/conflict/currentness/evidence states.
3. `decision_closure`: machine-checkable readiness/blocking/currentness/evidence semantics.

## SC-M2.5 structural checks

`validate_story_implementation_package_v1.py --self-test` verifies required shape, canonical evidence preservation, Task 0 reuse guards, typed preconditions, false-ready prevention, path collisions, and rejection of Work Protocol runtime/controller residues.

## SC-M3.1 anti-invention / no-duplicate checks

The same validator consumes an authority snapshot produced from existing canonical surfaces. `story_implementation_authority_checks_v1.py` is only a domain check module; it does not resolve sources or mutate qualification.

It rejects deterministically:

- values that differ from the exact authority assertion (`INVENTED_OR_STALE_VALUE`);
- missing package material or missing required authority assertion;
- unproven currentness or non-current source decision;
- `CREATE_NEW` when a matching active capability already exists;
- non-current source-resolution/currentness/qualification capabilities.

The checked ONB_004 fixture is a frozen readback from `lf_ops` plus source-decision currentness observed on 2026-10-02; it is test evidence, not a new authority.

## SC-M3.2 ONB_004 adversarial fixture suite

`fixtures/onb_004_adversarial_cases_v1.json` contains deterministic adversarial mutations against the same frozen authority snapshot. The suite covers screen/version/route drift, design-system token invention, field-token invention, stale source decisions, unproven currentness, missing authority material, duplicate transversal capability creation, and stale qualification ownership.

`test_onb_004_adversarial_suite_v1.py` first proves the authority-bound positive baseline and then requires every adversarial case to be rejected with its exact deterministic error code. It does not write qualification receipts, mutate canonical registries, or create another judge/qualification engine; qualification remains owned by `QUALIFICATION_FRAMEWORK` and `QUALIFICATION_RECEIPTS`.

Run:

```bash
python sandbox/lf_contract_gate_test/story_creator_implementation_package/validate_story_implementation_package_v1.py --self-test
python sandbox/lf_contract_gate_test/story_creator_implementation_package/validate_story_implementation_package_v1.py --anti-invention-self-test
python sandbox/lf_contract_gate_test/story_creator_implementation_package/test_onb_004_adversarial_suite_v1.py
```

Any PASS here is a candidate validation result only. It does not authorize promotion, runtime activation, deploy, production, or qualification mutation.
