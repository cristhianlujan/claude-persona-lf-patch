# T-PERF — transverse phase budget + exact-source benchmark candidate

Owner: `SUPER_ADMIN` under D-V2.2. This source generalizes the existing candidate assets `TIMEOUT_PHASE_BUDGET_POLICY` and `PERFORMANCE_EXACT_SOURCE_BENCHMARK`; it does not treat the historic S30/profile carrier as authority.

## Boundary

This candidate is source-only. It does not change database roles, session timeouts, Input Governance functions, runtime/deploy/production state, or capability current pointers. It never increases a timeout automatically.

The budget policy consumes an explicit phase map. The evidence model follows the existing EKB separation of `CONNECT`, `READ`, `INFERENCE`, `JOB`, and `ORCHESTRATION`; consumers may declare budgets for the phases they actually use. Unknown phases fail closed.

A request within the configured budget is allowed. A request above the configured budget is blocked unless it supplies a valid benchmark receipt for the same phase and exact source SHA-256 with at least the configured sample count and p50/p95/p99. Even with valid evidence the result is only `EVIDENCE_BOUND_EXTENSION_CANDIDATE`, requires higher-authority approval, and does not mutate the timeout.

## Exact-source benchmark

`performance_exact_source_benchmark_v1.py` receives the exact source SHA-256 and source reference from the caller and measures each supplied phase callable exactly once per sample using `time.perf_counter_ns`. It emits p50/p95/p99/max and call count per phase. The helper does not persist evidence itself; the governed control plane owns durable persistence/readback.

The current `programacion.input_readiness_runs.source_manifest` is a source-authority manifest of governance/domain inputs, not a Git/code revision. Therefore historical run durations cannot be retroactively claimed as exact-code-source benchmark evidence. T-PERF keeps those live run timings as factual AS-IS performance context only.

## Negative proof

The deterministic source test proves:

1. within-budget request is accepted without changing the budget;
2. a timeout increase without benchmark evidence is blocked;
3. an unknown phase is blocked;
4. exact-source benchmark emits p50/p95/p99 and one-call-per-sample evidence;
5. an evidence-bound extension remains approval-required and non-mutating;
6. a real local async call exceeding the configured phase budget is cancelled by `asyncio.wait_for`;
7. the combined candidate test closes without runtime/DB changes.

No blind timeout extension is permitted.
