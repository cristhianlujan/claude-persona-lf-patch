# S36 Assurance Evaluator — T01

## Scope

This directory proves and closes `ASSURANCE_EVALUATOR_TRANSVERSAL_V1` only.
The evaluator is owner-neutral and reuses the canonical LF Assurance Method stores and LF Test Matrix.
It must not hardcode Currentness, Parity, Assets, Router, or any other consumer.

Currentness PR `#877@c56b20d7d34b3dc7e4cdf44af69d17253f3efc52` is only the pinned first consumer/fire-test fixture. Its rules do not become part of the evaluator.

## Control proof

Command:

```text
python sandbox/lf_contract_gate_test/s36_assurance_evaluator/test_lf_assurance_evaluator_transversal_v1.py
```

The source-control proof checks at least:

- exact-revision test evidence;
- governed execution provenance;
- PASS/PASSED and FAIL/FAILED normalization;
- assertion contradictions and expected/actual proof;
- durable evidence requirement;
- canonical independent-review recorder lineage and producer/reviewer separation;
- REVIEW_REQUIRED pre-materialization handling;
- negative/adversarial-only defeater closure;
- required counterevidence and zero-effect proof;
- unsupported closure rules remain fail-closed;
- append-only/concurrency-idempotent evaluation recording;
- service-role-only execution boundary;
- the two T01 workflows are exact-admitted while `.github/` remains broad-denied and sibling/lookalike workflow names remain denied.

## First-consumer claim fire-test

`S36 Assurance Evaluator Control` rebuilds a disposable local Supabase from a read-only schema export, applies the exact Currentness matrix plus the exact evaluator candidate, and executes the Currentness root claim.

The expected proof is deliberately not `PASS`: three deterministic subclaims are demonstrated and the four intentionally uncovered surfaces remain `UNPROVEN`, so the root must remain `UNPROVEN`. A root `PASS` would be a critical false-pass regression.

The same fire-test also proves append-only/idempotent recording by evaluating twice and requiring the same evaluation id with one durable row.

## Source-first pre-merge boundary

The repository-wide migration source-first gate has a stricter generic pre-merge rule: while exactly one migration is local-only, the PR diff must contain only that migration file. T01 deliberately keeps its migration, tests and workflows together in one solution PR, so that generic gate can stop pre-merge with `FAIL_LF_MIGRATION_SOURCE_FIRST_SCOPE` even after all T01-owned admission/control checks pass.

T01 does not weaken, bypass or special-case that shared parity engine. The deployment close instead follows the canonical source-first order: merge the exact source to `main`, then materialize only T01 `190500`, then perform exact live readback. No foreign migration is repaired or deployed from this lane.

## Isolated post-merge deployment close

`.github/workflows/s36-assurance-evaluator-deployment-close.yml` runs only after the control workflow succeeds on `main`.
It checks out that exact successful `main` revision and targets only:

```text
20260917190500_lf_assurance_evaluator_transversal_v1.sql
```

The close is fail-closed:

1. freeze exact filename, Git blob and SHA-256;
2. read only the T01 live prestate;
3. block on version mismatch, same-name drift or partial T01 function state;
4. when absent, execute only the exact `190500` source and its exact ledger row in one transaction with an advisory lock;
5. never scan, apply, repair or reconcile another owner's pending migration;
6. read back exact version/name/blob/source SHA-256;
7. require all six evaluator functions, `service_role` EXECUTE only, zero public/anon/authenticated EXECUTE, and zero SECURITY DEFINER functions;
8. execute a live fail-closed smoke that must return `UNPROVEN` for an unregistered claim.

A rerun is idempotent: if the exact T01 ledger/source identity is already present it performs no DDL and only repeats readback.

## Transversal result

Once the control regression, first-consumer fire-test, exact deployment and independent live readback are all closed, T01 is the single transversal evaluator implementation. New capabilities consume it through their own claim/obligation/defeater/test bindings; they do not fork or rebuild this evaluator. Consumer-specific semantics remain outside T01.

## Result discipline

- Control regression `PASS` proves the source/control contract.
- Currentness fire-test `PASS` proves the evaluator does not manufacture a false PASS from incomplete evidence.
- Deployment-close `PASS` proves the exact T01 source is materialized and read back live without touching another solution.

Only the conjunction of those gates closes T01 as `PASS_CLOSED` and makes the generic evaluator available as the transversal implementation. Consumer-specific claims, obligations, bindings and semantic rules remain owned by their respective capabilities.
