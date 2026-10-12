# POLICY_MIGRATION_APPLY_V1

Status: ACTIVE OWNER POLICY  
Owner decision: D4, Paulo, 2026-10-05  
Scope: every LF Supabase migration applied from this date onward.

## Rule

For `target_type=MIGRATION`, the only permitted write mode is
`DB_WRITE_TRANSPORT / EXACT_VERSION_SOURCE_FIRST`.

`Supabase MCP apply_migration` is prohibited for governed migrations because
the tool does not accept the canonical 14-digit version explicitly and can mint
a server-side timestamp that differs from the Git filename.

Permitted executors:

1. Primary: `SUPABASE_CLI_DB_PUSH_LINKED` / `supabase db push --db-url ...`
   through the governed DB_WRITE_TRANSPORT wrapper.
2. Fallback: `SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML`, using the exact
   SQL bytes read from the exact PR head.

Direct MCP SQL may be used for readbacks and for the governed fallback
transaction described below, but never through `apply_migration`.

## Procedure available today

This is the procedure used successfully for DB-SPACE PR-IDX-1 and PR-B1.

### 1. Freeze the race boundary

Read and record:

- exact `main` SHA;
- maximum `supabase_migrations.schema_migrations.version` as `L`;
- the set of timestamped migrations currently on `main`.

STOP if `main` contains any migration with version greater than `L` that is
not in the ledger. Do not wait for another owner; report the conflict.

### 2. Prepare one exact-version PR

Use a branch based on the frozen `main`.

There must be at most one new migration in the PR. Its canonical identity is:

`supabase/migrations/YYYYMMDDHHMMSS_name.sql`

The version must be strictly greater than both:

- every migration version on current `main`;
- the live ledger maximum.

If a validated source is being retimestamped, verify byte identity of the SQL.
Only the filename/version may change unless the owner approved SQL changes.

### 3. Re-read before write

Immediately before DB write, re-read:

- current `main`;
- current ledger maximum.

STOP if another migration has overtaken the candidate or if current `main`
contains an unapplied migration that must precede it.

### 4. Read source from the exact PR head

Fetch the migration blob from the exact PR head SHA and record its Git blob SHA.
Do not execute a working-copy reconstruction, an older branch copy, or SQL
copied from the live ledger.

### 5. Apply exact-version

Preferred path, once the governed wrapper is active:

`supabase db push --db-url "$DB_URL"`

The wrapper must first prove that the only pending migration is the exact
candidate identity.

Until that wrapper is active, use the governed fallback in one transaction:

1. `BEGIN`.
2. Lock `supabase_migrations.schema_migrations` against a concurrent version
   race.
3. Recheck that the target version does not exist and that the live maximum is
   still lower than the target.
4. Execute the exact SQL bytes fetched from the PR head.
5. Insert the exact canonical ledger row with:
   - `version = <14-digit filename prefix>`;
   - `name = <filename name>`;
   - `statements = ARRAY[<exact source SQL>]`;
   - `created_by = 'SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML'`;
   - `idempotency_key = 'gitblob:<exact Git blob SHA>'`.
6. `COMMIT`.

DDL and ledger registration must succeed or roll back together.

### 6. Mandatory ledger readback

Require exactly one ledger row for the candidate and verify:

- exact version;
- exact name;
- expected `created_by`;
- `idempotency_key` bound to the PR-head Git blob;
- expected statement cardinality.

STOP on any mismatch.

### 7. Merge the same exact head

Merge only the head whose blob was applied. Never retimestamp after apply and
never apply a second copy merely because `main` moved.

### 8. Post-merge readback

Verify that:

- the exact source exists on `main`;
- the exact ledger row still exists;
- source parity is PASS or, before the automatic carrier is enabled, the same
  exact version/name/blob evidence remains reproducible.

## Fail-forward boundary

Before DB apply, failures may return the PR to preparation and a new version may
be assigned.

After DB apply, the version and SQL identity are frozen. Recovery is
fail-forward: ledger readback, source parity, then merge of the same exact
source. Do not retimestamp, replay DDL, or call `apply_migration`.

## Existing governance binding

