#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

_CORE_PATH = Path(__file__).resolve().with_name("lf_migration_source_parity_core.py")
_spec = importlib.util.spec_from_file_location("lf_migration_source_parity_core", _CORE_PATH)
if _spec is None or _spec.loader is None:
    raise SystemExit("FAIL_CI009_CORE_LOAD")
_core = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_core)

for _name in dir(_core):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_core, _name)

S30_C05_MANAGED_EXACT_NAMES = {
    "s30_c05_generic_execution_reliability_v1",
    "s30_c05_effect_guard_acl_hardening_v1",
}
_core.MANAGED_EXACT_NAMES.update(S30_C05_MANAGED_EXACT_NAMES)
MANAGED_EXACT_NAMES = _core.MANAGED_EXACT_NAMES


def main() -> int:
    missing = sorted(name for name in S30_C05_MANAGED_EXACT_NAMES if not _core.managed(name))
    if missing:
        _core.fail("FAIL_CI009_S30_C05_CLASSIFICATION_EXTENSION", repr(missing))
    result = _core.main()
    print("PASS_CI009_S30_C05_CLASSIFICATION_EXTENSION=2/2")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
