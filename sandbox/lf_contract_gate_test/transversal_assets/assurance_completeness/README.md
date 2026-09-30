# ASSURANCE_COMPLETENESS — LEGACY LINEAGE

`ASSURANCE_COMPLETENESS` / `TRANSVERSAL_ASSURANCE_COMPLETENESS` is a historical umbrella capability retained only for lineage and compatibility readback.

## Target state after governed cutover

- document state: `LEGACY`;
- operational state: `READ_ONLY`;
- transversal inventory status: `RETIRED_LEGACY_LINEAGE`;
- new consumers: **forbidden**;
- generic repository-CI context injection: **forbidden**;
- physical historical function deletion: **not required**.

The governed cutover source is:

`supabase/migrations/20260930073000_lf_assurance_completeness_legacy_owner_retirement_v1.sql`

## Why it is retired

The umbrella mixed responsibilities that now have separate canonical owners:

- `OPERATION_TEST_COVERAGE` — structural operation/test coverage only;
- `TEST_COVERAGE_DEBT_GUARD` — accepted global structural-debt monotonicity, Full Regression/audit only;
- `ASSURANCE_EVALUATOR` — exact-binding claim/evidence sufficiency only, dormant unless Router applicability plus exactly one ACTIVE exact subject binding authorize it.

No one of these replacements is a global Assurance-completeness PASS engine.

## Historical surfaces

Historical lineage may still include:

- `public.lf_s36_assurance_completeness_v1(boolean)`;
- migration `20260914205435_s36_assurance_completeness_engine_v1`.

Those surfaces are **not canonical for new consumption**. They must not be registered into a new policy/context set, PASE control, workflow, owner, binding or runtime path.

## Currentness rule

Consumers must resolve `public.lf_activos` before use. If the asset is `LEGACY`, `READ_ONLY`, `RETIRED_LEGACY_LINEAGE`, archived, or otherwise not active shared enforcement, the correct result is **do not consume this capability**.

Historical references in migrations, evidence or prior executions do not reactivate ownership.

## Fail-closed replacement rule

Do not substitute another global umbrella capability. Resolve the actual responsibility:

- structural coverage question → `OPERATION_TEST_COVERAGE`;
- global debt monotonicity during Full Regression/audit → `TEST_COVERAGE_DEBT_GUARD`;
- material Assurance claim → Router applicability + exact ACTIVE binding + `ASSURANCE_EVALUATOR`;
- no exact ACTIVE Assurance binding → `NOT_APPLICABLE_NO_EXECUTION`.

## Readback required for retirement closure

Closure requires all of the following:

1. active `POL-LF-POLICY-CONSUMPTION` context contains zero `ASSURANCE_COMPLETENESS` capability references;
2. `public.lf_activos` exposes this asset as `LEGACY / READ_ONLY` with inventory status `RETIRED_LEGACY_LINEAGE`;
3. zero active explicit operation-policy bindings reference the capability;
4. no new executable consumer calls `public.lf_s36_assurance_completeness_v1`;
5. Assurance subject bindings remain unchanged by this retirement lot;
6. exact-head source gates and post-apply Supabase readback are clean.

## EKB

- `ASSURANCE-COMPLETENESS-LEGACY-OWNER-RESIDUE-001`
- `OPERATION-TEST-COVERAGE-COVERED-OVERCLAIM-001`
- `TEST-COVERAGE-DEBT-GUARD-SEMANTIC-OVERCLAIM-001`
