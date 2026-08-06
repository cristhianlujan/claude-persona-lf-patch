# PR93 · Production readiness P0 · GitHub Edge proxy hardening

## Objective

Remove anonymous and ordinary authenticated access to the two Edge Functions that use a server-side GitHub token.

## Functions

- `run-github-write-perfil-lf`
- `run-github-readback-perfil-lf`

Both deployments must use `verify_jwt=true`.

The source adds a second independent gate: the bearer token must exactly match `SUPABASE_SERVICE_ROLE_KEY`. A valid ordinary `authenticated` JWT is therefore insufficient.

## Repository boundary

Both functions accept only:

`cristhianlujan/claude-persona-lf-patch`

The caller cannot select another repository.

## Path boundary

Only these prefixes are accepted:

- `profiles/`
- `sandbox/lf_contract_gate_test/receipts/`

Absolute paths, backslashes, repeated separators and traversal components are rejected.

## Write boundary

The writer:

- rejects `main` and `master`;
- requires a pre-existing non-default branch;
- caps file count and content size;
- creates blobs, one tree and one commit;
- updates the branch exactly once with `force=false`;
- fails closed on concurrent/non-fast-forward updates;
- does not use one commit per file;
- does not create branches;
- does not merge pull requests.

## Readback boundary

The reader:

- permits readback from an explicitly named safe branch, including `main`;
- reads only allowlisted paths from the fixed repository;
- independently calculates SHA-256 of decoded UTF-8 content;
- optionally enforces both Git blob SHA and content SHA-256;
- rejects directory responses and mismatches.

## Required runtime negatives

After deployment to the technical sandbox:

1. no Authorization header → gateway denial;
2. malformed bearer → denial;
3. ordinary authenticated JWT → function-level `SERVICE_ROLE_REQUIRED`;
4. wrong repository → `REPOSITORY_NOT_ALLOWED`;
5. writer targeting `main` → `BRANCH_NOT_ALLOWED`;
6. traversal path → `PATH_NOT_ALLOWED`;
7. duplicate path → `DUPLICATE_PATH`;
8. oversized file or pack → rejection;
9. stale branch head during update → non-fast-forward rejection;
10. readback SHA mismatch → mismatch rejection.

## Positive runtime boundary

A positive writer probe may target only a disposable non-default branch and disposable profile/receipt paths. It must be followed by authenticated readback and safe branch cleanup. Until a native safe ref-deletion operation is available, do not run a positive write probe that creates persistent branch debris.

## Excluded

This lot does not authorize:

- deployment to production;
- use from browsers;
- sharing the service-role key;
- writes to `main`;
- arbitrary repository access;
- merge or pull-request approval;
- `RUNTIME_PASS` or `PRODUCTION_READINESS_PASS`.

## Static verification

Run:

```bash
python3 sandbox/lf_contract_gate_test/PR93_PRODUCTION_P0_EDGE_AUTH_TESTS.py
```

Expected marker:

`PASS_P0_EDGE_AUTH_STATIC=24/24`
