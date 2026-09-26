#!/usr/bin/env python3
"""Pure functional core for MIGRATION_SOURCE_PARITY.

This module compares an already-resolved Git migration snapshot with an
already-resolved Supabase migration-ledger snapshot. It has no knowledge of
pull requests, workflows, CI routing, GitHub environment variables, database
connections, or process execution.

Callers are responsible for acquiring the two snapshots. The core owns only
the parity invariant: exact version/name/content equivalence under the
canonical transport representation comparator.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass

import migration_transport_normalization as transport

SCHEMA_VERSION = "lf-migration-source-parity-result/v1"


class ParityCoreError(ValueError):
    """Typed fail-closed parity failure."""

    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class ParityResult:
    schema_version: str
    status: str
    code: str
    version_count: int
    direct_count: int
    cli_statement_storage_count: int
    comparisons: dict[str, transport.Comparison]

    def as_dict(self) -> dict[str, object]:
        payload = asdict(self)
        payload["comparisons"] = {
            version: comparison.as_dict()
            for version, comparison in self.comparisons.items()
        }
        return payload


def _raise(code: str, detail: str = "") -> None:
    raise ParityCoreError(code, detail)


def evaluate_exact_parity(
    local: dict[str, tuple[str, str, str]],
    remote: dict[str, tuple[str, str]],
    statement_counts: dict[str, int],
) -> ParityResult:
    """Compare exact Git source against exact ledger identity/content.

    local maps version -> (name, direct_source_sha256, source_sql)
    remote maps version -> (name, remote_content_sha256)
    statement_counts maps version -> ledger statement cardinality
    """
    local_versions = set(local)
    remote_versions = set(remote)
    if local_versions != remote_versions:
        _raise(
            "FAIL_LF_MIGRATION_VERSION_PARITY",
            f"remote_only={sorted(remote_versions-local_versions)} "
            f"local_only={sorted(local_versions-remote_versions)}",
        )

    if set(statement_counts) != remote_versions:
        _raise(
            "FAIL_LF_MIGRATION_STATEMENT_COUNT_SET",
            f"missing={sorted(remote_versions-set(statement_counts))} "
            f"extra={sorted(set(statement_counts)-remote_versions)}",
        )

    name_mismatches = [
        version
        for version in sorted(local_versions)
        if local[version][0] != remote[version][0]
    ]
    if name_mismatches:
        _raise("FAIL_LF_MIGRATION_NAME_PARITY", repr(name_mismatches))

    comparisons: dict[str, transport.Comparison] = {}
    failures: list[tuple[str, str]] = []
    for version in sorted(local_versions):
        name, source_sha, source_sql = local[version]
        remote_name, remote_sha = remote[version]
        try:
            comparison = transport.compare_exact_source(
                version=version,
                source_name=name,
                source_sql=source_sql,
                remote_name=remote_name,
                remote_sha256=remote_sha,
                remote_statement_count=statement_counts[version],
            )
        except transport.TransportNormalizationError as exc:
            failures.append((version, str(exc)))
            continue
        if comparison.direct_sha256 != source_sha:
            failures.append((version, "LOCAL_DIRECT_SHA_INTERNAL_MISMATCH"))
            continue
        comparisons[version] = comparison

    if failures:
        _raise("FAIL_LF_MIGRATION_CONTENT_PARITY", repr(failures))

    direct_count = sum(
        item.representation == "DIRECT_SOURCE"
        for item in comparisons.values()
    )
    cli_count = sum(
        item.representation == "CLI_STATEMENT_STORAGE"
        for item in comparisons.values()
    )
    return ParityResult(
        schema_version=SCHEMA_VERSION,
        status="PASS",
        code="PASS_LF_MIGRATION_SOURCE_PARITY",
        version_count=len(comparisons),
        direct_count=direct_count,
        cli_statement_storage_count=cli_count,
        comparisons=comparisons,
    )
