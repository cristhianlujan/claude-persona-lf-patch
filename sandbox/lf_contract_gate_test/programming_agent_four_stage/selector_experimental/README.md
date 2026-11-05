# Experimental profile selector — isolated extraction (05 Nov 2026)

Base: draft PR #3550, exact HEAD `d675a7248ac686049623c7f2c0906504bdfb6f34`.

## What was completed
- Seven original function definitions extracted by read-only `pg_get_functiondef` and copied without semantic changes into `original/functions/`.
- Each function SHA-256 equals the plan pin.
- Table inventory: six named dependencies present in `public`; raw table records intentionally NOT copied pending personal-data/secrets checks.
- Five scoped table snapshots pinned by hashes only, see `SOURCE_PIN.json`.

## Not completed / STOP before experiments
- Recursively inspect non-`lf_` function dependencies, PostgreSQL types/extensions, DDL, constraints, triggers, policies and minimize execution rows.
- Copy screened data into a disposable database named `selector_exp_test_*`, with explicit opt-in and localhost connection checks.
- Run catalog and five-request `prepare_v2` parity; SELECTED, AMBIGUOUS, NO_MATCH, adversarial and stale-pin tests.
- Only after parity GREEN may `_exp_` variants be implemented.

## Safety
No Supabase writes; no edits to existing selector, Analysis, Testing, or main. **DO NOT load the original SQL into live Supabase.** This extraction is NOT deployable and is NOT evidence of parity.
