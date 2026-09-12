# PR #93 · LOTE-E.13.1 · Semantic readiness and rowset rollback evidence

## Precedence

This file supersedes the accepted-entrypoint and evidence-acceptance sections of
`PR93_LOTE_E13_GUARDS.md`. The original E.13 utilities remain compatibility modules
used internally by E.13.1 and are not accepted direct evidence entry points.

Accepted entry points only:

1. `PR93_LOTE_E13_CAPTURE_V2.py`;
2. `PR93_LOTE_E13_VERIFY_V2.py` with an externally anchored receipt SHA-256;
3. `PR93_LOTE_E13_NEGATIVE_TESTS_V2.py`.

Direct execution of the historical adversarial battery or the original E.13 capture
cannot produce accepted E.13.1 evidence.

## T1 semantic readiness

A zero `psql` exit is insufficient. Capture and verification independently recompute
`PR93_LOTE_E13_SEMANTICS.py` and require exact receipt equality for:

- exactly one `E13_T1_HEAD_SHA=<head>` matching the audited head;
- strict marker order;
- three correlation probes with `context_valid=true`;
- matching runtime fingerprint, correlation ID, PID, transaction timestamp,
  postmaster timestamp, database name and database OID;
- valid read-only `REPEATABLE READ` execution context;
- `preflight_ready=true` and `all_present=true`;
- exactly 25 mutation vectors and every vector `pass=true`;
- binder preservation, binder digest, mutation controls and pinned trigger linkage;
- final evidence chain ready, binder/trigger integrity and `failure_domain=NONE`;
- optional system-identifier evidence bound to the same T1 when used.

Any false readiness boolean forces T1 and overall status to `FAIL`.

## Marker uniqueness

These markers are distinct and must each occur exactly once in their own scope:

- `E13_HEAD_SHA=<head>` in the capture envelope;
- `E13_T1_HEAD_SHA=<head>` in T1;
- `E13_T2_HEAD_SHA=<head>` in T2.

Duplicate, conflicting or cross-scope head markers invalidate the receipt.

## T2 boundary

`PR93_LOTE_E13_T2.psql` is the accepted T2 wrapper. It runs in a fresh `psql`
process, requires autocommit, requires `transaction_read_only=off`, emits exactly one
`E13_T2_CONTEXT_GUARD_PASS`, and only then includes the historical battery.

Bypassing the wrapper cannot satisfy the source inventory, head marker, context guard
or receipt contract.

## Rowset rollback evidence

`PR93_LOTE_E13_STATE_READBACK.sql` is one SELECT-only statement. It records counts and
SHA-256 digests of complete relevant rowsets before and after T2 for:

- writer HMAC keys;
- writer nonces;
- reconciliation runs;
- gate-test runs;
- LF events.

`key_material` is removed before hashing. Pre-state and post-state must match exactly,
including rowset digests. Count-preserving updates therefore cannot masquerade as
rollback. Raw state-command logs must parse as JSON and equal their canonical state
files.

Rollback status is computed:

- `EXPLICIT`: T2 exit 0, exactly one literal `ROLLBACK`, exact state match;
- `IMPLICIT_ON_DISCONNECT`: T2 nonzero, no literal rollback, exact state match;
- `NOT_VERIFIED`: readback failure, state difference or ambiguous markers.

Overall `PASS` requires `EXPLICIT`. A failed T2 may retain a forensic receipt but
cannot pass.

## Receipt trust anchor

The canonical receipt binds the exact head, source Git blobs and SHA-256 values,
evidence-file hashes and sizes, T1 semantic checks, T2 process status, rowset state,
rollback status and overall result.

Its digest must be copied to an independent trust anchor before later verification.
The sidecar digest inside the bundle is informational only. The verifier checks the
externally supplied digest before trusting any receipt-contained hash.

## Mandatory negative matrix

E.13.1 requires `PASS_E13_NEGATIVE_MATRIX=12/12`, covering the original ten mutation
cases plus:

11. `preflight_ready=false` cannot yield semantic PASS;
12. a duplicated T1 head marker is rejected.

## Open outside E.13.1

- CA-N93: canonical retention of all push and pull-request runs;
- CA-N96: explainable handling of unreachable `payload.before`;
- execution against an authorized isolated LF baseline;
- Edge/PostgreSQL comparison;
- native ruleset, independent reviewer and administrative controls;
- deletion of obsolete temporary refs.

No static result from this lot authorizes runtime PASS, merge, deployment or
production readiness.
