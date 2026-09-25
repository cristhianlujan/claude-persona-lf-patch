# S30 EKB_PREFLIGHT_LF

Source-only S30 candidate for a transversal EKB preflight. It does not create another knowledge base and does not authorize mutation by itself.

## Authority

The candidate resolves active operational learnings from the existing live authorities:

- `public.lf_error_knowledge`
- `public.lf_prevention_rules`
- `public.lf_best_practices`

Applicability is explicit: the consumer supplies lifecycle phases and consumer roles. Operation-name inference and fuzzy role matching are forbidden. Explicit required EKB codes are supported for owner contracts that already bind specific controls.

Active-state semantics are aligned to the canonical Router preflight: `UPPER(TRIM(estado))` in `ACTIVO | ACTIVE | ABIERTO | OPEN`. High-severity semantics are likewise aligned to `ALTA | HIGH | CRITICA | CRITICAL | P0`. This prevents recent learnings from disappearing merely because producers used a different case/language spelling already accepted by the Router.

## Two-stage semantics

`EKB_RESOLUTION` determines which active errors, prevention rules and category-aligned best practices apply. `CONTROL_COVERAGE` is separate and proves whether the preventive controls were actually executed. Reading EKB text, having a `control_ref`, or seeing a favorable `detectability` value never constitutes execution evidence.

A PASS requires exactly one control binding for every selected high-severity error and every explicitly required code, plus observed execution evidence (`executed=true`, evidence reference and SHA-256). Human review must be an explicit reviewed PASS; `REVIEW_REQUIRED` remains pending.

## Legacy-rule compatibility

The live inventory contains active prevention rules whose own phase/role metadata is null. They remain reachable because applicability is resolved first from `lf_error_knowledge`, then all active prevention rules for the selected `error_codigo` values are inherited. This avoids silently dropping legacy prevention while avoiding a new parallel binding table.

## First real case

`first_real_case_20260914.json` freezes a real S30 CI/source-parity context. It deliberately expects `EKB_RESOLVED_CONTROLS_PENDING`, not PASS, because the case demonstrates knowledge resolution and control binding but does not fabricate executed evidence. This directly enforces the AUD-018 learning that declarative PASS is not proof execution.

## Currentness repair

The original PR #788 was built on an older `main` and used exact `estado='activo'` plus an incomplete severity vocabulary. The current-main port preserves the original two-stage design but rebinds the scope lock to current `main`, refreshes the live inventory, and adds regressions for Router-compatible active-state/severity normalization.

## Existing mechanisms reused

The design follows the fail-closed semantics already demonstrated by `programacion.fn_input_governance_ekb_checkpoint` and the active-state vocabulary already used by `public.fn_lf_router_preflight_v1`; it removes agent-specific hardcoded phase/code arrays. Existing operation `required_before_write` declarations remain consumer obligations; this candidate supplies a common resolver/receipt rather than taking ownership of their business semantics.

## Claim ceiling

`SOURCE_CANDIDATE_NO_LIVE_MUTATION`.

This branch does not apply the SQL candidate, mutate Supabase, authorize repository writes, repair owner operations, merge `main`, or enable runtime/production/Golden.
