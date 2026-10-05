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
