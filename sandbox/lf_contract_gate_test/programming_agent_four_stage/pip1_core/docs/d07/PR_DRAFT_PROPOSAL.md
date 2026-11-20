# Proposed GitHub PR (NOT PUBLISHED)
- Repository: cristhianlujan/claude-persona-lf-patch
- Base: main containing a49bf2a59bb54869e829e49fc8d59e0bac813f9c; refresh exact HEAD before publishing.
- Branch: lf/pip1-core-isolated-d07
- Title: [Paulo · PIP-1] feat(programming): núcleo puro DAG y transiciones, sin activación
- Suggested commit: feat(programming): add isolated PIP-1 pure core and adversarial tests
- Paths (decisión de Paulo, 29/10, ruta B): sandbox/lf_contract_gate_test/programming_agent_four_stage/pip1_core/{pip1_core,tests,docs,README.md,verify_exact_inventory.py}. Familia fija PROGRAMMING_AGENT_TESTS; no requiere changeset manifest.

## PR body
Scope: purely isolated contract/DAG/transitions/closure; no DB, scheduler, lease, fencing or runtime adapters. Candidate source remains CANDIDATE_NOT_APPROVED. Excludes PG-00 (owned by Carril C). No merge without PASE+Train.

Checks (29/10): authentic #3220 file (sha256 fc4cd3a3…19c9, core cd2f7a96…0ffb), 108 IDs, 22 edges, 10/10 source-copy mutations, **50 unique unit tests** (no duplicates), 20-seed stability, mypy 1.11.2 and ruff 0.6.9 clean. Independent review of D-07 remediation: GO with conditions (28/10); review of the post-C1/C2/C3 delta: PENDING. PASE: local plan on the exact local commit only; remote PASE NOT_RUN. No readiness label. No push nor draft PR until owner GO.

Declared backlog: MEDIA-2, MEDIA-3, MEDIA-5, A2 (numeric checkpoint_id → TypeError), A3 (PG-00 id pattern), B6 (N/A closure code masked by DEPENDENCY_UNSATISFIED after C1 ordering; still blocks), B11, B12, CLI prints traceback for typed PIPError.
