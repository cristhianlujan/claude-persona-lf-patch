# M0.7 — Input Governance Reference Corpus v1

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M0.7` / `PAULO-115` / L4  
**Scope:** historical reference corpus only; no runtime, migration, deploy, promotion or production change.

## Authority and currentness rule

- Canonical rows: `programacion.input_readiness_runs` and `programacion.input_family_assessments`.
- Currentness is resolved only with `programacion.fn_input_readiness_run_is_current(run_id)`.
- The four corpus cases are runs `191`, `253`, `265`, `266`; run `264` is the lineage anchor for `265` and `266`.
- At M0.7 readback, **191, 253, 264, 265 and 266 are all non-current**. They are historical fixtures, never current authority.
- Canonical snapshot SHA256: `c06454ca6766e5bb7bf95f1fe2201a1a61d8a95617f26b3dee3fd3410e5d369c`.

## Case expectations

| Run | Role | Contract | Persisted state | Parent | Expected reason / oracle | Assessment distribution | Current? |
|---|---|---:|---|---:|---|---|---|
| 191 | corpus case | 5.12 | COMPLETED | 183 | Preserve the historical validator output exactly; do not reinterpret under 5.13 | COMPLETE/PASS 36; MISSING/PASS 1; NOT_APPLICABLE/PASS 2; PARTIAL/PASS 8 | NO |
| 253 | corpus negative | 5.13 | BLOCKED | 191 | `SUPERSEDED_AFTER_ACCESSIBILITY_SEMANTIC_CLASSIFIER_FIX_V1`; no validator identity; all 47 validator outcomes remain PENDING | COMPLETE/PENDING 21; MISSING/PENDING 8; NOT_APPLICABLE/PENDING 2; PARTIAL/PENDING 16 | NO |
| 265 | lineage negative | 5.13 | BLOCKED | 264 | `VALIDATOR_CLASSIFIER_EQUIVALENCE_MISMATCH_API_DATA_CONTRACT_FIXED_BY_CACHED_CLASSIFIER_EQUIVALENCE_V1`; no validator identity; all 47 validator outcomes remain PENDING | COMPLETE/PENDING 33; NOT_APPLICABLE/PENDING 2; PARTIAL/PENDING 12 | NO |
| 266 | lineage completed | 5.13 | COMPLETED | 264 | Validator executes and all 47 outcomes are PASS | COMPLETE/PASS 34; NOT_APPLICABLE/PASS 2; PARTIAL/PASS 11 | NO |

### Lineage anchor 264

Run `264` is not one of the four corpus cases. It is the common parent used to explain the divergent successor paths:

- persisted state: `COMPLETED`;
- contract: `5.13`;
- currentness: `false`;
- invalidation: `TERMINAL_SUCCESSOR`;
- successor recorded by invalidation: run `265`.

## 264 → 265 vs 264 → 266

Runs `265` and `266` share parent `264` but exercise different historical outcomes:

- `265`: BLOCKED before Validator completion; 47/47 validator outcomes remain `PENDING`.
- `266`: COMPLETED with Validator identity; 47/47 validator outcomes are `PASS`.
- All **47 families** therefore change validator outcome `PENDING → PASS` when comparing 265 with 266.
- Coverage stays equal for 46/47 families.
- The only coverage change is `API_DATA_CONTRACT`: `PARTIAL → COMPLETE`.

Families whose validator outcome changes PENDING → PASS:

`ACCESSIBILITY`, `ACTIONS`, `ANALYTICS`, `API_DATA_CONTRACT`, `APPLICABILITY_READINESS`, `ASSETS_ICONS`, `AUDIT`, `BROWSER_PLATFORM`, `CONFLICT_PRECEDENCE`, `CONTEXT_BUDGET_RETRIEVAL_POLICY`, `DEPENDENCIES`, `DESIGN_SYSTEM`, `EKB`, `ERRORS`, `FEATURE_FLAGS`, `FIELDS`, `FORCED_COLORS_CONTRAST`, `FRESHNESS_INVALIDATION`, `I18N_FORMATS`, `IDEMPOTENCY_CONCURRENCY`, `LOADING_EMPTY_ERROR_STATES`, `MFA_OTP_SSO`, `NEGATIVE_REQUIREMENTS`, `OBJECTIVE_OUTCOMES`, `OBSERVABILITY`, `PERFORMANCE`, `PERMISSIONS`, `PRIVACY_PII`, `PROFILES`, `RATE_LIMIT`, `REDUCED_MOTION`, `RESPONSIVE`, `ROLLOUT_PRODUCTION_GATES`, `ROUTING_NAVIGATION`, `RUNTIME_CONFIG`, `SCREEN_IDENTITY`, `SECURITY`, `SESSION`, `SOURCE_AUTHORITY_PROVENANCE`, `STATES`, `TESTING_OBLIGATIONS`, `THEME_LIGHT_DARK_SYSTEM`, `TIMEOUT_RETRY`, `TRANSITIONS`, `UI_MESSAGES`, `VALIDATIONS`, `VISUAL_EVIDENCE`.

## Fixture inventory

Suite: `INPUT_GOVERNANCE_REGRESSION`, status `CANDIDATO`.

Current suite contains 10 deterministic SHA-binding cases:

1. `M7_1_BUILD_SHA`
2. `M7_1_CONTRACT_SHA`
3. `M7_1_REGISTRY_SHA`
4. `M7_1_ROUTER_SHA`
5. `M7_1_CURATOR_SHA`
6. `M7_1_VALIDATOR_SHA`
7. `M7_1_EXECUTION_SHA`
8. `M7_1_SHADOW_SHA`
9. `M7_1_SEMANTIC_SHA`
10. `M7_1_CURRENTNESS_SHA`

The following M0.7 fixture classes are **not represented in this suite** and remain explicit follow-up work:

- `BROKEN_REFERENCE`
- `CANDIDATE_AUTHORITY`
- `CONTRADICTION`
- `CACHED_VS_NON_CACHED`

Cases with similar words in unrelated suites do not count as Input Governance coverage.

## Source-pack correction

The M0.7 source pack previously declared persisted `blocked_reason` for BLOCKED runs as missing. Live readback shows `blocked_reason` is now directly persisted for both `253` and `265`. That missing input is therefore `STALE_RESOLVED`; M0.7 does not infer these reasons from chat history or unrelated events.

## Negative controls

M0.7 is valid only if all of the following remain true at closure:

1. Every corpus case has an explicit expected persisted state, validator expectation and evidence source.
2. Historical runs are labelled historical using `fn_input_readiness_run_is_current`; no status/`invalidated_at` inference is used for currentness.
3. Run 191 remains explicitly contract `5.12`; it is not rewritten conceptually as 5.13.
4. Runs 253 and 265 use their persisted `blocked_reason`; no reconstructed reason overrides the row.
5. Missing fixture kinds are reported as missing, not borrowed from other suites.
6. The snapshot digest equals `c06454ca6766e5bb7bf95f1fe2201a1a61d8a95617f26b3dee3fd3410e5d369c` for the frozen readback used by this artifact.

## R16 / R17

This unit is Git documentation/data only. R16 Git-first applies. R17 is **not applicable** because no runtime is changed or executed.
