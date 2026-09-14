# LF Material Currentness V1

Candidate transversal evaluator for S30/S31.

It separates a moving logical authority such as `refs/heads/main` from the immutable revision used as evidence. A newer `main` commit does not make an execution stale by itself. The evaluator fingerprints only the declared materials and propagates impact through the declared dependency graph.

Decisions:

- `CURRENT`: same authority revision and same materials.
- `CURRENT_REBOUND`: authority moved, declared materials did not; safe automatic rebind.
- `STALE_AFFECTED`: a root material or a transitive dependency changed.
- `UNKNOWN_FAIL_CLOSED`: dependencies or evidence are incomplete/unresolvable.

The evaluator performs no network I/O. A governed Git broker/attestor resolves the current logical ref once and passes the exact commit SHA. `DIGEST` materials are hydrated by their governed providers (for example a capability manifest fingerprint) before evaluation.
