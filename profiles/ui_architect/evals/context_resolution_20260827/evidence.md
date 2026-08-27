# UI Architect V5 — Context Resolution + Report Precision

Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260827-002`
Baseline main: `e90e16d311a77febdf1018b0212c530abfdbb408`
Scope: `profiles/ui_architect/**`

## User-reported gap

A real UI review was directionally useful but mixed precise and vague remediation language. Examples included:
- `Darle más aire inferior... mínimo space_24` — good because the canonical/known spacing was made explicit.
- `Subirlos levemente` — under-specified if a DS size token is already available.
- `Normalizar alturas internas ... space_16/12` — useful because the relevant spacing basis is explicit.

The larger workflow gap is not that the user should manually send a super-report. A normal request such as `analiza esta pantalla` should route to UI Architect with relevant context resolved by chat/orchestrator when available. The profile must then use that context or identify a genuinely material unresolved input.

## Required behavior

### C1 — Canonical spacing available
Input context:
- visible issue: amount too close to divider;
- canonical spacing: `space_24` applies to amount -> divider.

PASS:
- selected correction explicitly uses `space_24`;
- `precision_basis.mode=CANONICAL_TOKEN`;
- source is bound.

FAIL:
- only `dar más aire`, `aumentar espacio`, or another vague phrase.

### C2 — Canonical interaction rule available
Input context:
- CTA behavior contract says CTA remains active;
- click without payment selection shows validation error.

PASS:
- report preserves CTA active;
- error state is explicit and actionable.

FAIL:
- profile invents `disabled until selected` or asks the user what the CTA should do.

### C3 — Exploratory screen without DS/token
Input context:
- no canonical spacing token exists;
- visual choice is low-risk/exploratory.

PASS:
- continue;
- choose `EXPLORATORY_PROPOSAL / PROPOSED_NOT_CANONICAL`, e.g. 24px starting proposal; OR
- choose `RELATIVE_GUIDANCE`, e.g. increase one spacing level.

FAIL:
- `BLOCK_PIPELINE` only because token does not exist;
- call the proposal a canonical DS token.

### C4 — Material interaction ambiguity
Input context:
- whether CTA is active or disabled materially changes behavior;
- no interaction/product source resolves it.

PASS:
- `RETURN_TO_ORCHESTRATOR`;
- identify preferred interaction/product source and why the decision is material;
- orchestrator may later escalate to user if canonical resolution fails.

FAIL:
- silently invent active/disabled;
- UI worker asks end user directly.

### C5 — Partial-context holdout
Input context:
- `space_16` is canonical for radio -> content;
- exact radio size token is absent and the size tweak is low-risk;
- CTA state remains materially unresolved.

PASS:
- use `space_16` exactly;
- treat radio-size tuning as exploratory proposal/relative guidance;
- escalate CTA state only.

### C6 — False authority adversarial
Input context:
- no token `space_20` exists.

FAIL:
- output says `space_20 (DS)` merely because 20px seems reasonable.

### C7 — Unnecessary user-question adversarial
Input context:
- source context already supplies `space_24`.

FAIL:
- profile asks user `¿qué espacio deseas?` or returns to orchestrator for the same recoverable value.

## Compact report expectation

The user-facing output must remain concise. Precision should appear inside the existing `Observación / Cómo corregir` style rather than as a large internal specification dump.

Example:

| Observación | Cómo corregir |
|---|---|
| Monto muy cerca del divisor | `payment_amount -> divider = space_24` (DS). |
| Radio separado del contenido | `radio -> content = space_16`; use DS size token if available; otherwise label size adjustment as exploratory proposal. |
| CTA state unresolved | Return only this material ambiguity to orchestrator; do not ask the user from the worker. |

## Preserved constraints
- no new output mode;
- no runtime enablement;
- no automatic promotion;
- no token-mandatory rule for exploratory design;
- no user-facing super-report;
- no direct end-user questioning by worker in automated routing;
- semantic authority and LF safety remain mandatory.
