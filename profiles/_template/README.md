# LF Profile Pack Template

Status: GENERIC_REUSABLE_TEMPLATE / SANDBOX_PASS

This directory is a **reference superset**, not a universal exact-tree mandate for every Profile.

The canonical technical minimum is `skills/profile_creator/contracts/main_contract.md`: a governed Profile must prove the required capabilities and evidence (role/authority, contracts, typed output, judges, evals, handoff, provenance and applicable governance boundaries). File presence alone is not semantic or runtime proof.

Use this template when creating a new pack and keep the useful structure, but do not create empty folders, duplicate central adapters, copy shared policy, or materialize non-applicable artifacts only to resemble this tree.

Conditional examples:

- `manifest.json`: required when the resolved destination contract requires it.
- local `adapters/`: required only for a profile-specific transformation not already covered by a canonical Router adapter binding.
- user/internal payload separation: required only for Profiles exposing user-facing output.
- additional checklists/examples/fixtures: materialize when they provide executable review/eval value.

A real governed Profile opts into the reusable Profile Creator CI boundary by publishing its own `profiles/<slug>/validators/validate_pack.py`. The `_template` validator below validates the **integrity of this reference template itself**; it is not evidence that every real Profile must contain these exact filenames.

## Required template-integrity validation

Run from this directory:

```bash
python validators/validate_pack.py .
```

For real Profiles, run their profile-local validator through `skills/profile_creator/validators/validate_pack.py` discovery.
