# (Paulo) PG C6 → Pipeline PG — isolated qualification adapter

**Boundary:** This directory is an adapter and proof candidate, NOT a second orchestrator, runtime hook, validation registry entry, C3 release, or PG-01 receipt. It does not modify SQL or PASE/Train. A passing qualification is not authority to pass a production checkpoint.

## Existing contract reused

- `PROGRAMMING_SIMPLE_EXECUTOR_V1` maintains per-run/unit/checkpoint receipts and refuses imported historical PASS; mandatory checkpoints use admitted deterministic validators.
- PG-01_C4 pins standards catalog, architecture/profile/controls, and optimization budget. PG-01_C6 owns the handoff receipt. PG-03, PG-08 and PG-11 consume the catalog. A **new active pre-model check must be bound through the current-run validator registry** rather than inserted as an independent scheduling engine.
- PR #3324 (PG-02 classifier) and PR #3325 (domain mapping) are drafts and do not authorize any domains. No edits to their files.
- Catalog from `paulozterra/lf-programming-sandbox` PR #13 @ `ab361cf947fb9a34c874bf3e786b7f7478c85aa9` is DRAFT; no attested C3 release is available.

## Contract

`LF_PG_C6_ASSEMBLED_CONTEXT_V1` contains run_id, catalog version and SHA-256, selected skills with version and JSON SHA-256, active domains, included/pending rules, UTF-8 byte length, C6 token estimate, assembled SHA-256 and warnings. A separate trusted caller must bind the approved required-rule set, eligible domains, and source provenance. The test fixture uses synthetic manifests and is NOT a real origin attestation.

## Staging only

`gate()` always blocks production (`qualification_only=False`). A qualification PASS means that its inputs are internally coherent against a separately provided source snapshot; it does not authenticate that snapshot. A production path needs C3's governed writer / authenticated release provenance, exact execution binding, checkpoint admission, and a real pre-model dispatch guard.

`CONTEXT_SIZE_WARNING` remains non-blocking in the standalone C6 assembler, but a missing approved budget returns REQUIRES_DECISION; exceeded budget returns REQUIRES_DECISION. No model dispatch exists in this candidate. Rebuilds must happen upstream deterministically and must produce a freshly verified receipt and full required-rule set.

## Run tests

`python -m unittest discover -s sandbox/lf_contract_gate_test/programming_agent_four_stage/c6_context_gate -p 'test_*.py' -v`

The 3,358-token warning test is a **synthetic size-equivalent**, not a replay of the original Spring fixture. Offline test corpus exercises positive qualification and negative cases, including release refusal.
