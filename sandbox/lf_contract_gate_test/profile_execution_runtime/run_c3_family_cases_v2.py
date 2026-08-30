#!/usr/bin/env python3
from __future__ import annotations

# Import v3 only for its deliberate side-effect: it patches the shared core
# generation guard used by run_c3_core_cases_v2. Keep the original c3v2
# module namespace inside the family harness because it owns helper functions
# such as _materialized_text, _bullets and _guard_for_input.
import run_c3_core_cases_v3  # noqa: F401
import run_c3_family_cases as family

if __name__ == '__main__':
    raise SystemExit(family.main())
