# H4 — EX6 real source evidence, candidate (NOT ADMITTED)

**Status:** PARTIAL. Original EX6 evidence preserved; real PG04/PG05 original producers PASS_SOURCE_ONLY, PG06 blocks with an exact reason and PG07–PG14 are not invoked. No stage may be marked PASS from mere file hashes. This candidate stays in draft; it is not eligible for `ready-to-merge` until an independently reviewed H4 completion.

## Original source
- Sandbox run: https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42674262914 (worker-native, SUCCESS, attempt 1)
- Source base: `53ab6b1a85da95f3e2a38d7f3298af731c6698ab`
- Proposal commit: `13ef9c319fb62f7e08f6f030d447c60ee7bfa7f5`
- Task pack SHA-256: `31a01a43c13d1a6c8ef5d861825e03211d05566abecded7eeea023dcfaba048e`
- Proposal SHA-256: `c469a00ebb78d1346cecab0b19bd7c385e13e428a2eaf1fccea61e30dc838d78`
- Run and feedback status: PASS **reported by source CI**; production authority False; receipt authenticated False; hidden oracle contents unavailable and never accessed.

## Original binary ZIPs (unaltered; SHA-256)
| Filename | Artifact ID | Original ZIP SHA-256 | Git blob OID |
|---|---:|---|---|
| `evidence/native-attempt-proof.zip` | 13699547221 | `237baba0c483f1330244dff94314fc883a7321b1f41295686dc501b4f7527114` | `b176e839dab6a526192bb2032e7a03e161667a0a` |
| `evidence/native-visible-feedback-and-cost.zip` | 13699208046 | `fb76b00b8870ebc0f11b509e5770a185f58e2564b4af8e9fb9349a74e9625e5b` | `ff719db0d05f037a845117810f69bcf95e4289fa` |
| `evidence/native-verified-patch.zip` | 13699771867 | `57f73f828ec5a926b6f77e712ed952e2a7c79a1471e16f73f6810cb88ec4dd04` | `81549f61cef3de587b136fba8af26a06ea6afd9e` |

Original member SHA-256:
- `attempt-proof.json`: `e45dd320598739b959849137033e6908fa6a12cfbdb0faacdce1a009f6120336`
- `feedback.json`: `9b796e549eccc582ee0717d4bcf4a6859237c49eca6699fe403d9075595e66bb`
- `cost.json`: `78d6445696d10a2b1bb15f1bc936cd05c3882bd64bd5327757d1b7ff0cbffe25`
- `status.json`: `c2725691a6f941648becd262ff45a51b3bcb1a883ac0fd81b274019edc0cb6af`
- `worker.patch`: `e0c3675f7bc7b2b80ed199be3cd5fffadae564d8b354da75ef6c56bb21bf7ce5`

The original patch creates only:
1. `apps/time-service/src/main/java/lf/sandbox/time/reminder/ReminderStats.java`
2. `apps/time-service/src/main/java/lf/sandbox/time/reminder/ReminderStatsController.java`
3. `apps/time-service/src/main/java/lf/sandbox/time/reminder/ReminderStatsService.java`

## PG-04→PG-14: original producers, real EX6, v1 first

Executed on immutable candidate HEAD `1f73f343edf1ca230d1a9f722880efc7b86fe1c9` in [GitHub Actions run 42694144179](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42694144179). All ten EX6 integrity, scope, anti-contamination and isolation tests passed. The chain builder calls **original PG-04, PG-05 and PG-06 C1 v1 producer functions**; later producers were not invoked after the earliest concrete block.

| Stage | Before v2 | After v2 | Exact code / source |
|---|---|---|---|
| PG-04 | PASS_SOURCE_ONLY | NOT_APPLICABLE | Original partition/dossier/DoD/review and exit producers; no production authority |
| PG-05 | PASS_SOURCE_ONLY | NOT_APPLICABLE | Original C1–C5 and PG05→PG06 exit; no production authority |
| PG-06 | BLOCK | NOT_APPLICABLE | `PG06_C1_PG01_DECISION_BINDING_INCOMPLETE` |
| PG-07 | UPSTREAM_BLOCKED | NOT_RUN | `UPSTREAM_BLOCKED:PG-06:PG06_C1_PG01_DECISION_BINDING_INCOMPLETE` |
| PG-08 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |
| PG-09 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |
| PG-10 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |
| PG-11 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |
| PG-12 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |
| PG-13 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |
| PG-14 | UPSTREAM_BLOCKED | NOT_RUN | same upstream code; producer not invoked |

**Why not bypass PG06:** its first original contract requires independently attested PG01 currentness authority, decision digest and related binding. None is in the allowed EX6 ZIPs, Lote D specification or task spec. Passing a fabricated fixture would contaminate the claimed real chain. `EX6SourceBlocked` is separate from the actual original PG06 rejection.

**No v2 built or invoked:** the expected `PG09_C1` cost projection mismatch cannot yet be demonstrated from the EX6 original-producer chain; `PG08_C1/C8` already allow GPT_NATIVE and have not rejected DETERMINISTIC_TOOL on EX6. Versions v1 and their producers are unchanged.

Additional baseline synthetic regression, executed locally on the unchanged producer tree (not a CI attestation): PG04 29/29, PG05 13/13, PG06 15/15. `install()`/`uninstall()` was also exercised by the 10/10 CI test suite.

## Validated public evidence, not the chain
- ZIP/member SHA-256, Git blob OIDs, canonical feedback SHA, task and proposal binding, `api_calls=0`, `real_api_usage=false`, `total_usd=0` scoped to `incremental_api`, subscription `NOT_EVALUATED`.
- Both visible acceptance commands report PASS / return code 0.
- Reported authority is `REAL_SANDBOX_UNAUTHENTICATED`; no invented blind-test evidence, no SUPER_ADMIN signature.
- New tests mutate one ZIP byte and assert fail-closed. Tests do not assert the downstream chain.

## Remaining required work before H4 approval
1. Obtain independently verifiable PG01 currentness binding for the immutable EX6 task base; do not infer or forge it from native Worker receipts.
2. Resume the original PG06 producer chain with genuine baseline/toolchain/reversibility material; repeat downstream original PG07–PG14 only if each predecessor is actually source-backed.
3. Only on an actual producer rejection, introduce narrowly scoped independent v2 files (PG09 C1 native zero API if observed; PG08 C1/C8 DETERMINISTIC_TOOL only if exercised). Keep all v1 original code unchanged.
4. Negatives: native nonzero API, missing/mismatched proposal SHA, unknown mode, and byte-for-byte WORKER_API v1 equivalence.
5. Repeat producer chain and CI tests, document per-stage after-v2 results. Keep PG12/14 PostgreSQL readbacks disposable (never production).
6. Require Claude review, then a PASE/Train manifest before any `ready-to-merge`.

**No Supabase writes; no merge/train dispatched; no producer v1 edits.**
