#!/usr/bin/env python3
"""LF Contract Check v0.16: governed strategy-path wrapper over exact v0.15."""
from __future__ import annotations
import importlib.util
from pathlib import Path

LEGACY_PATH = Path(__file__).with_name("lf_contract_check_v015.py")
LEGACY_EXACT_PATH = "scripts/lf_contract_check_v015.py"
STRATEGY_PREFIX = "strategies/"

_spec = importlib.util.spec_from_file_location("lf_contract_check_v015", LEGACY_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("FAIL_V016_LEGACY_LOAD")
_legacy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_legacy)

if STRATEGY_PREFIX not in _legacy.GOVERNED_PREFIXES:
    _legacy.GOVERNED_PREFIXES.append(STRATEGY_PREFIX)
_legacy.ALLOWED_EXACT.add(LEGACY_EXACT_PATH)

for _name in dir(_legacy):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_legacy, _name)

_original_validate_changed_files = _legacy.validate_changed_files


def validate_strategy_governed_scope() -> None:
    failures: list[str] = []
    canonical = "strategies/LF_SAMPLE_STRATEGY.yaml"
    lookalike = "strategy/LF_SAMPLE_STRATEGY.yaml"
    helper_lookalike = LEGACY_EXACT_PATH + ".bak"
    if STRATEGY_PREFIX not in GOVERNED_PREFIXES:
        failures.append("strategies_prefix_missing_from_governed")
    if STRATEGY_PREFIX in ALLOWED_PREFIXES:
        failures.append("strategies_must_not_bypass_receipt_via_allowed_prefix")
    if not is_governed_path(canonical):
        failures.append("canonical_strategy_not_governed")
    if is_allowed_path(canonical):
        failures.append("canonical_strategy_directly_allowed_without_receipt")
    if is_governed_path(lookalike):
        failures.append("strategy_lookalike_unexpectedly_governed")
    if not is_allowed_path(LEGACY_EXACT_PATH):
        failures.append("legacy_exact_helper_not_allowed")
    if is_allowed_path(helper_lookalike):
        failures.append("legacy_helper_lookalike_unexpectedly_allowed")
    if failures:
        fail("FAIL_STRATEGY_GOVERNED_SCOPE_INVARIANT", ",".join(failures))
    print("PASS_STRATEGY_GOVERNED_SCOPE_INVARIANT: strategy receipt-required; exact legacy helper only")


def validate_changed_files(changed_files: list[str]) -> list[str]:
    validate_strategy_governed_scope()
    return _original_validate_changed_files(changed_files)


_legacy.validate_changed_files = validate_changed_files


def main() -> None:
    _legacy.main()


if __name__ == "__main__":
    main()
