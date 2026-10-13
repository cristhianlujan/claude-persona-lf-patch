# PROFILE_ASSESSMENT v1

Transversal read-only capability for measuring profile capability maturity separately from S26 structural compatibility.

## Boundary

Input claims must be expressed as evidence records with status `PASS | FAIL | UNKNOWN` and evidence refs. A `PASS` without refs is normalized to `UNKNOWN`.

Outputs:

- maturity: `GENERIC | SPECIALIZED | ADAPTIVE | EXPERT | EVIDENCE_OPTIMIZED`;
- structural compatibility as a separate field;
- evidence-bound gaps;
- evolution mode: `NO_CHANGE | PATCH | SPECIALIZE | ADAPT | REARCHITECT | OPTIMIZE`;
- typed signals for downstream selection.

This capability never authorizes a write, runtime activation, promotion, or admission.

## Conversational context sufficiency (V1 candidate; reusable by all profiles)

Runtime decision-only adapter:
`profile_conversational_context_v1.py` — not a new evidence engine.

- Starts from the short user request; the profile identifies the requested answer depth and only the gaps that can change its next decision.
- Reuses the trusted conversation/memory/authorized tools, but never treats a source declaration as a verified system readback. System facts require an independently checked receipt via the `verify_source` callback.
- Calls the existing **`public.lf_targeted_evidence_acquisition_plan_v1`** for candidate ranking and stop logic, and then returns `RETRIEVE`. The caller performs the actual authorized lookup and re-runs sufficiency with newly acquired evidence.
- Only after all eligible decision-changing retrievals are exhausted may it ask one question on that turn. Questions must resolve a specific outstanding fact; they can request a user-owned source document for later verification, but its contents do not automatically become trusted facts.
- If the context is adequate, it returns `PROCEED` without asking. If no useful question or retrievable source remains, it returns `LIMITED_RESPONSE` and explicitly preserves uncertainty. Invalid provider/caller bindings return `BLOCKED`.
- Every callback/turn is bounded; it never executes the model, modifies authority, activates production or grants independent assurance.

Self-test:

```bash
python3 sandbox/lf_contract_gate_test/transversal_assets/profile_assessment/test_profile_conversational_context_v1.py
python3 skills/profile_creator/evals/test_profile_conversational_campaign_v1.py
```

The expert-task campaign's existing scorer must also check staged real dialogue traces; static answer-only scores no longer suffice under the current benchmark protocol. Benchmarks remain **pending** until fresh, blinded GPT profile executions and independent outcome receipts exist.
