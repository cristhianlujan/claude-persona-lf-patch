# LF Work Protocol Manifest V1 — DEPRECATED

Status: **DEPRECATED / DO NOT ADOPT / DO NOT EXECUTE / NO RUNTIME ACTIVATION**

Decision date: 2026-09-22

## Decision

Work Protocol V1 is deprecated and must not be used as a routing, execution, gate, closure, rollout, or progress authority.

The candidate duplicated responsibilities already owned by canonical LF components: ACT-0001 Router, operation-specific execution contracts, profiles, deterministic validators, semantic judges, CI/currentness controls, and runtime execution primitives. Deploying it would create a second orchestration layer, increase latency and cost, and allow contradictory verdicts over the same work.

G12 rollout is cancelled. PR #1008 was closed without merge or apply.

## Prohibited use

- Do not attach `work_protocol_manifest_v1` to new executions.
- Do not use G00–G11 to route work, select profiles/agents, repeat validators/judges, derive closure, or authorize rollout.
- Do not materialize or apply the former candidate SQL.
- Do not treat historical G09/G10/G11 receipts as current adoption authority.
- Do not copy these gates into another transversal controller under a different name.

Any attempt to validate or apply this V1 must fail closed with `WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE`.

## Canonical owners after deprecation

- Routing and operation selection: **ACT-0001 Router**.
- Profile execution, scope, source resolution, output validation and semantic judgment: **canonical operation/profile contracts** such as `EJECUCION_PERFIL_LF`.
- Execution owner binding: **canonical operation begin/reservation governance**.
- Timeout/retry/chunk/checkpoint working discipline: move to the **development/runtime working policy**, without creating a second gate engine.
- `ONE_SOLUTION_PER_PR`: move to the **GitHub + Claude/GPT development policy**, not a runtime gate.
- Direct evidence/readback rules such as avoiding ZIP/archive transport when direct sources exist: keep in the same development policy.

## Historical retention

Git history, prior receipts, tests and analysis remain historical evidence only. They may be used to understand why the candidate was rejected, but they are not reusable runtime assets.
