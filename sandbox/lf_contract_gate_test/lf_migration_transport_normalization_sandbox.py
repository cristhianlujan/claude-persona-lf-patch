#!/usr/bin/env python3
"""Sandbox-only comparator for migration source vs ledger transport representation.

This helper does not replace or relax the canonical LF migration parity gate.
It tests whether an exact source can explain the current ledger hash through one
of two observed storage representations:

1. DIRECT_SOURCE: the ledger stores the migration source as one source-preserving
   statement payload.
2. CLI_STATEMENT_STORAGE: a migration client parses statements, removes top-level
   delimiters and trims inter-statement boundary whitespace before persisting the
   statement array.

Version, name and ledger statement cardinality remain exact. Content mismatches
fail closed. Any future use in a canonical gate requires separate governed review
and adversarial validation.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass

VERSION_RE = re.compile(r"^20\d{12}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DOLLAR_TAG_RE = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$")


class TransportNormalizationError(ValueError):
    pass


def canonical(sql: str) -> bytes:
    """Mirror main lf_migration_source_parity.py canonicalization exactly."""
    sql = sql.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line for line in sql.split("\n") if not line.lstrip().startswith("--")]
    return "\n".join(lines).rstrip("\n").encode("utf-8")


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _is_e_string_prefix(sql: str, quote_index: int) -> bool:
    if quote_index == 0 or sql[quote_index - 1] not in "eE":
        return False
    if quote_index >= 2 and (sql[quote_index - 2].isalnum() or sql[quote_index - 2] == "_"):
        return False
    return True


def _backslash_escaped(sql: str, index: int) -> bool:
    count = 0
    j = index - 1
    while j >= 0 and sql[j] == "\\":
        count += 1
        j -= 1
    return count % 2 == 1


def split_postgres_statements(sql: str) -> list[str]:
    """Split top-level SQL statements without treating quoted semicolons as delimiters.

    The splitter is intentionally narrow and fail-closed. It supports PostgreSQL
    single/double quotes, E-strings, line comments, nested block comments and
    dollar-quoted bodies. Unterminated lexical states are rejected.
    """
    sql = sql.replace("\r\n", "\n").replace("\r", "\n")
    parts: list[str] = []
    start = 0
    i = 0
    n = len(sql)
    single = False
    single_backslash = False
    double = False
    line_comment = False
    block_depth = 0
    dollar_tag: str | None = None

    while i < n:
        if line_comment:
            if sql[i] == "\n":
                line_comment = False
            i += 1
            continue

        if block_depth:
            if sql.startswith("/*", i):
                block_depth += 1
                i += 2
                continue
            if sql.startswith("*/", i):
                block_depth -= 1
                i += 2
                continue
            i += 1
            continue

        if dollar_tag is not None:
            if sql.startswith(dollar_tag, i):
                i += len(dollar_tag)
                dollar_tag = None
                continue
            i += 1
            continue

        if single:
            if sql[i] == "'":
                if i + 1 < n and sql[i + 1] == "'":
                    i += 2
                    continue
                if single_backslash and _backslash_escaped(sql, i):
                    i += 1
                    continue
                single = False
                single_backslash = False
            i += 1
            continue

        if double:
            if sql[i] == '"':
                if i + 1 < n and sql[i + 1] == '"':
                    i += 2
                    continue
                double = False
            i += 1
            continue

        if sql.startswith("--", i):
            line_comment = True
            i += 2
            continue
        if sql.startswith("/*", i):
            block_depth = 1
            i += 2
            continue
        if sql[i] == "'":
            single = True
            single_backslash = _is_e_string_prefix(sql, i)
            i += 1
            continue
        if sql[i] == '"':
            double = True
            i += 1
            continue
        if sql[i] == "$":
            match = DOLLAR_TAG_RE.match(sql, i)
            if match:
                dollar_tag = match.group(0)
                i = match.end()
                continue
        if sql[i] == ";":
            piece = sql[start:i].strip()
            if piece:
                parts.append(piece)
            start = i + 1
        i += 1

    if single:
        raise TransportNormalizationError("UNTERMINATED_SINGLE_QUOTE")
    if double:
        raise TransportNormalizationError("UNTERMINATED_DOUBLE_QUOTE")
    if block_depth:
        raise TransportNormalizationError("UNTERMINATED_BLOCK_COMMENT")
    if dollar_tag is not None:
        raise TransportNormalizationError("UNTERMINATED_DOLLAR_QUOTE")

    tail = sql[start:].strip()
    if tail:
        parts.append(tail)
    if not parts:
        raise TransportNormalizationError("NO_SQL_STATEMENTS")
    return parts


def direct_source_hash(sql: str) -> str:
    return sha256(canonical(sql))


def cli_statement_storage_hash(sql: str) -> str:
    parts = split_postgres_statements(sql)
    return sha256(canonical("\n".join(parts)))


@dataclass(frozen=True)
class Comparison:
    version: str
    name: str
    representation: str
    remote_sha256: str
    direct_sha256: str
    cli_storage_sha256: str
    source_statement_count: int
    remote_statement_count: int

    def as_dict(self) -> dict[str, object]:
        return {
            "version": self.version,
            "name": self.name,
            "representation": self.representation,
            "remote_sha256": self.remote_sha256,
            "direct_sha256": self.direct_sha256,
            "cli_storage_sha256": self.cli_storage_sha256,
            "source_statement_count": self.source_statement_count,
            "remote_statement_count": self.remote_statement_count,
        }


def compare_exact_source(
    *,
    version: str,
    source_name: str,
    source_sql: str,
    remote_name: str,
    remote_sha256: str,
    remote_statement_count: int,
) -> Comparison:
    if not VERSION_RE.fullmatch(version):
        raise TransportNormalizationError("VERSION_INVALID")
    if not source_name or remote_name != source_name:
        raise TransportNormalizationError("NAME_MISMATCH")
    if not SHA256_RE.fullmatch(remote_sha256):
        raise TransportNormalizationError("REMOTE_SHA256_INVALID")
    if not isinstance(remote_statement_count, int) or remote_statement_count < 1:
        raise TransportNormalizationError("REMOTE_STATEMENT_COUNT_INVALID")

    parts = split_postgres_statements(source_sql)
    source_statement_count = len(parts)
    direct = direct_source_hash(source_sql)
    cli_storage = sha256(canonical("\n".join(parts)))

    if remote_sha256 == direct:
        if remote_statement_count != 1:
            raise TransportNormalizationError(
                f"DIRECT_STORAGE_STATEMENT_COUNT_MISMATCH:remote={remote_statement_count}:expected=1"
            )
        representation = "DIRECT_SOURCE"
    elif remote_sha256 == cli_storage:
        if remote_statement_count != source_statement_count:
            raise TransportNormalizationError(
                "CLI_STORAGE_STATEMENT_COUNT_MISMATCH:"
                f"remote={remote_statement_count}:source={source_statement_count}"
            )
        representation = "CLI_STATEMENT_STORAGE"
    else:
        raise TransportNormalizationError(
            f"CONTENT_MISMATCH:remote={remote_sha256}:direct={direct}:cli={cli_storage}"
        )

    return Comparison(
        version=version,
        name=source_name,
        representation=representation,
        remote_sha256=remote_sha256,
        direct_sha256=direct,
        cli_storage_sha256=cli_storage,
        source_statement_count=source_statement_count,
        remote_statement_count=remote_statement_count,
    )
