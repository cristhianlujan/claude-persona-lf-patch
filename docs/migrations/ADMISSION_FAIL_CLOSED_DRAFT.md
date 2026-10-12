# Admission check conclusion policy — DRAFT
- GitHub check conclusion `success` is required for `lf-independent-change-admission`.
- `skipped` and `neutral` block the Train. `NOT_APPLICABLE` must be emitted by admission in a successful job's artifact/output. Train **does not currently validate that payload**; semantic validation is a follow-up, not a test PASS.
- `ig-runtime-candidate-judge` remains untouched: **PENDIENTE DE DECISIÓN DEL OWNER**.
- No changes to labels, rulesets, secrets, Environments, or merge.
