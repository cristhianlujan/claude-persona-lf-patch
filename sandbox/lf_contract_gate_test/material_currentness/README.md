# LF Material Currentness V1

Candidate transversal evaluator for S30/S31.

It separates a moving logical authority such as `refs/heads/main` from the immutable revision used as evidence. A newer `main` commit does not make an execution stale by itself. The evaluator fingerprints only the declared materials and propagates impact through the declared dependency graph.

Decisions:

- `CURRENT`: same authority revision and same materials.
- `CURRENT_REBOUND`: authority moved, declared materials did not; safe automatic rebind.
- `STALE_AFFECTED`: a root material or a transitive dependency changed.
- `UNKNOWN_FAIL_CLOSED`: dependencies or evidence are incomplete/unresolvable.

The evaluator performs no network I/O. A governed Git broker/attestor resolves the current logical ref once and passes the exact commit SHA. `DIGEST` materials are hydrated by their governed providers (for example a capability manifest fingerprint) before evaluation.

## Scoped Git material enumeration

`GIT_TREE` materials are resolved from their declared selectors before Git tree enumeration. The evaluator passes bounded pathspec roots to `git ls-tree` and then applies the existing exact `paths` / lexical `prefixes` / `fnmatch` `globs` filter locally. It no longer enumerates the repository-wide tree and filters afterward.

Safety rules:

- exact paths are passed as exact pathspecs;
- directory prefixes are passed as bounded roots;
- globs must expose a static directory root before the first wildcard;
- an unbounded root glob such as `*.py` fails closed with `GIT_TREE_GLOB_UNBOUNDED` rather than falling back to a whole-repository scan;
- existing currentness decisions, dependency closure, compatibility proof and receipt schemas are unchanged.

## Governance / Phase 03 normalization

`SADM-PP-L2-011` reuses the existing `CURRENTNESS_AUTHORITY@1.0.0`; it does not create a parallel engine, does not promote a new current pointer, and does not execute cutover/runtime/production actions. The existing capability asset remains the authority. Existing material relations that consume `CURRENTNESS_AUTHORITY` remain authoritative and are read back rather than duplicated.

DoD evidence for this source-only normalization is captured in `currentness_authority_scoped_selector_inventory_v1.json`. Live registry/current-pointer mutation is intentionally excluded from this PR.
