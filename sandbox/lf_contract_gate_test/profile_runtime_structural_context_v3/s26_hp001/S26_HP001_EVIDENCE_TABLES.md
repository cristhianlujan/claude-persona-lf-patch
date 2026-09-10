# S26-HP-001 — Evidence Tables for Claude / GPT

## Immutable identity

| Field | Value | Status |
|---|---|---|
| Project / test | `S26` / `S26-HP-001` | FROZEN |
| Runtime candidate | `d5f27f129464163d915b08a26be08ca117385482` | EXECUTED |
| Runtime branch | `lf/s26-hp001-gate-f-perf-parity-20260910` | PR #654 |
| Immutable evidence commit | `be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652` | READBACK PASS |
| Evidence branch | `lf/s26-hp001-evidence-final-20260910` | EVIDENCE ONLY |
| Production effect | `NO` | PASS |
| Model weight acquisition | `NO` | PASS |
| Paid fallback | `NO` | PASS |

## Exact artifact chain

| Artifact | SHA-256 |
|---|---|
| Input | `fdfb12f2c8c5313fef5152e1f6b6689ccae78ed94170358cf065bb02649135a1` |
| Model raw | `8270b0ab381fed8ec3060c73bfe3cdb6ba645e184a64daa90eda22f7f75f8d1b` |
| Materialized exact runtime output | `9f1c3c8bb90e6fc279998273d59d043273791c2e5b7793307db4be9d3e0ab5c2` |
| Gate F evidence | `73d8d2d3afff1d7dd78c9dbf0084cb46c22cdbc00a932debda28a33d1d27470b` |
| Gate F output | `87912fce0aa9b3851cd2c43d50ce1ed1c3bc327f3da4291995e5437226838baf` |
| Gate G output | `56639ed8529683e54ab51c41c2cad5daefd67a389c98604060a748846ad32069` |
| Gate H output | `4162be5a97fbee4ed96ccb0c2d5b24bbefbd914138f84def4e19e6c2e7825353` |
| Exact replay manifest | `830964a27ef785aa4ee83854ca937aecbbb22a92dae783e65d39d1179a202ef3` |
| Exact replay runner | `e1cd5addcd7d90b70ff9a63f62f6eaf502933378755dc61df1f7e7766af809fa` |

## A→J status

| Stage | Result |
|---|---|
| A — exact input | PASS |
| B — EKB/control plane | PASS |
| C — Card resolution | PASS — `NO_CARD_GOVERNED` |
| D — Authority | PASS |
| E — typed context | PASS |
| F — exact deployed runtime | **PASS** |
| G — contract shape | **PASS** |
| H — material requirements | **PASS** |
| I — immutable evidence readback | **PASS** |
| J — deterministic replay from immutable commit | **PASS** |
| Independent semantic review | **NOT EXECUTED** |
| Overall S26 Golden | **NOT GOLDEN** |

## Runtime performance

| Metric | Observed | Limit | Result |
|---|---:|---:|---|
| Model generation | 25,999.708 ms | 120,000 ms | PASS |
| Full profile | 31,318.137 ms | 120,000 ms | PASS |
| Requirement coverage | 100% | 100% | PASS |
| Source-bound integrity | 100% | 100% | PASS |

## Closure boundary

The deterministic/runtime path is closed through immutable GitHub readback at `be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652`. The only remaining promotion boundary is the independent Quality Pack semantic review in a new `INDEPENDENT_CHAT_CONTEXT`. This producer/integrator context must not self-certify that gate.

**Claim ceiling:** `HP001_EXACT_RUNTIME_F_G_H_REPLAY_EVIDENCE_PASS_PENDING_INDEPENDENT_REVIEW_NOT_GOLDEN`.
