# N-2 Input Governance — PR / recuration checklist

Use this checklist in every PR or governed work unit that can change or recur N-2 readiness.

## Migration impact
- [ ] If a migration touches readiness authorities for N-2 screens, the migration declares `-- LF_INPUT_GOV_RECURATION: REQUIRED`.
- [ ] The migration declares affected screens with `-- LF_INPUT_GOV_PANTALLAS: <ids>` or `ALL_N2`.
- [ ] The declared ids are inside the canonical scope: `1,2,3,5,43,51,52,53,54,55,56,57,58`.

## Before any screen recuration
- [ ] Query the target screen and confirm there is no active `CURATING` or `VALIDATING` run.
- [ ] Before invoking recuration, register in `public.lf_eventos` which governed unit/execution is claiming the screen.
- [ ] The event records at minimum: unit/execution id, pantalla_id, purpose, executor, and occurred_at.
- [ ] If an active `CURATING`/`VALIDATING` run exists, STOP and reconcile/close that run through the governed path; do not create another successor on top.
- [ ] Any real probe that can create or mutate runs is declared before execution.
