===ROLE_REPORT:PERFORMANCE BEGIN===

Role: PERFORMANCE
Case: PE10-IG-M107-M109-P0
Mode: READ_ONLY
Evidence: Q7, Q8, Q9
Observation class: CURRENT, except historical contractual requirements taken directly from the packet.

Findings

P1. Q7 shows track_functions=none, pg_stat_statements.track=top, planning tracking disabled, and I/O timing disabled. Per-function execution accounting is unavailable through the observed statistics configuration.

P2. Q8 identifies 27 matching aggregate SQL statements since the reported statistics reset of 2026-10-10T02:45:35.862139Z. This interval straddles the P0 cutoff, and the counters are not partitioned by execution epoch.

P3. Q8/Q9 identify individual measured SQL statement cohorts:

-1190413845958252360: curator materialization compound, 7 calls, mean 33,046.13 ms.

3120726644697259216: shadow evaluation compound, 7 calls, mean 6,351.03 ms.

8711451024423911529: validator loop compound, 6 calls, mean 48,383.52 ms.

-6121712835719537967: queue worker, 23,819 calls at Q9, mean 58.22 ms.

P4. The four cohorts are not demonstrably equivalent in workflow, input population, timing boundaries, or execution semantics. No valid baseline-to-optimized speedup ratio can be calculated from them.

P5. Q8/Q9 queue-worker counters advance between measurements; three other selected statement counters remain unchanged. Q9's static rows were coordinator-verified, while the advancing worker's original snapshot could not be independently reverified.

P6. Static dependency census size, function-body MD5 changes, and nominal cached-function references cannot measure runtime speed, resource efficiency, or governance correctness.

P7. The Q8 readback accidentally exposed three denylisted previous-method SQL samples. The coordinator identifies the incident as an erroneous relay. This is recorded as contamination, not used as investigative evidence.

Candidate causal accounts

Improved performance through graph/cache reuse.

Apparent differences caused by non-equivalent cohorts and workflow boundaries.

Reduced mean latency accompanied by increased validation overhead or tail risk.

No material performance regression.

All remain falsifiable and unresolved.

Negative falsifiers

Matched before/after cohorts showing no meaningful latency difference would falsify a material speedup claim.

Equivalent correctness-adjusted cohorts showing sustained regression would falsify the no-regression hypothesis.

Invocation-level timing demonstrating that apparent overhead comes from unrelated waits would falsify attribution to the targeted functions.

Measured cache hits without reduced recomputation would weaken the proposed caching mechanism.

Minimal safe action

Use existing governed timing receipts, when authorized, to construct epoch-consistent and workload-matched comparisons. Preserve correctness, source freshness, and validation-gate outcomes as eligibility constraints. Do not enable instrumentation or execute benchmarks through this diagnostic run.

Measured costs

Existing SQL execution times and block counters from Q8/Q9 are measured. Investigation-query execution costs, total wall-clock duration, producer token use, and historical performance baseline are NO_MEDIDO.

Decision

NEEDS_MORE_EVIDENCE. No performance repair has been justified.

===ROLE_REPORT:PERFORMANCE END===
