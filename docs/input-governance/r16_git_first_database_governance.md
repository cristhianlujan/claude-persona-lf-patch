# R16 — Git-first database changes

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Extends plan event: `#19275`  
Codifies decision: `#19529 / D-V2.3`

## Rule

No persistent database object or persisted seed-data change is canonical unless it is first represented by a versioned migration in Git.

If a live object/change appears without Git source:

1. classify it as `DRIFT`;
2. block dependent work;
3. reconcile it in a dedicated PR/change-set;
4. review and merge the migration;
5. apply and ledger the exact merged migration;
6. read back `Git = ledger = DB`;
7. only then resume dependent work.

The only exception is a transient/nonpersistent verification scoped by transaction rollback.

## EKB

Error knowledge:
`DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001`

Prevention rule:
`PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001`

Evidence origin:
- direct DB drift of `programacion.input_source_inventory_l1`;
- later transversal `inventory.*` drift;
- decision event #19529;
- reconciliation PRs #1314/#1315.
