# Product Director LF — remediation evidence 2026-08-27

## BEFORE — exact baseline
- main: `e90e16d311a77febdf1018b0212c530abfdbb408`
- baseline schema blob: `1c8c7de421a34fbf407e12be033720cc47337271`
- observed defect: baseline JSON Schema accepts a `PRODUCT_DIRECTION_SPEC` with empty `product_decision`, empty acceptance/evidence arrays, empty score and `self_verdict=PASS`.
- baseline eval pack has good/missing/block/repair examples but no contradictory-source case, counterfactual twin or fresh holdout.

This is structural BEFORE evidence only; it is not presented as a real profile execution.

## Root cause
Decision quality was described narratively, but the package did not deterministically bind source authority, selected decision, claims, preserved qualifiers, observable acceptance, handoff trajectory, cross-artifact consistency and score evidence.

The UI remediation established two reusable lessons applied here:
- provenance/receipt proves execution, not semantic correctness;
- a fixture suite is not evidence that the profile actually produced the expected RAW decision.

## AFTER controls
- schema materializes source authority, decision lineage, material claims, observable acceptance, conflict resolution and exact score evidence fields;
- deterministic validator rejects nominal evidence, unresolved contradiction, insufficient/weak source authority, invented claim refs, cross-artifact decision mismatch, qualifier loss and malformed input without crash;
- material claims require an observed `AUTHORITATIVE` or `CONSTRAINT` source, not a merely non-empty URI or contextual note;
- semantic judge separately checks whether the selected decision actually resolves the product objective and preserves authority/constraints;
- downstream handoff carries qualifiers that UI/Copy must preserve;
- `behavioral_eval_protocol.md` requires RAW output + canonical execution receipt + semantic judge + fresh holdout/adversarials before any behavioral remediation claim.

## Structural regression matrix
`run_cases.py` exercises 14 cases:
- 3 positive structural candidates, including a properly resolved source conflict;
- 1 insufficient-input state;
- 8 negative/adversarial controls, including weak authority, counterfactual trajectory, cross-artifact mismatch and qualifier loss;
- 1 fresh holdout;
- 1 malformed-input totality case.

The suite emits `evidence_class=STRUCTURAL_VALIDATOR_ONLY_NOT_PROFILE_EXECUTION` by design.

## Runtime-context hardening V2 — current main comparison
Comparison baseline for this pass: `main@b2fe89d63cbc041536a2634ee3bdbbcddc14a39b`.

Current UI Architect has a runtime-first authority/context resolution invariant that Product Director did not express with the same force. The V2 patch adds the domain-equivalent behavior rather than copying UI fields:
- consume supplied/resolved authority before missing-input classification;
- forbid re-asking a material authority/constraint already resolved in the run;
- distinguish low-risk non-material proposals from material unresolved product truth;
- preserve `referential/conditional/pending validation` qualifiers without semantic strengthening;
- self-repair once before output when a path re-asks context, erases a qualifier, strengthens a claim, contradicts current authority or forces downstream invention;
- require Router/direct normalized decision consistency.

`runtime_context_cases.json` adds 7 fresh semantic cases: resolved-authority short-circuit, material unresolved truth, noncanonical proposal boundary, qualifier preservation, counterfactual wrong path, Router/direct divergence and a fresh existing-load holdout.

The semantic case catalog is explicitly `SEMANTIC_CASE_CATALOG_NOT_RAW_PROFILE_EXECUTION`.

## Immutable structural evidence reuse
The V2 patch does not modify the deterministic validator, schema or `run_cases.py`. Their exact blobs remain:
- validator: `07058e3ce275d7ade5496e73909f98f69c13d4a6`;
- schema: `df8a988e1913b1d5d95090b67c6ab0e72c80d24b`;
- runner: `99d1c0b34a9aa772ca632cf8e14f3cf0fe459ebb`.

Those immutable blobs are the same artifacts previously executed 14/14. The current pass still requires exact-head CI/readback and the new semantic layer before merge; prior execution is not treated as RAW runtime behavior.

## Evidence ceiling
These fixtures prove contract/validator and semantic-case coverage of the candidate package only. They do not prove an external runtime profile execution. A real behavioral claim still requires literal input + RAW output + canonical execution receipt + semantic judge + fresh holdout/adversarial evidence under `EJECUCION_PERFIL_LF`.
