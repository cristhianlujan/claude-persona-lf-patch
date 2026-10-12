# CARD UPDATE I7 — MEGA 1 INDEPENDENT REVIEW HANDOFF V0.1

Review case: `CARD-UPDATE-I7-MEGA1-IR-002`

## Operating mode

Operate in `INDEPENDENT_CHAT_CONTEXT`.
Do not use producer conclusions as the expected verdict.
Attempt falsification.
Do not repair or mutate artifacts.
Do not merge.
Do not enable Router, Golden, runtime, production, or Card write.

Supabase project authority: `mhwmirqcgxxukpctffuv`.
Operational authority: Supabase only.
External Card carriers are forbidden for the active Card path.

## Frozen Git scope

Producer source commit:
`d242cd8b7833f1a150d086e9a78169c758609bee`

Review manifest path:
`sandbox/lf_contract_gate_test/card_update_i7_mega1_independent_review_v0_1/CARD_UPDATE_I7_MEGA1_REVIEW_MANIFEST_V0_1.json`

Canonical source refs to inspect at immutable SHAs:

1. Card content migration:
   - commit `4f68d52393529dec3638ca6e1740b257f522ab2e`
   - path `supabase/migrations/20260914115500_lf_card_content_supabase_native_v1.sql`

2. Supabase-native updater contract:
   - commit `d242cd8b7833f1a150d086e9a78169c758609bee`
   - path `supabase/migrations/20260914121000_lf_card_update_supabase_native_contract_v1.sql`

3. Core hardening source blob expected:
   `cd0eb837bb746d55d6a19d3d4f322e1674d4634e`

4. Server evidence v3 source blob expected:
   `2ab7f085be3e4617009bee0bdb27920b9750fb08`

Historical defective/superseded sources may exist in the sandbox. They are evidence only and must not be treated as current implementation.

## Required live Supabase checks

Verify, independently:

- Target Card: `CARD-CAND-DASHBOARD-CLIENTE-LECTOR-LF-001`.
- Active Card binding is `SUPABASE_NATIVE_CARD_CONTENT`.
- `external_card_carriers_allowed=false`.
- Active external Card refs count is zero.
- Active Router mappings for `CARD_UPDATE` / `ACTUALIZACION_CARD_LF` are zero in this phase.
- CURRENT content is exactly one row in `public.lf_card_content_versions` for the target Card.
- CURRENT row id is `1` unless live immutable evidence proves otherwise.
- Content version is `v0.1-supabase-native.1`.
- Content chars = `833`.
- Registered SHA256 equals recomputed SHA256:
  `0401cea0e645f7910676839855e336ecdc1248bfc8cf388e7abe157992e19dab`.
- RLS is enabled on `public.lf_card_content_versions`.
- `anon` / `authenticated` do not have table privileges that bypass the intended model.
- The expected migration ledger entries listed in the manifest exist.

## Required execution checks

Inspect these executions:

- `EXEC-CARD-UPDATE-I7-MEGA1-CANARY-20260914-001`
- `EXEC-CARD-UPDATE-I7-MEGA1-CANARY-20260914-002`
- `EXEC-CARD-UPDATE-I7-MEGA1-SUPABASE-CANARY-20260914-003`

All three must be terminal `CANCELLED`, with no live lease and no pending effect guard.

For the primary canary `...003`:

- steps 0 through 80 must be clean `STEP_PASS_WITH_EVIDENCE`;
- step 90 must remain blocked/no-write;
- no real Card content write is claimed;
- no real post-write readback is claimed;
- no real rollback write/readback is claimed.

A blocked step 90 is expected in Mega 1 and is not itself a failure if it proves the no-write ceiling.

## Falsification targets F01–F08

### F01 — null/missing trust fail-open
Try to demonstrate any path where missing/null/non-boolean `valid` can pass. PASS only if fail-closed is independently proven.

### F02 — caller-controlled judge assertions
Try to prove caller-supplied assertions/hard-fails can alter a server decision. PASS only if server-derived assertions dominate and caller injection cannot turn a deny into PASS.

### F03 — stale currentness / optimistic lock model
Try stale content version, wrong current row, or mismatched SHA semantics. PASS only if the pre-write trust model binds exact current Supabase row/version/SHA and rejects mismatch.

### F04 — external carrier bypass
Try to find any active Card route that accepts Google Drive, Google Docs, GitHub, or another external carrier as Card content authority. PASS only if active operational Card content is Supabase-native and external carrier use is rejected.

### F05 — baseline / effect guard / rollback preparation
Verify reversible baseline semantics and generic effect guard behavior. Do not require a real rollback write in Mega 1. Real rollback remains deferred to Mega 2.

### F06 — honest matrix semantics
Fail if any real write, post-write readback, rollback write, or rollback readback is represented as executed/PASS when it was not executed.

### F07 — exact replay
Try subset/different evidence replay. PASS only if exact canonical replay is accepted and non-exact evidence is blocked/reconciled, not treated as replay.

### F08 — source/live parity
Verify relevant source refs against live function/contract/ledger state. Fail on material drift or if the current Supabase-native contract cannot be tied to the frozen source commit/ledger evidence.

## Explicit ceiling

This review cannot authorize:

- merge;
- Golden;
- production;
- runtime activation;
- Router activation;
- Card write;
- real rollback.

A PASS only authorizes progression to Mega 2 fire test planning/execution under separate authorization.

## Required receipt

Return only a JSON object with this exact top-level shape:

```json
{
  "review_case": "CARD-UPDATE-I7-MEGA1-IR-002",
  "review_mode": "INDEPENDENT_CHAT_CONTEXT",
  "verdict": "PASS|PASS_WITH_BLOCKERS|FAIL",
  "claim_ceiling": "NO_MERGE_NO_GOLDEN_NO_PRODUCTION_NO_RUNTIME_NO_CARD_WRITE",
  "findings": [
    {
      "id": "IR-Fxx",
      "severity": "INFO|LOW|MEDIUM|HIGH|CRITICAL",
      "status": "CLOSED|OPEN|DEFERRED",
      "statement": "...",
      "evidence_refs": ["..."]
    }
  ],
  "f01_f08": {
    "F01": "PASS|FAIL|DEFERRED",
    "F02": "PASS|FAIL|DEFERRED",
    "F03": "PASS|FAIL|DEFERRED",
    "F04": "PASS|FAIL|DEFERRED",
    "F05": "PASS|FAIL|DEFERRED",
    "F06": "PASS|FAIL|DEFERRED",
    "F07": "PASS|FAIL|DEFERRED",
    "F08": "PASS|FAIL|DEFERRED"
  },
  "real_write_evidence": "NOT_EXECUTED_REQUIRES_AUTHORIZED_WRITE",
  "real_rollback_evidence": "NOT_EXECUTED_REQUIRES_AUTHORIZED_WRITE",
  "next_gate": "MEGA2_IF_PASS_ELSE_RETURN_TO_MEGA1"
}
```

No prose outside the JSON receipt.
