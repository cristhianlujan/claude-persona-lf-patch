# S36 Assurance Evaluator — T01 control regression

## Scope

This directory proves source/control invariants for `ASSURANCE_EVALUATOR_TRANSVERSAL_V1` only.
It does not apply migrations, activate runtime, repair migration parity, or claim deployment readiness.

The evaluator must remain owner-neutral and reuse the canonical LF Assurance Method stores and LF Test Matrix.
It must not hardcode Currentness, Parity, Assets, Router, or any other consumer.

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
- service-role-only execution boundary.

## Result discipline

`PASS` here means the **control/source contract** is internally guarded by deterministic regression checks.
It is not proof that the migration was deployed or that a live database execution passed.
Deployment/parity/runtime proof is a later gate and must remain separate.
