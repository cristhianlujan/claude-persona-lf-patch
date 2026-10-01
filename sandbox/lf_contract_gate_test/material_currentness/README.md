# LF Material Currentness V1

`CURRENTNESS_AUTHORITY` is the single transversal source/currentness engine. `SADM-PP-L2-011` reuses it in place; it does not create a parallel capability or change the live current pointer.

It separates a moving logical authority such as `refs/heads/main` from the immutable revision used as evidence. A newer `main` commit does not make an execution stale by itself. The evaluator fingerprints only the declared materials and propagates impact through the declared dependency graph.

## Decisions preserved

- `CURRENT`: same authority revision and same materials.
- `CURRENT_REBOUND`: authority moved, declared materials did not; safe automatic rebind.
- `STALE_AFFECTED`: a root material or a transitive dependency changed.
- `UNKNOWN_FAIL_CLOSED`: dependencies, selectors or evidence are incomplete/unresolvable.

The receipt schemas, material fingerprint algorithm and affected-closure semantics are unchanged by L2-011.

## Scoped Git tree reader

Before L2-011, each `GIT_TREE` material executed:

`git ls-tree -r --full-tree <revision>`

and filtered the complete repository tree afterward.

The normalized reader derives bounded Git pathspecs from the material's declared selectors and runs:

`git ls-tree -r --full-tree <revision> -- <bounded pathspecs>`

The original `_matches` selector logic remains the final filter. Therefore declared material entries and their `SHA256_CANONICAL_SORTED_PATH_MODE_BLOB_SHA1` fingerprints remain semantically identical.

Rules:

- exact `paths` become exact root-anchored literal pathspecs;
- `prefixes` read only their declared containing directory;
- `globs` read only the bounded directory before the wildcard;
- empty, malformed or repository-root-unbounded prefix/glob selectors fail closed;
- unrelated repository paths are not traversed for a bounded material.

This implements EKB `POST-PASE-CURRENTNESS-GLOBAL-GIT-TREE-SCAN-001` without weakening fail-closed behavior.

## Authority / ownership

FAST_LOOKUP_MAP (`inventory.fn_lookup_v2`) resolves the live capability as:

- asset `CURRENTNESS_AUTHORITY`, ACTIVO, v1.0.0;
- registry status `ACTIVE`;
- current pointer `1.0.0`;
- current manifest SHA `9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09`.

The live registry still carries historical `owner_scope=LF_GOVERNANCE_S31`. The source-only normalization projection changes administrative ownership to `LF_GOVERNANCE` and adds only the administrative discoverability relation. It does **not** register a new engine/version or move `lf_capability_current`.

## Runtime boundary

The evaluator performs no network I/O. A governed Git broker/attestor resolves the current logical ref once and passes the exact commit SHA. `DIGEST` materials are hydrated by governed providers before evaluation.

L2-011 does not authorize Supabase apply, current-pointer promotion, cutover, runtime, deploy or production activation.

## Regression

`test_lf_currentness_authority_v1.py` retains the current authority tests and adds:

- fingerprint equivalence against the legacy full-tree algorithm for bounded `paths`, `prefixes`, `globs` and overlapping selectors;
- command-level proof that the reader passes declared pathspecs to Git;
- fail-closed tests for malformed or unbounded selectors.

A focused owner-local regression of the scoped reader also returns `PASS_CURRENTNESS_SCOPED_READER checks=9`.
