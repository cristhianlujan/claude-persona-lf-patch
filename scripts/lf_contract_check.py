#!/usr/bin/env python3
"""LF Contract Check v0.17: Strategy Factory governed-scope wrapper over exact v0.16."""
from __future__ import annotations

import importlib.util
from pathlib import Path

LEGACY_PATH = Path(__file__).with_name("lf_contract_check_v016.py")
LEGACY_EXACT_PATH = "scripts/lf_contract_check_v016.py"
STRATEGY_PREFIX = "strategies/"
REPOSITORY_GOVERNANCE_PREFIX = "gobernanza/repositorios/"

_spec = importlib.util.spec_from_file_location("lf_contract_check_v016", LEGACY_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("FAIL_V017_LEGACY_LOAD")
_legacy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_legacy)

# Strategy Factory source and generated strategy artifacts are governed surfaces:
# they require an LF operation receipt and are never direct allowlist bypasses.
for _prefix in (STRATEGY_PREFIX, REPOSITORY_GOVERNANCE_PREFIX):
    if _prefix not in _legacy.GOVERNED_PREFIXES:
        _legacy.GOVERNED_PREFIXES.append(_prefix)
_legacy.ALLOWED_EXACT.add(LEGACY_EXACT_PATH)

for _name in dir(_legacy):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_legacy, _name)

_original_validate_changed_files = _legacy.validate_changed_files


def validate_s30_strategy_factory_scope() -> None:
    failures: list[str] = []
    strategy = "strategies/LF_SAMPLE_STRATEGY.yaml"
    strategy_lookalike = "strategy/LF_SAMPLE_STRATEGY.yaml"
    repo_matrix = "gobernanza/repositorios/matriz_repos_lf.yaml"
    repo_lookalike = "gobernanza/repositorio/matriz_repos_lf.yaml"
    helper_lookalike = LEGACY_EXACT_PATH + ".bak"

    for prefix in (STRATEGY_PREFIX, REPOSITORY_GOVERNANCE_PREFIX):
        if prefix not in GOVERNED_PREFIXES:
            failures.append(f"governed_prefix_missing:{prefix}")
        if prefix in ALLOWED_PREFIXES:
            failures.append(f"governed_prefix_must_not_bypass_receipt:{prefix}")

    if not is_governed_path(strategy):
        failures.append("canonical_strategy_not_governed")
    if is_allowed_path(strategy):
        failures.append("canonical_strategy_directly_allowed_without_receipt")
    if is_governed_path(strategy_lookalike):
        failures.append("strategy_lookalike_unexpectedly_governed")

    if not is_governed_path(repo_matrix):
        failures.append("repo_matrix_not_governed")
    if is_allowed_path(repo_matrix):
        failures.append("repo_matrix_directly_allowed_without_receipt")
    if is_governed_path(repo_lookalike):
        failures.append("repo_matrix_lookalike_unexpectedly_governed")

    if not is_allowed_path(LEGACY_EXACT_PATH):
        failures.append("v016_exact_helper_not_allowed")
    if is_allowed_path(helper_lookalike):
        failures.append("v016_helper_lookalike_unexpectedly_allowed")

    if failures:
        fail("FAIL_S30_STRATEGY_FACTORY_SCOPE_INVARIANT", ",".join(failures))
    print(
        "PASS_S30_STRATEGY_FACTORY_SCOPE_INVARIANT: "
        "strategies and repository-governance are receipt-required; exact v0.16 helper only"
    )


def validate_changed_files(changed_files: list[str]) -> list[str]:
    validate_s30_strategy_factory_scope()
    return _original_validate_changed_files(changed_files)


_legacy.validate_changed_files = validate_changed_files


def main() -> None:
    _legacy.main()


if __name__ == "__main__":
    main()
