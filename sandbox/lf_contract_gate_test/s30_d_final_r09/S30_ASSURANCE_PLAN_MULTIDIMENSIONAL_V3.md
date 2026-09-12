# S30 Assurance Plan — Multidimensional Family Objective Matrix v3

## Purpose

Extend, not replace, `S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V2`.

The v3 assurance layer makes four dimensions first-class acceptance gates for the Strategy Executor family:

1. FUNCTIONALITY
2. QUALITY
3. DEPTH
4. PERFORMANCE

No runtime, scheduler, production, S26, strategy snapshot, or business-effect activation is authorized by this plan.

## Gate sequence

| Gate | Dimension | Acceptance |
|---|---|---|
| G0 | Source / governance | v2 remains valid and v3 is exactly bound to the governed activation contracts |
| G1 | Functionality | required positive + negative functional checks pass |
| G2 | Quality | independent, non-nominal evidence; producer self-attestation alone is insufficient |
| G3 | Depth | all F01-F14 objectives retain positive, negative, edge/fail-closed coverage without hidden safe scope |
| G4 | Performance | timing/retry/timeout evidence is complete and within sandbox canary budgets |
| G5 | Runtime canary | controlled-state canary executes with zero business effect |
| G6 | Independent readback | evidence, timing samples, hashes and rollback/close state are independently readable |

## Performance policy

Performance is a canary gate, not a production SLO.

The initial thresholds are conservative pre-canary engineering guardrails used to detect pathological latency, retries or timeouts. They must be reviewed against the first controlled baseline before any production SLO is proposed.

Required measurement:
- monotonic timing source;
- at least 1 warm-up and 5 measured samples;
- raw samples retained;
- P50, P95, MAX and total wall-clock reported;
- retry and timeout counts reported;
- missing or partial metrics fail closed;
- model calls, production writes and business effects remain forbidden.

## Execution order

`v2 PASS -> v3 source validation -> exact-head CI -> governed promotion/readback -> controlled no-effect canary -> multidimensional receipt -> independent review`

## Closure rule

S30 Strategy Executor may not be declared canary-qualified unless Functionality, Quality, Depth and Performance all satisfy their v3 gates. A PASS in one dimension cannot compensate for a FAIL or missing evidence in another.
