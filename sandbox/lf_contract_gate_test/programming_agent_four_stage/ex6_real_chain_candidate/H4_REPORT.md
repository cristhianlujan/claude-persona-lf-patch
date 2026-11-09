# H4 — EX6 real source evidence, candidate (NOT ADMITTED)

**Status:** PARTIAL. Original EX6 evidence preserved and locally readable; **the real PG-04→PG-14 producer chain has not yet been executed for EX6**. No stage may be marked PASS from mere file hashes. This candidate stays in draft; it is not eligible for `ready-to-merge` until an independently reviewed H4 completion.

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

## PG-04→PG-14 stage-by-stage **actual** execution status

| Stage | Before v2 | After v2 | Exact result / blocker |
|---|---|---|---|
| PG-04 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-05 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-06 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-07 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-08 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-09 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-10 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-11 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-12 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-13 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |
| PG-14 | NOT_RUN | NOT_RUN | EX6_REAL_STAGE_PRODUCER_NOT_YET_INVOKED |

The matrix is intentionally unambiguous: **NOT_RUN is not PASS**. No new v2 contract was implemented. The original `PG09_C1` v1 source unconditionally marks `executor_mode != WORKER_API` as `cost_unknown=True`, but this source inspection is **not** a real EX6-chain rejection or admission. `GPT_NATIVE` was already present in the `PG08_C1`/`PG08_C8` mode catalog per mandate.

## Validated public evidence, not the chain
- ZIP/member SHA-256, Git blob OIDs, canonical feedback SHA, task and proposal binding, `api_calls=0`, `real_api_usage=false`, `total_usd=0` scoped to `incremental_api`, subscription `NOT_EVALUATED`.
- Both visible acceptance commands report PASS / return code 0.
- Reported authority is `REAL_SANDBOX_UNAUTHENTICATED`; no invented blind-test evidence, no SUPER_ADMIN signature.
- New tests mutate one ZIP byte and assert fail-closed. Tests do not assert the downstream chain.

## Remaining required work before H4 approval
1. Construct EX6-specific `install()/uninstall()` caller builders to the **original PG04–PG14 producers**, replacing the EX5C-specific two-batch Git/Maven/format fixtures only with genuinely source-backed EX6 observations. Never substitute EX5C synthetic data.
2. Run each producer on the real EX6 evidence and capture exact PASS/blocked reason with immutable report for before-v2.
3. Only on observed rejection, introduce strictly additive v2 producer file(s). Expected conditional work: PG09 C1 native zero-API scoped decision; PG08 C1/C8 DETERMINISTIC_TOOL addition *only if exercised*. Keep v1 original unchanged.
4. Negatives: native nonzero API, missing/mismatched proposal SHA, unknown mode, and byte-for-byte WORKER_API v1 equivalence.
5. Repeat producer chain and CI tests, document per-stage after-v2 results. Keep PG12/14 PostgreSQL readbacks disposable (never production).
6. Require Claude review, then a PASE/Train manifest before any `ready-to-merge`.

**No Supabase writes; no merge/train dispatched; no producer v1 edits.**
