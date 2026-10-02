# PASE temporary freeze — 2026-10-02

Scope: execution freeze only. No PASE/POST-PASE implementation, Supabase capability, registry, migration, runtime, or evidence asset is deleted.

Effective behavior:
- `.github/workflows/pase.yml`: `lf-pase` and `migration-source-parity` jobs are disabled with `if: false`.
- `.github/workflows/pase-merge-gate.yml`: only the `pase-merge-gate` job is disabled with `if: false`.
- independent change admission and IG runtime candidate judge remain active.
- repository ruleset `protect-main` currently has no required status-check contexts, so the disabled PASE jobs do not become mandatory merge blockers.

Re-enable only after the PASE/Post-PASE architecture is qualified end-to-end and the temporary guards are explicitly removed through a reviewed PR.
