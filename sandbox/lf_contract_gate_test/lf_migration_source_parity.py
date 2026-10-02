#!/usr/bin/env python3
"""CI/pass adapter for MIGRATION_SOURCE_PARITY.

The functional parity invariant lives in
migration_source_parity/migration_source_parity_core.py. This entrypoint keeps
the existing PR/CI context and public import surface while delegating the final
Git-vs-ledger comparison to that core.
"""
from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import sys

_MODULE_DIR = pathlib.Path(__file__).resolve().parent
if str(_MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(_MODULE_DIR))
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

# SADM-PP-L5-022 established post_pase_* as a governed LF_GOVERNANCE-owned
# migration family (terminal readbacks include lf_eventos #19718 and #19733).
# Classify the family, never an individual filename, while preserving the
# fail-closed unknown-family negative in the legacy context.
POST_PASE_EXTERNAL_MIGRATION_PREFIX = "post_pase_"
if POST_PASE_EXTERNAL_MIGRATION_PREFIX not in _legacy.CLASSIFIED_EXTERNAL_PREFIXES:
    _legacy.CLASSIFIED_EXTERNAL_PREFIXES = (
        *_legacy.CLASSIFIED_EXTERNAL_PREFIXES,
        POST_PASE_EXTERNAL_MIGRATION_PREFIX,
    )
if not _legacy.classified("post_pase_waiver_authority_cutover_v1"):
    _legacy.fail("FAIL_CI009_SELFTEST_POST_PASE_EXTERNAL_OWNER_FAMILY")

# INV-6.2 used the shorter input_gov_* source prefix for a governed Input
# Governance migration. PR #1450, lf_eventos #19834/#19722 and exact-version
# source-first ledger identity establish it as an authority alias of the existing
# input_governance_* family, not a filename exception.
INPUT_GOV_EXTERNAL_MIGRATION_PREFIX = "input_gov_"
if INPUT_GOV_EXTERNAL_MIGRATION_PREFIX not in _legacy.CLASSIFIED_EXTERNAL_PREFIXES:
    _legacy.CLASSIFIED_EXTERNAL_PREFIXES = (
        *_legacy.CLASSIFIED_EXTERNAL_PREFIXES,
        INPUT_GOV_EXTERNAL_MIGRATION_PREFIX,
    )
if not _legacy.classified("input_gov_recuration_authorized_screens_v1"):
    _legacy.fail("FAIL_CI009_SELFTEST_INPUT_GOV_EXTERNAL_AUTHORITY_ALIAS")

# Preserve the existing module surface for current tests/consumers. The active
# parity comparator below intentionally replaces the legacy implementation.
for _name in dir(_legacy):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_legacy, _name)


_RECONCILIATION_IDENTITY_FIELDS = {
    "reconciliation_owner_execution_id",
    "source_version",
    "source_name",
}


def _reconciliation_payload_for_parity(
    *, version: str, name: str, source_sql: str
) -> str:
    """Remove only an exact validated reconciliation metadata envelope.

    The envelope exists to classify/prove provenance for a DB-first recovery; it
    is not part of the recovered migration SQL stored in the ledger. Any
    malformed or incomplete envelope remains fail-closed and is never stripped.
    """
    if not _legacy.reconciliation_source_metadata(
        source_sql, version=version, name=name
    ):
        return source_sql

    normalized = source_sql.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.splitlines(keepends=True)
    required_keys = set(_legacy.RECONCILIATION_REQUIRED_FIELDS) | _RECONCILIATION_IDENTITY_FIELDS
    marker_seen = False
    observed_keys: set[str] = set()
    boundary: int | None = None

    for index, raw in enumerate(lines):
        stripped = raw.strip()
        if not stripped:
            if marker_seen and required_keys.issubset(observed_keys):
                boundary = index + 1
                break
            if marker_seen:
                _legacy.fail(
                    "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
                    f"version={version} name={name} premature_separator=true",
                )
            continue
        if not stripped.startswith("--"):
            break

        body = stripped[2:].strip()
        if body == _legacy.RECONCILIATION_MARKER:
            if marker_seen or observed_keys:
                _legacy.fail(
                    "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
                    f"version={version} name={name} duplicate_or_late_marker=true",
                )
            marker_seen = True
            continue

        if not marker_seen:
            _legacy.fail(
                "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
                f"version={version} name={name} marker_not_first=true",
            )
        if "=" not in body:
            _legacy.fail(
                "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
                f"version={version} name={name} unexpected_comment=true",
            )

        key, _value = body.split("=", 1)
        key = key.strip()
        if key not in required_keys:
            _legacy.fail(
                "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
                f"version={version} name={name} unexpected_field={key}",
            )
        if key in observed_keys:
            _legacy.fail(
                "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
                f"version={version} name={name} duplicate_field={key}",
            )
        observed_keys.add(key)

    if boundary is None:
        _legacy.fail(
            "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
            f"version={version} name={name} separator_missing=true",
        )

    payload = "".join(lines[boundary:])
    if not payload.strip():
        _legacy.fail(
            "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE",
            f"version={version} name={name} payload_empty=true",
        )
    return payload


def evaluate_managed_transport(local, remote, statement_counts):
    effective_local = {}
    for version, (name, source_sha, source_sql) in local.items():
        if _legacy.reconciliation_source_metadata(
            source_sql, version=version, name=name
        ):
            source_sql = _reconciliation_payload_for_parity(
                version=version, name=name, source_sql=source_sql
            )
            source_sha = hashlib.sha256(_legacy.canonical(source_sql)).hexdigest()
        effective_local[version] = (name, source_sha, source_sql)

    try:
        result = _core.evaluate_exact_parity(
            effective_local, remote, statement_counts
        )
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
