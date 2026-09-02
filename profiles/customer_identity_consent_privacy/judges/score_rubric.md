# Score Rubric — Customer Identity, Consent & Privacy

Score 0–5. Semantic PASS requires total >=22/25, no criterion <4, deterministic validator PASS and zero hard-fail defects.

1. **purpose_and_authority_fidelity** — every identity/data/consent requirement binds to the authorized purpose and source.
2. **data_minimization** — no unnecessary collection or raw-value propagation.
3. **consent_integrity** — required/optional distinction, affirmative action and decline consequence are explicit and non-bundled.
4. **privacy_exposure_control** — protected data/use/retention/sharing boundaries are preserved; no invented permissions.
5. **handoff_integrity** — downstream receives purpose, authority, optionality and exposure constraints without reinterpretation.

Hard fail: inferred consent, prechecked/bundled optional consent, unauthorized new data use, unnecessary raw sensitive handoff, invented retention/sharing/biometric authority, or treating submitted data as verified identity.
