from __future__ import annotations

import json
import os
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class JobStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.RLock()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("pragma journal_mode = WAL")
        connection.execute("pragma synchronous = FULL")
        return connection

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(self.path.parent, 0o700)
        with self._lock, self._connect() as db:
            db.execute(
                """
                create table if not exists jobs (
                    job_id text primary key,
                    external_key text not null unique,
                    kind text not null,
                    status text not null,
                    request_meta_json text not null,
                    result_json text,
                    error_json text,
                    submitted_at text not null,
                    started_at text,
                    completed_at text
                )
                """
            )
            db.execute("create index if not exists jobs_status_idx on jobs(status)")
        os.chmod(self.path, 0o600)

    def recover_incomplete(self) -> int:
        error = json.dumps(
            {
                "code": "SERVICE_RESTARTED",
                "detail": "incomplete job recovered fail-closed",
            }
        )
        with self._lock, self._connect() as db:
            cursor = db.execute(
                "update jobs set status='FAILED', error_json=?, completed_at=? "
                "where status in ('QUEUED','RUNNING')",
                (error, utc_now()),
            )
            return int(cursor.rowcount)

    def create(
        self, *, external_key: str, kind: str, request_meta: dict[str, Any]
    ) -> tuple[dict[str, Any], bool]:
        self.initialize()
        with self._lock, self._connect() as db:
            existing = db.execute(
                "select * from jobs where external_key=?", (external_key,)
            ).fetchone()
            if existing is not None:
                return self._row(existing), True
            job_id = str(uuid.uuid4())
            db.execute(
                "insert into jobs(job_id,external_key,kind,status,request_meta_json,submitted_at) "
                "values(?,?,?,?,?,?)",
                (
                    job_id,
                    external_key,
                    kind,
                    "QUEUED",
                    json.dumps(request_meta, ensure_ascii=False, sort_keys=True),
                    utc_now(),
                ),
            )
            row = db.execute("select * from jobs where job_id=?", (job_id,)).fetchone()
            assert row is not None
            return self._row(row), False

    def start(self, job_id: str) -> None:
        self._update(job_id, status="RUNNING", started_at=utc_now())

    def complete(self, job_id: str, result: dict[str, Any]) -> None:
        self._update(
            job_id,
            status="COMPLETED",
            result_json=json.dumps(result, ensure_ascii=False, sort_keys=True),
            completed_at=utc_now(),
        )

    def fail(self, job_id: str, error: dict[str, Any]) -> None:
        self._update(
            job_id,
            status="FAILED",
            error_json=json.dumps(error, ensure_ascii=False, sort_keys=True),
            completed_at=utc_now(),
        )

    def _update(self, job_id: str, **fields: str) -> None:
        if not fields:
            return
        allowed = {"status", "result_json", "error_json", "started_at", "completed_at"}
        if not set(fields).issubset(allowed):
            raise ValueError("JOB_UPDATE_FIELD_INVALID")
        columns = ", ".join(f"{name}=?" for name in fields)
        values = list(fields.values()) + [job_id]
        with self._lock, self._connect() as db:
            cursor = db.execute(f"update jobs set {columns} where job_id=?", values)
            if cursor.rowcount != 1:
                raise KeyError(job_id)

    def get(self, job_id: str) -> dict[str, Any] | None:
        self.initialize()
        with self._lock, self._connect() as db:
            row = db.execute("select * from jobs where job_id=?", (job_id,)).fetchone()
            return self._row(row) if row is not None else None

    def stats(self) -> dict[str, int]:
        self.initialize()
        with self._lock, self._connect() as db:
            rows = db.execute(
                "select status, count(*) as count from jobs group by status"
            ).fetchall()
        return {str(row["status"]): int(row["count"]) for row in rows}

    @staticmethod
    def _row(row: sqlite3.Row) -> dict[str, Any]:
        result = dict(row)
        for source, target in (
            ("request_meta_json", "request_meta"),
            ("result_json", "result"),
            ("error_json", "error"),
        ):
            raw = result.pop(source, None)
            result[target] = json.loads(raw) if raw else None
        return result
