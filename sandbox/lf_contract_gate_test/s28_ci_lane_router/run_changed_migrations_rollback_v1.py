#!/usr/bin/env python3
"""Prepare changed LF migrations for a rollback-only sandbox probe.

The exact source artifact is always bound by SHA-256. For the repository's
canonical single outer transaction frame (BEGIN/COMMIT), CI removes only those
two framing statements so the unchanged interior candidate material can run
inside the probe's own BEGIN/ROLLBACK envelope. Any other transaction control
or non-transaction-safe statement fails closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "lf-db-candidate-rollback-probe/v3"
MIGRATION_PREFIX = "supabase/migrations/"
ACTOR_BOOTSTRAP_REGISTRY_PATH = Path(
    "sandbox/lf_contract_gate_test/s28_ci_lane_router/"
    "lf_ci_candidate_actor_bootstrap_registry_v1.json"
)
ACTOR_MARKER_RE = re.compile(
    r"(?m)^--[ \t]*LF_CI_ROLLBACK_GOVERNED_ACTOR_V1:[ \t]*"
    r"([A-Z0-9][A-Z0-9_-]{2,119})[ \t]*$"
)

TX_STMT = re.compile(
    r"(?im)^[ \t]*(BEGIN(?:[ \t]+TRANSACTION)?|START[ \t]+TRANSACTION|COMMIT|ROLLBACK)[ \t]*;"
)
FORBIDDEN_TOP_LEVEL = (
    re.compile(r"^\s*VACUUM\b", re.I | re.M),
    re.compile(r"^\s*ALTER\s+SYSTEM\b", re.I | re.M),
    re.compile(r"^\s*(?:CREATE|DROP)\s+DATABASE\b", re.I | re.M),
    re.compile(
        r"^\s*(?:CREATE\s+(?:UNIQUE\s+)?INDEX|DROP\s+INDEX|REINDEX\b[^;]*)\s+CONCURRENTLY\b",
        re.I | re.M,
    ),
    re.compile(r"^\s*REFRESH\s+MATERIALIZED\s+VIEW\s+CONCURRENTLY\b", re.I | re.M),
)


class ProbeError(ValueError):
    pass


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_blob_sha(repo: Path, path: str) -> str:
    value = subprocess.check_output(
        ["git","-C",str(repo),"hash-object","--",path],
        text=True,
    ).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ProbeError(f"FAIL_DB_CANDIDATE_GIT_BLOB_SHA:{path}:{value}")
    return value


def migration_identity(path: str) -> tuple[str, str]:
    name = Path(path).name
    match = re.fullmatch(r"([0-9]{14})_([A-Za-z0-9_]+)\.sql", name)
    if not match:
        raise ProbeError(f"FAIL_DB_CANDIDATE_MIGRATION_NAME_INVALID:{path}")
    return match.group(1), match.group(2)


def changed_migrations(repo: Path, base: str, head: str) -> list[tuple[str, str]]:
    raw = subprocess.check_output(
        [
            "git",
            "-C",
            str(repo),
            "diff",
            "--name-status",
            "--no-renames",
            base,
            head,
            "--",
            "supabase/migrations",
        ],
        text=True,
    )
    rows: list[tuple[str, str]] = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise ProbeError(f"FAIL_DB_CANDIDATE_DIFF_SHAPE:{line}")
        status, path = parts
        if not path.startswith(MIGRATION_PREFIX) or not path.endswith(".sql"):
            continue
        if status not in {"A", "M"}:
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_NON_ADDITIVE_OR_MODIFIED:{status}:{path}"
            )
        rows.append((status, path))
    if not rows:
        raise ProbeError("FAIL_DB_CANDIDATE_NO_CHANGED_MIGRATIONS")
    return sorted(rows, key=lambda x: x[1])


def strip_non_code(sql: str) -> str:
    """Blank comments/string/dollar bodies while preserving offsets/newlines."""
    out = list(sql)
    n = len(sql)
    i = 0
    while i < n:
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            if j < 0:
                j = n
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            if j < 0:
                raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_BLOCK_COMMENT")
            for k in range(i, j + 2):
                if out[k] != "\n":
                    out[k] = " "
            i = j + 2
            continue
        if sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_STRING")
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        if sql[i] == "$":
            m = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[i:])
            if m:
                tag = m.group(0)
                j = sql.find(tag, i + len(tag))
                if j < 0:
                    raise ProbeError("FAIL_DB_CANDIDATE_UNTERMINATED_DOLLAR_QUOTE")
                end = j + len(tag)
                for k in range(i, end):
                    if out[k] != "\n":
                        out[k] = " "
                i = end
                continue
        i += 1
    return "".join(out)


def _tx_kind(match: re.Match[str]) -> str:
    return re.sub(r"\s+", " ", match.group(1).upper()).strip()


def _blank_span_preserve_newlines(text: str, start: int, end: int) -> str:
    chars = list(text)
    for i in range(start, end):
        if chars[i] != "\n":
            chars[i] = " "
    return "".join(chars)


def prepare_transaction_payload(path: str, text: str) -> tuple[str, dict[str, Any]]:
    """Return transaction-safe probe payload plus explicit frame provenance."""
    code = strip_non_code(text)
    tx = list(TX_STMT.finditer(code))

    if not tx:
        payload = text
        frame: dict[str, Any] = {
            "mode": "NONE",
            "source_transaction_statements": 0,
            "interior_material_preserved": True,
        }
    else:
        kinds = [_tx_kind(m) for m in tx]
        outer_begin = kinds[0] in {"BEGIN", "BEGIN TRANSACTION", "START TRANSACTION"}
        outer_commit = kinds[-1] == "COMMIT"
        only_outer_pair = len(tx) == 2 and outer_begin and outer_commit
        prefix_empty = code[: tx[0].start()].strip() == ""
        suffix_empty = code[tx[-1].end() :].strip() == ""

        if not (only_outer_pair and prefix_empty and suffix_empty):
            raise ProbeError(
                f"BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL:{path}:"
                f"kinds={','.join(kinds)}"
            )

        payload = _blank_span_preserve_newlines(text, tx[0].start(), tx[0].end())
        payload = _blank_span_preserve_newlines(
            payload, tx[-1].start(), tx[-1].end()
        )
        frame = {
            "mode": "SINGLE_OUTER_BEGIN_COMMIT_NORMALIZED",
            "source_transaction_statements": 2,
            "source_open_kind": kinds[0],
            "source_close_kind": kinds[-1],
            "open_span": [tx[0].start(), tx[0].end()],
            "close_span": [tx[-1].start(), tx[-1].end()],
            "interior_material_preserved": True,
        }

    payload_code = strip_non_code(payload)
    residual_tx = list(TX_STMT.finditer(payload_code))
    if residual_tx:
        kinds = ",".join(_tx_kind(m) for m in residual_tx)
        raise ProbeError(
            f"BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL_REMAINS:{path}:{kinds}"
        )

    for pattern in FORBIDDEN_TOP_LEVEL:
        hit = pattern.search(payload_code)
        if hit:
            snippet = payload_code[hit.start() : hit.end() + 80].splitlines()[0][:160]
            raise ProbeError(
                f"BLOCK_DB_CANDIDATE_NONTRANSACTIONAL:{path}:{snippet}"
            )

    frame["source_sha256"] = sha(text.encode("utf-8"))
    frame["execution_payload_sha256"] = sha(payload.encode("utf-8"))
    frame["source_bytes"] = len(text.encode("utf-8"))
    frame["execution_payload_bytes"] = len(payload.encode("utf-8"))
    return payload, frame


def validate_transaction_safe(path: str, text: str) -> None:
    prepare_transaction_payload(path, text)



def load_actor_bootstrap_registry(repo: Path) -> dict[str, dict[str, Any]]:
    path = repo / ACTOR_BOOTSTRAP_REGISTRY_PATH
    if not path.is_file():
        raise ProbeError(
            f"FAIL_DB_CANDIDATE_ACTOR_REGISTRY_MISSING:{ACTOR_BOOTSTRAP_REGISTRY_PATH}"
        )
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ProbeError("FAIL_DB_CANDIDATE_ACTOR_REGISTRY_INVALID") from exc
    if raw.get("schema_version") != "lf-ci-candidate-actor-bootstrap-registry/v1":
        raise ProbeError("FAIL_DB_CANDIDATE_ACTOR_REGISTRY_VERSION")
    entries = raw.get("entries")
    if not isinstance(entries, dict):
        raise ProbeError("FAIL_DB_CANDIDATE_ACTOR_REGISTRY_ENTRIES")
    normalized: dict[str, dict[str, Any]] = {}
    for operation_code, entry in entries.items():
        if not isinstance(operation_code, str) or not re.fullmatch(
            r"[A-Z0-9][A-Z0-9_-]{2,119}", operation_code
        ):
            raise ProbeError("FAIL_DB_CANDIDATE_ACTOR_REGISTRY_OPERATION_CODE")
        if not isinstance(entry, dict):
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_ACTOR_REGISTRY_ENTRY:{operation_code}"
            )
        if entry.get("adapter") != "RUNTIME_UPDATE_BEGIN_V1":
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_ACTOR_ADAPTER_UNSUPPORTED:{operation_code}"
            )
        if entry.get("begin_rpc") != "public.lf_runtime_update_begin_v1":
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_ACTOR_RPC_UNSUPPORTED:{operation_code}"
            )
        target_code = entry.get("target_code")
        target_repo = entry.get("target_repo")
        if not isinstance(target_code, str) or not re.fullmatch(
            r"[A-Z0-9][A-Z0-9_-]{2,119}", target_code
        ):
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_ACTOR_TARGET_CODE:{operation_code}"
            )
        if not isinstance(target_repo, str) or not target_repo.strip():
            raise ProbeError(
                f"FAIL_DB_CANDIDATE_ACTOR_TARGET_REPO:{operation_code}"
            )
        normalized[operation_code] = dict(entry)
    return normalized


def governed_actor_marker(
    path: str, text: str, registry: dict[str, dict[str, Any]]
) -> tuple[str, dict[str, Any]] | None:
    matches = ACTOR_MARKER_RE.findall(text)
    if not matches:
        return None
    if len(matches) != 1:
        raise ProbeError(f"FAIL_DB_CANDIDATE_ACTOR_MARKER_DUPLICATE:{path}")
    operation_code = matches[0]
    entry = registry.get(operation_code)
    if entry is None:
        raise ProbeError(
            f"FAIL_DB_CANDIDATE_ACTOR_OPERATION_UNREGISTERED:{path}:{operation_code}"
        )
    return operation_code, entry


def _sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def render_governed_actor_bootstrap(
    *,
    path: str,
    migration_version: str,
    source_digest: str,
    operation_code: str,
    entry: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    if entry.get("adapter") != "RUNTIME_UPDATE_BEGIN_V1":
        raise ProbeError(
            f"FAIL_DB_CANDIDATE_ACTOR_ADAPTER_UNSUPPORTED:{operation_code}"
        )
    execution_id = (
        f"CI-DB-CANDIDATE-{migration_version}-{source_digest[:16]}"
    )
    idempotency_key = (
        f"ci-db-candidate:{migration_version}:{source_digest[:16]}"
    )
    manifest = {
        "ci_candidate_rollback_actor": True,
        "production_apply_authorized": True,
        "runtime_activation_authorized": False,
        "source_candidate_only": False,
        "candidate_source_sha256": source_digest,
    }
    manifest_sql = _sql_literal(
        json.dumps(manifest, sort_keys=True, separators=(",", ":"))
    )
    sql = f"""\echo LF_DB_CANDIDATE_ACTOR_BEGIN {operation_code} execution_id={execution_id}
