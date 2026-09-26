# LF Contract Check — intrinsic validation baseline

This directory contains the reproducible baseline for the intrinsic contract-validation behavior of `lf-contract-check` before restructuring.

Naming rule: artifacts describe the capability and purpose directly. Temporary stage codes are not used as durable identifiers.

The baseline executes only `validate_contract()` from the frozen pre-restructure revision and records exact positive, negative, wiring, and readback evidence. Routing, applicability planning, Migration Parity, Validate LF Packs, DB Regression, Profile Runtime, P0, Assurance, and Supabase control-plane checks are outside this baseline.
