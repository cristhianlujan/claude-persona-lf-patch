# LF Migration Train receipt verifier (F09-X16)

`verify_train_receipt.py` is a read-only, fail-closed verifier for the existing F07-X01 `LF_MIGRATION_TRAIN_RECEIPT_V1` carrier. It checks the persisted event, canonical operation and step rows, the exact migration ledger entry, and GitHub's merged PR identity. It does not activate a check or write to Supabase/GitHub.

## Receipt contract and invariants

The source of truth is `supabase/migrations/20261013203636_lf_migration_train_receipt_v1.sql`, writer `public.lf_record_migration_train_receipt_v1`, event `MIGRATION_TRAIN_RECEIPT_RECORDED`, operational-event/v2. The event payload has `receipt_schema`, `receipt_sha256`, `receipt`, `acceptance_declared=false`, and `occurred_at`. The digest is verified by Postgres as SHA-256 over `receipt::text` (jsonb text form), rather than reserialized by Python.

| Receipt field | Required invariant |
|---|---|
| `execution_id` | Matches event `entidad_codigo`, `lf_operation_execution.execution_id`, and `EXEC-DB-TRAIN-PR<PR>-<14-digit-version>-R<run>` syntax. Encoded PR, version, and run match the typed receipt fields. |
| `pr`, `train_run_id`, `repository` | Positive PR, decimal Train run id, owner/repository; equal the operation manifest and target repository. |
| `terminal_status` | Only `COMPLETED` or `BLOCKED`; equal canonical operation status. |
| `started_at`, terminal timestamp, `terminated_by` | `started_at` is required with a timezone for both outcomes. `COMPLETED` requires `completed_at` with a timezone and `completed_at >= started_at`. `BLOCKED` does not require `completed_at` (the Train writer omits it); it requires `failure.recorded_at` with a timezone and `failure.recorded_at >= started_at`. The terminator is `LF-MIGRATION-TRAIN-RUN-<train_run_id>`. |
| `human_authorization` | `label=ready-to-merge`, nonempty author, valid authorized head. |
| `heads` | Valid SHA-1s; `final_head=execution_head`, `final_head_is_execution_head=true`, execution head equals manifest head, persisted head matches preflight readback. GitHub's current PR head must equal `final_head` (not the earlier authorized head; retimestamping can change it). |
| `diff_check` | D1 classification is one of `NO_CHANGE`, `SYNC_AND_RETIMESTAMP_ONLY`, `UNEXPECTED_CHANGES`, `NOT_EVALUATED`; unexpected paths is an array. |
| `migration` | Version is encoded in execution id; target code, path, version, name, source blob and source SHA agree with operation and `preflight.exact_target`; source SHA equals operation request SHA. |
| `write_ahead`, `effect`, `apply`, `ledger_readback`, `parity`, `merge`, `failure` | Optional when the writer strips nulls; when present, they must cross-bind to canonical effect guard, patch/verify evidence and exact ledger/merge readbacks. COMPLETED requires successful effect/apply, one exact ledger row and merged main readback. BLOCKED requires `failure.reason`, `failure.failed_step`, and the timestamp invariant above; also requires abandoned/not-reserved effect and no apply/merge object. It remains BLOCKED even if a later attempt applied the same version. |
| `steps` | COMPLETED requires exactly one `preflight`, `patch`, `verify`, each `PASS_CLEAN`; no unexpected step. Preflight exact target and persisted head, patch transport/write receipt, and verify merge/ledger readbacks must agree with receipt. |
| Event and external readbacks | Type/schema and `acceptance_declared=false`; receipt hash matches; ledger has exactly one version/name match; GitHub says closed+merged into `main`, merge SHA matches and head SHA matches final receipt head. |

A missing field, unrecognized terminal state, digest failure, duplicate ledger version, absent/duplicate/non-clean step, or disagreement returns `FAIL` with a reason. An internally consistent BLOCKED attempt returns `BLOCKED`, never PASS.

## Tests

From repository root:

```sh
python3 -m unittest discover -s sandbox/lf_contract_gate_test/train_receipt_verifier -p 'test_*.py' -v
python3 -m py_compile sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py
```

## Live read-only invocation

Requires `psycopg`, `LF_SUPABASE_READONLY_DSN`, and `GITHUB_TOKEN` (or `GH_TOKEN`). SQL explicitly starts a READ ONLY transaction and rolls it back after reading. This environment did not have `LF_SUPABASE_READONLY_DSN`; these real receipts have therefore not yet been run through this new verifier. Claude should run:

```sh
for id in \
  EXEC-DB-TRAIN-PR2754-20261015152000-R38761480482 \
  EXEC-DB-TRAIN-PR2751-20261015130918-R38740189872 \
  EXEC-DB-TRAIN-PR2750-20261015125426-R38739289235 \
  EXEC-DB-TRAIN-PR2747-20261015124000-R38735075375 \
  EXEC-DB-TRAIN-PR2744-20261015122037-R38733816763 \
  EXEC-DB-TRAIN-PR2750-20261015125426-R38738144999 \
  EXEC-DB-TRAIN-PR2728-20261015045858-R38684657571
do
  python3 sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py \
    --execution-id "$id" --live-read-only
done
```

The first five are recent COMPLETED receipts; the final two are BLOCKED attempts. A BLOCKED result is an expected non-PASS classification, not an invocation error.
