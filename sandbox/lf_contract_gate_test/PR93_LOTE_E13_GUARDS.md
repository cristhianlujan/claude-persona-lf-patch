# PR #93 · LOTE-E.13 · Anchored receipt and isolated T2

## Scope

E.13 replaces self-validating transcript hashes with a canonical evidence receipt whose SHA-256 must be anchored outside the evidence bundle. It also runs T1 and T2 in separate PostgreSQL processes and proves T2 non-persistence with before/after state readbacks.

No Supabase, Edge, secret, baseline, migration, `main`, deployment or runtime object is modified by this lot. CA-N93 and CA-N96 remain separate. Obsolete temporary refs remain an administrative cleanup gate.

## Only accepted entry points

1. `PR93_LOTE_E13_CAPTURE.py`
2. `PR93_LOTE_E13_VERIFY.py` with an externally trusted receipt SHA-256
3. `PR93_LOTE_E13_NEGATIVE_TESTS.py`

`PR93_LOTE_E10_RUNBOOK.psql` is fail-closed and emits `E13_CAPTURE_RUNNER_REQUIRED`. Direct execution of `PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` cannot produce accepted evidence.

## Capture

Run from a clean checkout at the exact audited head. The output directory must not exist and must be outside the repository.

```bash
export DATABASE_URL='<isolated PostgreSQL connection string>'
HEAD_SHA="$(git rev-parse HEAD)"
python3 sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE.py \
  --head-sha "$HEAD_SHA" \
  --repo-root . \
  --output-dir /tmp/pr93-e13-evidence
```

The connection string is inherited through the environment, passed to child `psql` processes through `PGDATABASE`, and never written to argv, transcripts or receipt.

Capture refuses a dirty checkout, head mismatch, malformed head, pre-existing output directory, output inside the repository or missing source artifact.

## T1

`PR93_LOTE_E13_T1.psql` runs in its own `psql` process:

- exact head required;
- `BEGIN`;
- read-only `REPEATABLE READ`;
- `search_path=pg_catalog`;
- three correlation probes;
- optional system-identifier probe after capability check;
- context snapshot, dependency preflight, primary 25-vector readback and final addendum;
- explicit `ROLLBACK` and one `E13_T1_ROLLBACK_COMPLETE` marker.

T1 must exit zero.

## T2 boundary and CA-N103

`PR93_LOTE_E13_T2.psql` runs only after T1 exits, in a fresh `psql` process. Before including the historical battery it requires:

- `AUTOCOMMIT` enabled;
- `transaction_read_only='off'`;
- exactly one `E13_T2_CONTEXT_GUARD_PASS` marker.

A read-only or inherited T1 context raises `E13_T2_MUST_NOT_RUN_INSIDE_T1` before the battery is included. The accepted receipt inventories the exact Git blobs of the wrapper and battery, so bypassing the wrapper cannot produce accepted E.13 evidence.

## CA-N102 rollback attestation

`PR93_LOTE_E13_STATE_READBACK.sql` is one SELECT-only statement. In fresh sessions before and after T2 it records counts for writer keys, writer nonces, reconciliation runs, gate runs, events, the known test keys and the known test workflow run.

Rollback status is computed:

- `EXPLICIT`: T2 exit 0, exactly one literal `ROLLBACK`, and identical before/after state;
- `IMPLICIT_ON_DISCONNECT`: T2 nonzero, no literal rollback, and identical state in a new session;
- `NOT_VERIFIED`: readback failure, state difference, invalid marker cardinality or ambiguity.

Overall `PASS` requires T1 PASS, T2 PASS and `EXPLICIT`. A failed T2 can produce a forensic receipt, but capture exits nonzero and overall status is `FAIL`.

## Canonical receipt and CA-N110/N111

Capture writes canonical JSON `PR93_E13_RECEIPT.json`. It binds:

- repository and exact head;
- schema version;
- Git blob SHA-1, SHA-256 and size of every source artifact;
- SHA-256, size and line count of every evidence file;
- T1/T2 exit codes and marker cardinalities;
- before/after state and rollback status;
- overall PASS/FAIL;
- strict first and final full-transcript markers.

Capture prints `E13_RECEIPT_SHA256=<digest>`. The sidecar digest beside the receipt is informational only.

Before verification, the receipt digest must be copied to a trust anchor controlled outside the bundle, such as:

1. a signed or protected evidence commit/tag;
2. an authenticated GitHub check or artifact attestation tied to the exact head;
3. an append-only governance ledger;
4. an independent auditor report whose integrity is controlled outside the bundle.

Verification refuses to run without that externally trusted digest and verifies the receipt digest before trusting hashes inside it:

```bash
python3 sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY.py \
  --bundle-dir /tmp/pr93-e13-evidence \
  --trusted-receipt-sha256 '<digest from independent anchor>' \
  --repo-root .
```

Changing a transcript alone fails its receipt hash. Changing transcript and receipt together fails the external receipt digest. Changing a source file fails SHA-256 and Git-blob checks.

## Transcript contract

`PR93_E13_FULL_TRANSCRIPT.log` is constructed directly by the capture process. Child stdout and stderr are merged by the operating system during execution.

It must:

1. start at line 1 with `E13_CAPTURE_BEGIN`;
2. contain the exact head and start timestamp immediately after it;
3. contain T1, pre-state, T2 and post-state between unique ordered markers;
4. contain state-match, rollback and overall status;
5. end with `E13_CAPTURE_END` as the final line.

The verifier compares embedded T1/T2/state content byte-for-byte by line with separate evidence files and rejects extra preamble, missing lines, reordered markers, truncation or content after the end marker.

## Negative matrix

```bash
python3 sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS.py \
  --bundle-dir /tmp/pr93-e13-evidence \
  --trusted-receipt-sha256 '<anchored digest>' \
  --repo-root . \
  --verifier sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY.py
```

Required result: `PASS_E13_NEGATIVE_MATRIX=10/10`.

The matrix rejects insertion before/after the begin marker, deleted lines, one-byte T1/T2 mutation, truncation, missing full transcript, receipt-only mutation, transcript plus recomputed receipt metadata, and post-state mutation.

## Optional system identifier

The mandatory path never invokes `pg_control_system()`. The optional probe runs only after the capability check. On PostgreSQL installations where EXECUTE is available to PUBLIC, the degraded route must be tested in an isolated cluster after temporary `REVOKE EXECUTE ... FROM PUBLIC`, followed by restoration or cluster disposal.

Identity strength never relies on `system_identifier_binding` alone; runtime fingerprint, transaction correlation ID, PID and transaction timestamp must also match.

## Static safety

The Python utilities use only the standard library, never use `shell=True`, reject path traversal, do not overwrite evidence, do not write inside the audited repository and require a clean exact head. The state readback contains no DML/DDL or side effects.

## Open outside E.13

- CA-N93: canonical retention of all push and pull-request runs;
- CA-N96: explainable fail-closed handling of unreachable `payload.before`;
- execution against an authorized isolated LF baseline;
- Edge/PostgreSQL comparison;
- native ruleset, independent reviewer and administrative controls;
- deletion of all obsolete temporary branches.

## Prohibitions

- Do not treat the receipt sidecar hash as an external anchor.
- Do not accept direct battery execution as E.13 evidence.
- Do not declare PASS with `IMPLICIT_ON_DISCONNECT` or `NOT_VERIFIED`.
- Do not place the evidence bundle inside the repository.
- Do not expose `DATABASE_URL` in commands or evidence.
- Do not declare runtime PASS, merge authorization or production readiness from this static lot.
