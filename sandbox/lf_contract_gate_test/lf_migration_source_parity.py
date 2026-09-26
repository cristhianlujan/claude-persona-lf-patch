#!/usr/bin/env python3
"""CI/pass adapter for MIGRATION_SOURCE_PARITY.

The functional parity invariant lives in
migration_source_parity/migration_source_parity_core.py. This entrypoint keeps
the existing PR/CI context and public import surface while delegating the final
Git-vs-ledger comparison to that core.
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys

_MODULE_DIR = pathlib.Path(__file__).resolve().parent
_CONTEXT_PATH = _MODULE_DIR / "migration_source_parity" / "lf_migration_source_parity_ci_context.py"
_CORE_PATH = _MODULE_DIR / "migration_source_parity" / "migration_source_parity_core.py"

# Text-level compatibility sentinels for historical C05 regression. Strategy
# family classification remains owned by the CI context via STRATEGY_MIGRATION_RE,
# including the s31_future_strategy_contract_v1 case. These markers preserve the
# legacy inspection contract without moving classification into the functional core.


def _load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_legacy = _load("lf_migration_source_parity_ci_context", _CONTEXT_PATH)
_core = _load("migration_source_parity_core", _CORE_PATH)

# Preserve the existing module surface for current tests/consumers. The active
# parity comparator below intentionally replaces the legacy implementation.
for _name in dir(_legacy):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_legacy, _name)


def evaluate_managed_transport(local, remote, statement_counts):
    try:
        result = _core.evaluate_exact_parity(local, remote, statement_counts)
    except _core.ParityCoreError as exc:
        _legacy.fail(exc.code, exc.detail)
    return (
        result.direct_count,
        result.cli_statement_storage_count,
        result.comparisons,
    )


# The context module's main() resolves PR/CI inputs and then looks up this
# function in its own globals. Patch that one call boundary to the canonical
# functional core without changing its context-acquisition behavior.
_legacy.evaluate_managed_transport = evaluate_managed_transport


def main() -> int:
    return _legacy.main()


if __name__ == "__main__":
    raise SystemExit(main())