DO $lf_ci_actor$
DECLARE
  r jsonb;
BEGIN
  r:=public.lf_runtime_update_begin_v1(
    {_sql_literal(execution_id)},
    {_sql_literal(idempotency_key)},
    {_sql_literal(source_digest)},
    {_sql_literal(execution_id)},
    {_sql_literal(str(entry['target_repo']))},
    {_sql_literal(path)},
    {manifest_sql}::jsonb
  );
  IF r->>'result' NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_DB_CANDIDATE_ACTOR_BEGIN_FAILED:%:%',
      {_sql_literal(operation_code)},coalesce(r->>'result','NULL');
  END IF;
END
$lf_ci_actor$;
\echo LF_DB_CANDIDATE_ACTOR_READY {operation_code} execution_id={execution_id}"""
    return sql, {
        "operation_code": operation_code,
        "adapter": entry["adapter"],
        "begin_rpc": entry["begin_rpc"],
        "target_code": entry["target_code"],
        "target_repo": entry["target_repo"],
        "target_path": path,
        "execution_id": execution_id,
        "request_sha256": source_digest,
    }


def render_actor_residue_check(actor_rows: list[dict[str, Any]]) -> str | None:
    if not actor_rows:
        return None
    ids = ",".join(_sql_literal(str(row["execution_id"])) for row in actor_rows)
    return f"""DO $lf_ci_actor_residue$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id IN ({ids})
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_CANDIDATE_ACTOR_RESIDUE';
  END IF;
