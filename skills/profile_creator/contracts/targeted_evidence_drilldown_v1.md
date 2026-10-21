# LF Targeted Evidence Drilldown V1 — transversal candidate

Applies to `CREACION_PERFIL_LF` and `ACTUALIZACION_PERFIL_LF`. Reuses `TARGETED_EVIDENCE_ACQUISITION` and `VERIFIER_GUIDED_SEARCH`; no new engine, router, database function, role swarm or change to the existing runtime authorization model.

## Conditional route

`authority + EKB + material uncertainty -> one discriminating read-only probe -> observe -> resolved/refuted: STOP | no new facts: STOP + unresolved | new material unknown: descend -> bounded selection`.
Maximum 3 probes per material limit by default. A fourth requires separately justified owner authorization; never recurse silently. Do not scan all families, screens or tables by default. Reuse snapshots only with matching subject, authority, revision and as-of; new contradictory evidence invalidates reuse, not history.

## Diagnosis and repair

- Diagnosis: for each material open limit, require a bounded, safe, discriminating read-only descent; if no authorized probe exists, surface a blocker instead of pretending to close it. Keep exact probe/evidence linkage and stop on zero marginal information.
- Repair: before choosing, verify every material surface touched (as applicable): caller vs mention, call-site vs observed execution, current graph/consumers, authority, version/hash, transport, contract/schema, state/retry, performance E2E, rollback and evidence/independence. Scope is driven by the specific case; never force all domains.
- The planner's `repair_selection_admissible` is design eligibility only. Supplied refs are not independently attested by the planner and do not authorize merge, deploy, runtime, PASS or DONE. Missing remote receipts remain unverified.

## Reuse and budget

Select methods from evidence signals, use canonical EKB and existing LF capability registry. Reuse immutable evidence by exact scope and source revision; minimize probe payload; reuse already computed results; stop when no new evidence; one bounded structural self-repair if warranted. Do not broaden holdouts or restart campaigns to overcome missing signatures. Measure tokens, wall time and DB/query counts only if instrumentation exists; otherwise record NO_MEDIDO.
Keep `P0_HISTORICAL`, `CURRENT` and `UNKNOWN_ASOF` separate. Preserve current S26 learning preflight, bound schema/output validation, Quality Pack independent review, PR/Train and runtime-disabled boundaries.

## Invocation

`python3 skills/profile_creator/validators/evidence_drilldown_v1.py <payload.json>`

Positive/negative local checks: `python3 skills/profile_creator/evals/test_evidence_drilldown_v1.py`.

Candidate only; activation and current profile source writes remain governed separately.