This policy does not create a new transport. It makes the already-registered
`DB_WRITE_TRANSPORT@1.0.0` rule operationally explicit:

- migration mode: `EXACT_VERSION_SOURCE_FIRST`;
- primary: `SUPABASE_CLI_DB_PUSH_LINKED`;
- fallback: `SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML`;
- blocked condition: `exact_version_migration_via_apply_migration`.

Related EKB: `CI-MIGRATION-SOURCE-PARITY-001`.

## Narrow exception: retire obsolete, never-applied migration in the same PR

The normal source-first order remains binding. A *single* exception exists for
M9.9 legacy migration `20261012013000_ig_m99_existing_n9_adapter_proof_boundary_v1.sql`
(Git blob `1b648348503d3deb75ec3610c9abfccdb37ac751`), which was
never applied to the ledger and conflicts with the new, already-applied
two-level sandbox/operational contract `20261012070000`.

A PR that explicitly deletes this old *unapplied* file, records its identity
and retirement in `docs/ig/M99_RETIRE_UNAPPLIED_20261012.md`, and introduces
at most one newer governed migration may be merged **before applying that
newer migration**, solely to remove the obsolete pending source from `main`.
Only then use `DB_WRITE_TRANSPORT/EXACT_VERSION_SOURCE_FIRST` with:
the exact merged Git blob, a new strictly increasing canonical version, an
atomic SQL+ledger transaction, and exact readback. The replacement migration
must not be run or declared DONE if another pending source remains.

This one-off exception never permits stamping an unexecuted migration as
applied, changing a production pointer, suppressing evidence or bypassing
the independent operational canary gate. Do not generalize to other files.


## Narrow recovery: two pre-merged, unapplied M9.10/EKB migrations (2026-10-12)

Status: authorized only for the exact two immutable source blobs below.
This exception repairs a Git-first-order violation after merge; it does not
relax exact-source identity, version sequence, pointer permissions, or ROLLBACK
test obligations. Never infer a new general-purpose DB transport.

The original "STOP on any pending on main" rule applies to all other cases.
It is replaced only for this exact frozen pair by an ordered recovery,
because the files already exist on main and cannot be prepared as fresh PR
heads without changing their canonical identities.

| Order | Version | Name | Git blob SHA |
|---|---|---|---|
| 1 | 20261012073000 | ig_m910_two_level_cohort_contract_governance_v2 | 60ee615dd51439c930c9129aad1846086a5ead1d |
| 2 | 20261012074500 | ig_ekb_semantic_preflight_first_run_v1 | ced7bde1edadec7c0045c1bec720f4ab82de52e7 |

Preflight MUST first read current main SHA/tree, all timestamped migration
paths on main, and live ledger max. The pending set at this boundary MUST be
exactly those two paths; existing applied versions 20261012070000 and
20261012071000 must have their registered blob identities intact. Any
unexpected pending path, unexpected DB max, changed blob or already-partially
applied mismatch means STOP, not best-effort skipping.

Then, one candidate at a time in canonical version ascending order:

1. Re-fetch the candidate's exact main blob immediately before write.
2. Test candidate source in an independent BEGIN/ROLLBACK transaction;
   assert post-state is unchanged.
3. In a single transaction, lock supabase_migrations.schema_migrations,
   assert expected predecessor max and target absence, apply the unmodified
   candidate SQL, and insert one exact-version ledger row with the complete
   source in statements[1], created_by and idempotency_key=gitblob:<SHA>
   as defined in this policy. COMMIT atomically.
4. Read back source/ledger/authority. If parity fails, STOP and diagnose
   rather than replay or stamp as applied.
5. Re-freeze current main and ledger before considering the second candidate.

Do not use Supabase MCP apply_migration, retimestamp, create a second
migration to mask the gap, or assert either receipt succeeded unless live
SQL+ledger+readback truly agree.

The first migration changes engineering contract/governance metadata only.
The second adds only an EKB finding. Neither activates runtime, canary, or
production. Engineering checkpoint completion still requires independent
real DB sandbox evidence, not this migration repair.

Scope expires as soon as both exact ledger identities are reconciled.
