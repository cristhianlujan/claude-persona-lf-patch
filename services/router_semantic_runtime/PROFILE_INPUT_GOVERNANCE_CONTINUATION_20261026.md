# Profile → Input Governance continuation boundary — 2026-10-26

Scope: connect `EJECUCION_PERFIL_LF/input_validate` to the existing Input Governance internal runtime for task-bound `CONTEXT_PACK`.

Behavior:
- Router decides task applicability only.
- Canonical reads with `READ_PRODUCT_DEFINITION / NOT_REQUIRED_CANONICAL_READ` skip Input Governance.
- Tasks with `REQUIRED_BY_TASK` call the existing Input Governance resolver.
- If Input Governance returns runtime-required for `CONTEXT_PACK`, `input_validate` submits the screen to the existing internal IG direct-worker queue.
- Input Governance owns Curator strategy selection, SOURCE_STALE_RECURATE / REBIND / BOOTSTRAP / FULL_RECURATE, independent Validator and final readback.
- GPT Native remains on the same `EJECUCION_PERFIL_LF` execution and receives `INPUT_GOVERNANCE_PENDING / RETRY_SAME_NATIVE_BRIDGE_PREPARE`.
- No ACT-0001 re-entry occurs while Input Governance is refreshing its own context.
- When the IG run becomes READY, the same `input_validate` succeeds and native profile execution continues.
- No production promotion authority is added.

Regression target:
- B2B-AUTH-001 / Product Director / CONTEXT_PACK.
- Existing run 833 is completed but source-stale; it must not be reused as CURRENT.
