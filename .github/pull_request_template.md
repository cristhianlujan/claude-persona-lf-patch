## Input Governance / N-2 recuration declaration

Complete this section for changes that can affect Input Governance readiness.

### Migration impact
- [ ] If this PR adds or modifies a migration that touches readiness authorities for N-2 screens, the migration contains `-- LF_INPUT_GOV_RECURATION: REQUIRED`.
- [ ] The same migration declares affected screens with `-- LF_INPUT_GOV_PANTALLAS: <ids>` or `ALL_N2`.
- [ ] If no readiness authority is touched, these migration items are not applicable.

### Before any screen recuration
- [ ] Confirm the target screen has no active `CURATING` or `VALIDATING` run.
- [ ] Before invoking recuration, register in `public.lf_eventos` which governed unit/execution is claiming the screen.
- [ ] The event records at minimum: unit/execution id, pantalla_id, purpose, executor, and occurred_at.
- [ ] If an active `CURATING`/`VALIDATING` run exists, STOP and reconcile/close that run through the governed path; do not create another successor on top.
- [ ] Any real probe that can create or mutate runs is declared before execution.

N-2 screen scope: `1,2,3,5,43,51,52,53,54,55,56,57,58`.