END
$lf_ci_actor_residue$;"""

def _failure_manifest(args: argparse.Namespace, exc: ProbeError) -> None:
    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    raw = str(exc)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "status": "BLOCKED",
        "base_sha": args.base,
        "head_sha": args.head,
        "blocking_code": raw.split(":", 1)[0],
        "error": raw,
        "transaction_escape_scan": "BLOCKED",
    }
    manifest_out.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _build(args: argparse.Namespace) -> dict[str, Any]:
    repo = Path(args.repo_root).resolve()
    rows = changed_migrations(repo, args.base, args.head)
    actor_registry = load_actor_bootstrap_registry(repo)
    actor_rows: list[dict[str, Any]] = []
    manifest_rows = []
    chunks = [
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "SET LOCAL statement_timeout = '120s';",
        "SET LOCAL lock_timeout = '15s';",
    ]

    for status, path in rows:
        target = repo / path
        raw = target.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProbeError(f"FAIL_DB_CANDIDATE_NON_UTF8:{path}") from exc

        payload, frame = prepare_transaction_payload(path, text)
        source_digest = sha(raw)
        payload_digest = sha(payload.encode("utf-8"))
        if frame["source_sha256"] != source_digest:
            raise ProbeError(f"FAIL_DB_CANDIDATE_SOURCE_DIGEST_INTERNAL:{path}")
        if frame["execution_payload_sha256"] != payload_digest:
            raise ProbeError(f"FAIL_DB_CANDIDATE_PAYLOAD_DIGEST_INTERNAL:{path}")

        migration_version, migration_name = migration_identity(path)
        actor_marker = governed_actor_marker(path, text, actor_registry)
        actor_row = None
        if actor_marker is not None:
            operation_code, actor_entry = actor_marker
            actor_sql, actor_row = render_governed_actor_bootstrap(
                path=path,
                migration_version=migration_version,
                source_digest=source_digest,
                operation_code=operation_code,
                entry=actor_entry,
            )
            chunks.append(actor_sql)
            actor_rows.append(actor_row)
        manifest_rows.append(
            {
                "status": status,
                "path": path,
                "migration_version": migration_version,
                "migration_name": migration_name,
                "source_sha256": source_digest,
                "source_git_blob_sha1": git_blob_sha(repo, path),
                "source_bytes": len(raw),
                "execution_payload_sha256": payload_digest,
                "transaction_frame": frame,
                "governed_actor_bootstrap": actor_row,
            }
        )
        chunks.extend(
            [
                (
                    f"\\echo LF_DB_CANDIDATE_BEGIN {path} "
                    f"source_sha256={source_digest} payload_sha256={payload_digest} "
                    f"frame={frame['mode']}"
                ),
                payload,
                (
                    f"\\echo LF_DB_CANDIDATE_APPLIED {path} "
                    f"source_sha256={source_digest} payload_sha256={payload_digest}"
                ),
            ]
        )

    probe_rows = []
    probe_only_chunks = [
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "SET LOCAL statement_timeout = '120s';",
        "SET LOCAL lock_timeout = '15s';",
    ]
    for probe_rel in args.probe_sql:
        probe_path = repo / probe_rel
        if not probe_path.is_file():
            raise ProbeError(f"FAIL_DB_CANDIDATE_PROBE_MISSING:{probe_rel}")
        raw_probe = probe_path.read_bytes()
        try:
            probe_text = raw_probe.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProbeError(f"FAIL_DB_CANDIDATE_PROBE_NON_UTF8:{probe_rel}") from exc

        probe_payload, probe_frame = prepare_transaction_payload(
            probe_rel, probe_text
        )
        source_digest = sha(raw_probe)
        payload_digest = sha(probe_payload.encode("utf-8"))
        probe_rows.append(
            {
                "path": probe_rel,
                "source_sha256": source_digest,
                "source_bytes": len(raw_probe),
                "execution_payload_sha256": payload_digest,
                "transaction_frame": probe_frame,
            }
        )
        probe_chunk = [
            (
                f"\\echo LF_DB_CANDIDATE_PROBE_BEGIN {probe_rel} "
                f"source_sha256={source_digest} payload_sha256={payload_digest}"
            ),
            probe_payload,
            (
                f"\\echo LF_DB_CANDIDATE_PROBE_PASS {probe_rel} "
                f"source_sha256={source_digest} payload_sha256={payload_digest}"
            ),
        ]
        chunks.extend(probe_chunk)
        probe_only_chunks.extend(probe_chunk)

    chunks.extend(
        [
            "SELECT 'LF_DB_CANDIDATE_ALL_APPLIED_BEFORE_ROLLBACK' AS probe_result;",
            "ROLLBACK;",
            "SELECT 'LF_DB_CANDIDATE_ROLLBACK_COMPLETE' AS probe_result;",
        ]
    )
    residue_check = render_actor_residue_check(actor_rows)
    if residue_check is not None:
        chunks.append(residue_check)
        chunks.append(
            "SELECT 'LF_DB_CANDIDATE_ACTOR_ROLLBACK_CLEAN' AS probe_result;"
        )
    sql_out = Path(args.sql_out)
    sql_out.parent.mkdir(parents=True, exist_ok=True)
    sql_out.write_text("\n".join(chunks) + "\n", encoding="utf-8")

    probe_only_chunks.extend(
        [
            "SELECT 'LF_DB_ALREADY_APPLIED_EXACT_PROBES_COMPLETE' AS probe_result;",
            "ROLLBACK;",
            "SELECT 'LF_DB_ALREADY_APPLIED_EXACT_ROLLBACK_COMPLETE' AS probe_result;",
        ]
    )
    probe_only_sha = None
    if args.probe_only_sql_out:
        probe_only_out = Path(args.probe_only_sql_out)
        probe_only_out.parent.mkdir(parents=True, exist_ok=True)
        probe_only_out.write_text("\n".join(probe_only_chunks) + "\n", encoding="utf-8")
        probe_only_sha = sha(probe_only_out.read_bytes())

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "status": "READY",
        "base_sha": args.base,
        "head_sha": args.head,
        "migration_count": len(manifest_rows),
        "migrations": manifest_rows,
        "combined_sql_sha256": sha(sql_out.read_bytes()),
        "probe_only_sql_sha256": probe_only_sha,
        "transaction_escape_scan": "PASS",
        "post_apply_probes": probe_rows,
        "governed_actor_bootstraps": actor_rows,
        "actor_bootstrap_registry": str(ACTOR_BOOTSTRAP_REGISTRY_PATH),
        "source_material_binding": "EXACT_SOURCE_SHA_WITH_EXPLICIT_OUTER_FRAME_NORMALIZATION",
    }
    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--repo-root", default=".")
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--sql-out", required=True)
    p.add_argument("--manifest-out", required=True)
    p.add_argument("--probe-only-sql-out")
    p.add_argument("--probe-sql", action="append", default=[])
    args = p.parse_args()

    try:
        manifest = _build(args)
    except ProbeError as exc:
        _failure_manifest(args, exc)
        print(str(exc))
        return 2

    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
