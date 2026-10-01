# Input Governance source-inventory drift reconciliation

Date: 2026-09-30  
Scope: precondition for `IG_CURATOR_VALIDATOR_REFACTOR_V2 / M0.2 / M0.3`

## Incident

A database-only Input Governance discovery inventory appeared after the M0.2 readback event #19523.

Observed sequence in Supabase PostgreSQL logs:

- 2026-09-30 20:51:10 UTC — #19523 verified the then-current M0.2 inventory.
- 2026-09-30 20:53:26 UTC — an MCP / `mgmt-api` statement created, in one transaction:
  - `programacion.input_source_inventory_l1`
  - `programacion.v_input_source_inventory_l1_v1`
  - `programacion.fn_input_source_inventory_lookup_l1_v1`
  - three supporting indexes
  - RLS + select policy
  - read/execute grants.
- 2026-09-30 20:54:26 UTC — 54 source-inventory rows were present, derived from the 2026-09-28 `Fuentes` snapshot and reconciled against current DB metadata/counts.
- 2026-09-30 20:56:21 UTC — a second MCP statement replaced the lookup function with the current structured-match/fallback implementation.

At discovery time:

- the objects existed in the live database;
- no matching `supabase_migrations.schema_migrations` entry existed;
- no matching migration or source file existed on `main`;
- no open PR contained the objects;
- no `lf_eventos` record named the function or inventory objects.

The database log identifies the execution channel as MCP/`mgmt-api` using DB role `postgres`, but does not provide a trustworthy human/session identity. The OAuth principal seen in logs is shared across multiple MCP calls and is not sufficient attribution evidence.

## Why this blocks M0.2 / M0.3

The new function matches the M0.3 seed naming rule:

`programacion.fn_input_source_inventory_lookup_l1_v1`

Therefore the live seed changed from 108 to 109 after the previously merged M0.3 readback. The merged M0.3 evidence script correctly fails closed on this drift.

Current live M0.3 counts before repository reconciliation:

- seed: 109
- controlled graph scope: 118
- internal SQL edges: 262
- outgoing boundary edges: 2
- incoming boundary edges: 33

For M0.2, the proper IG function set changes from 112 to 113 and registry gaps from 16 to 17. Those counts must not be frozen until the database-only change is represented in Git and migration history.

## Reconciliation migration

Migration:

`supabase/migrations/20260930211500_lf_input_source_inventory_l1_reconcile_v1.sql`

The migration captures the observed live state; it does not intentionally add new semantics.

It includes:

- table definition and comments;
- RLS and policy;
- grants;
- indexes;
- `security_invoker` view;
- current lookup function;
- exact 54-row discovery-index snapshot;
- semantic receipts;
- fail-closed preflight/postflight hashes.

Captured hashes:

| Surface | SHA-256 |
|---|---|
| Table shape/policy/grants | `aa6b38424a6e7dcaf6c2dad45094e9d6c56929a7c1a80c62aef45d18cbb54018` |
| View shape/grants | `17214d508ece399dd250252e3efaddbcb92d49f407b715c5604d7b5dd7406fe0` |
| Function definition/ACL | `2939fae3252aaf08367b5e5a28dbf01ee411981e09fd80a786fa188697f7c782` |
| 54-row data snapshot | `71941b10ece0bb159fd05f77ec6c6848b100854705e627c28244541a58b0642e` |

Semantic receipt:

- `RULES` → `lf_ops.reglas`, `lf_ops.reglas_pantallas`
- `FIELDS` → `lf_ops.campos`, `lf_ops.campos_pantallas`, `lf_ops.campos_validaciones`
- exact `lf_ops.reglas` lookup → one exact source
- reconciliation-state counts:
  - MATCH: 48
  - DB_NEWER: 3
  - DB_SUPERSET: 1
  - DB_SUPERSET_DB_NEWER: 2

## Verification

Exact Git blob under review:

`7b88316bc8335108858fc97e683c575465c5f62b`

Two independent execution modes were run against Supabase with transaction rollback:

1. **Existing-state reconciliation dry-run**
   - executed the exact Git migration with final `COMMIT` replaced by `ROLLBACK`;
   - all preflight/postflight hashes and semantic receipts passed.

2. **Clean-room dry-run**
   - inside one transaction, temporarily dropped the live view/function/table;
   - executed the exact migration body from an empty state;
   - all postflight hashes and semantic receipts passed;
   - transaction rolled back, restoring the original live state.

After both tests:

- table present: yes
- view present: yes
- function present: yes
- live rows: 54
- migration ledger version `20260930211500`: absent

No persistent database mutation was performed by these verification runs.

## Advisors

Supabase security and performance advisors show no finding specific to `input_source_inventory_l1`.

## Required order

1. Review this drift-reconciliation PR.
2. Merge the exact approved head.
3. Apply/ledger the exact merged migration as a separate authorization step.
4. Read back Git ↔ migration ledger ↔ live schema/data hashes.
5. Recalculate M0.2 and M0.3.
6. Only then amend/re-review PR #1312.

The liveness refinement identified during #1312 review (`ACTIVE_ONLY_VIA_UNUSED` for four functions whose only callers are ORPHAN/SHADOW) remains a separate M0.2 classification correction after drift reconciliation.
