#!/usr/bin/env python3
from __future__ import annotations

import lf_migration_source_parity_core as _core
from lf_migration_source_parity_core import *  # noqa: F401,F403

S30_C05_MANAGED_EXACT_NAMES = {
    "s30_c05_generic_execution_reliability_v1",
    "s30_c05_effect_guard_acl_hardening_v1",
}
_core.MANAGED_EXACT_NAMES.update(S30_C05_MANAGED_EXACT_NAMES)


def main() -> int:
    missing = sorted(name for name in S30_C05_MANAGED_EXACT_NAMES if not _core.managed(name))
    if missing:
        _core.fail("FAIL_CI009_S30_C05_CLASSIFICATION_EXTENSION", repr(missing))
    result = _core.main()
    print("PASS_CI009_S30_C05_CLASSIFICATION_EXTENSION=2/2")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
