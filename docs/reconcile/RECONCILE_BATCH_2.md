# RECONCILE batch 2 — restore Git sources from the ledger (source-only)

Lane: RECONCILE (base → Git), `SOURCE_ONLY_NO_DDL_REPLAY`. **No database write.** Nothing in
this batch is applied by the Merge Train; the files only make Git match
`supabase_migrations.schema_migrations`, which is the source authority.

Owner execution referenced by every restored header:
`EXEC-DB-SOURCE-RECONCILE-BATCH2-20261013-001` (operation `ACTUALIZACION_DB_LF`). The owner
must create/approve it before this PR leaves draft.

Inventory: PR #2415 comment (post-baseline era, `version > 20261005203801`), ledger read
read-only on 2026-10-13.

## A. Restored from the ledger (17)

Each file below was rebuilt line-by-line from the ledger statements and verified:
`direct_source_hash(file)` equals the ledger canonical hash (16-hex prefix shown), and
`reconciliation_source_metadata()` accepts the header for the exact version/name.

| Ledger version | Name | Previous Git file | What differed | Ledger hash16 |
|---|---|---|---|---|
| 20261006142429 | engineering_parallel_executor_v1 | same | whitespace only | defe5b3296a4fb4c |
| 20261007041013 | engineering_plan_contract_reduction_prepass_v1 | same | EKB evidence literal `E'\n'` vs `E'\\n'` | 7a3a16b9c64255ae |
| 20261007045438 | engineering_deterministic_contract_repair_auto_hook_v1 | same | whitespace only | e0367ee6a174aa7e |
| 20261007051836 | engineering_unit_first_scheduler_simplification_v1 | same | whitespace only | 913af2b6cb3d5959 |
| 20261007151652 | semantic_judge_json_fence_error_handler_v1 | same | whitespace only | b38e944d55a05c8a |
| 20261007031426 | m410_shadow_canonical_run_test_case | 20261007030500 | Git had an expanded, never-applied version | 8354274287c5a463 |
| 20261007032243 | engineering_parallel_executor_four_lanes_constraint_fix | 20261007032200 | EKB evidence text | 5c5c125520fe5adc |
| 20261007034901 | engineering_parallel_four_lanes_lane_no_constraint | 20261007035000 | EKB evidence text | 7e81e8d8d1776c16 |
| 20261007113107 | fix_profile_update_begin_uppercase_path_v1 | 20261007063435 | whitespace only | 6c340bce02522991 |
| 20261008033605 | b2b_admin_lf_all_permissions_v1 | 20261008032000 | ledger lost backslashes: `like 'B2B_%' escape ''` (see forward fix) | a3549cb4c99f3ca6 |
| 20261008044936 | human_decision_routing_v1 | 20261008043000 | Git reformatted (long lines split); objects exist live | 4befe738a3e3cd5d |
| 20261009024635 | ig_m412_oracle_admission_independence_v1 | 20261009010000 | Git added a trailing readback block never run | 44f2ef7afcb2bcee |
| 20261009133656 | ig_m4_12_validator_fail_closed_route_v1 | 20261009213000 | Git added one timing line; live function matches ledger (6 vs 7 occurrences) | 891b382b852fa9f4 |
| 20261010095224 | t_remed_derived_links_and_queue_v1 | 20261010130000 | whitespace only | 11404bf109bdedd3 |
| 20261010095305 | t_remed_layer1_property_test_findings_v3 | 20261010112000 | whitespace only | e966766ef2951616 |
| 20261010142227 | t_remed_rule_levels_v1 | 20261010160000 | whitespace only | e40a4108dae6f896 |
| 20261011021429 | t_remed_function_comments_v1 | 20261010280000 (invalid hour 28) | ledger has stricter LIKE `fn\_t\_remed\_%` | 52bc89afdabd6237 |

Content intentionally present only in the old Git files (m410 expanded case, human_decision
reformatting, M4.12 readback/timing line) was never applied. If the owner wants any of it in
the database it must ship as a **new** migration through the Train.

## B. Already consistent — no change (4)

`20261009172500`, `20261009175500`, `20261009183000`, `20261011190000` (`ig_m713_*`): the ledger
stores `github://…#blob=<sha>` pointing at the exact Git blob, and `git hash-object` of the
current file equals that blob for all four. The inventory tool must accept this pointer form.

## C. Applied outside the ledger — keep source, documented exception (2)

| Git file | Live evidence | Ledger |
|---|---|---|
| 20261006110403_engineering_unit_stop_scope_v1 | `programacion.fn_engineering_unit_bootstrap_v3(text,text)` exists; EKB `ENGINEERING-UNIT-STOP-SCOPE-001` exists | no row |
| 20261006152000_engineering_contract_corrections_privacy_m45 | EKB `ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001`, `ENGINEERING-DEPENDENCY-TEST-OWNERSHIP-TRANSFER-001` exist; file says "Live-validated … before source reconciliation" | no row |

Not replayed and not inserted into the ledger. Recording them in the ledger, if wanted,
needs a separately approved owner lane.

## D. Retired (1 here, 2 in #2412)

- `20261008054000_human_decision_authority_receipt_verifier_v1.sql` → `docs/retired_migrations/`
  (comment-only placeholder, "superseded before merge by 20261008054500").
- `20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1` and
  `20261013001500_lf_profile_evolution_phase_boundary_v1`: retired by PR #2412.

## E. Pending owner decision (1)

`20261012120000_ig_m100_ekb_signed_release_snapshot_learnings`: EKB rows
`IG-M100-LEGACY-JUDGE-VS-PINNED-RECEIPT-001` / `IG-M100-UPSTREAM-RECEIPT-GATE-STALE-001` are
absent in `transversal.error_knowledge`. Recommendation: apply through the Train (append-only).

## Related

- Forward fix for the B2B LIKE pattern: separate one-migration PR through the Train.
- Batch 1 (104 pure renames) and batch 3 (30 renames whose ledger name carries a version
  prefix) are separate.
