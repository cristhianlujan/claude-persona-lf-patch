# S26 Mandatory Operating Mode — Source-First / Correct-by-Construction

Status: MANDATORY_TEMPORARY_S26_POLICY
Scope: S26 only. Branch candidate only. No main/production promotion.
Purpose: make a fresh chat operate S26 in a source-first, correct-by-construction way while the broader reusable source/IR entrypoint is developed independently.

## Why this is mandatory

S26 must not rely on a chat remembering individual fixes or on validators discovering omissions after an artifact has already been built. The primary quality mechanism is construction from authority; validators are secondary regression/safety controls.

## Mandatory start protocol for every fresh S26 chat

Before material work, the chat MUST:

1. Read this file and `s26_operating_mode.json`.
2. Read the current S26 strategy/snapshot and the active execution contract.
3. Resolve the exact source authority for the current task.
4. Build or consume a source model / canonical graph before modifying or generating the artifact.
5. Classify every source-derived value as one of:
   - `IMMUTABLE_SEMANTIC`
   - `OBSERVED_SAMPLE_ONLY`
   - `RUNTIME_BINDING`
   - `PRESENTATION_ONLY`
6. Produce a governed build plan from those classifications.
7. Only then perform material generation or modification.

If steps 1–6 are incomplete, the chat must remain in pre-build state. It must not compensate by adding another validator and continuing.

## Correct-by-construction rules

### 1. Source semantics are referenced, not retyped freely

Do not freehand-copy or recreate source-derived labels, actions, fields, identifiers, claims, states or bindings when an authoritative source entity exists. Material output must be derived from the source model/canonical graph or from an explicit governed semantic binding.

### 2. Observed sample values never become runtime state

Values visible in a screenshot or frozen fixture are evidence of observation only unless a runtime authority explicitly binds them.

Examples:
- visible row count `6` -> `OBSERVED_SAMPLE_ONLY`, not runtime `record_count`
- visible page size `25` -> observed UI value unless a runtime state authority exists
- visually selected page `1` -> observation only, never implicit `current_page`
- visible pagination chrome `[1,2,3]` -> observation only, never canonical page options

Runtime state must use explicit bindings such as `LIVE_FILTERED_RESULT_COUNT`, `LIVE_PAGE_SIZE_STATE`, `LIVE_CURRENT_PAGE`, or another declared authority.

### 3. Completeness is a build responsibility

Before generation, enumerate the protected semantic surface required by the source, including as applicable:
- page title/subtitle
- breadcrumbs
- primary/secondary actions
- filters and exact labels/placeholders
- summaries/counters
- table columns
- row actions
- states/status labels
- warnings/legal/factual claims
- pagination semantics
- bindings/identifiers

Do not treat a partial semantic contract as permission to omit the rest of the source.

### 4. Presentation freedom remains allowed

Layout, spacing, responsive behavior, overflow handling, hierarchy and other presentation-only dimensions may improve, provided protected semantics and runtime bindings are preserved.

### 5. Use governed builders/bindings where available

Prefer canonical graph/source-model data, semantic bindings, runtime bindings and contract-bound execution. Do not construct source-derived semantic JSON as arbitrary free-form dictionaries when a governed representation is available.

### 6. Contract-bound runtime is the execution route

For governed profile execution, use the S26 contract-bound runtime and bound execution contract. A direct model response, manually reconstructed artifact, fixture or hand-built receipt is not equivalent execution evidence.

### 7. Cards do not override source authority

Card resolution remains `EXACT -> COMPOSED -> GENERIC_SAFE`. A Card may guide HOW to present; it must not replace WHAT the source requires.

### 8. Validators are secondary

Validators, mutation tests and independent reviews are required as regression/safety nets, but a new validator must not be the first response to a construction defect. First repair the producer/build path so the invalid state is not normally constructible.

## Mandatory S26 phase model

A fresh chat must operate in this order:

`S26_READ -> AUTHORITY_RESOLVED -> SOURCE_MODEL_READY -> GOVERNED_BUILD_PLAN_READY -> MATERIAL_BUILD -> RUNTIME_READBACK -> QUALITY -> INDEPENDENT_REVIEW -> ORCHESTRATOR_RECONCILIATION -> GOLDEN_ELIGIBLE`

Skipping forward is forbidden. A phase may only advance when the previous phase has concrete evidence.

## Temporary local implementation rule

This policy is intentionally S26-local and does not depend on Strategy 28 completing or switching its public entrypoint. If a usable canonical graph/source-first utility already exists, S26 should reuse it; otherwise S26 must implement the same operating discipline locally rather than waiting.

## Fresh-chat instruction

When a user says to continue S26, the chat should first read the current S26 state plus this operating mode. It should not reconstruct S26 behavior from memory or prior chat narrative.

## Golden boundary

This operating mode does not itself authorize Golden. Golden still requires the active S26 deterministic gates, exact artifact/source bindings, dual independent review where required, and orchestrator reconciliation.
