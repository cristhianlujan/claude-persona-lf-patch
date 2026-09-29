#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "LF_DB_SCHEMA_DRIFT_AUDIT_V1"


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def load_rows(path: Path) -> dict[tuple[str, str], Any]:
    rows: dict[tuple[str, str], Any] = {}
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"INVALID_JSONL:{path}:{line_no}:{exc.msg}") from exc
        if not isinstance(row, dict):
            raise ValueError(f"ROW_NOT_OBJECT:{path}:{line_no}")
        kind = row.get("kind")
        identity = row.get("identity")
        if not isinstance(kind, str) or not kind or not isinstance(identity, str) or not identity:
            raise ValueError(f"ROW_IDENTITY_INVALID:{path}:{line_no}")
        key = (kind, identity)
        if key in rows:
            raise ValueError(f"DUPLICATE_IDENTITY:{path}:{kind}:{identity}")
        rows[key] = row.get("definition")
    return rows


def fingerprint(rows: dict[tuple[str, str], Any]) -> str:
    normalized = [
        {"kind": kind, "identity": identity, "definition": rows[(kind, identity)]}
        for kind, identity in sorted(rows)
    ]
    return digest(normalized)


def compare(git_rows: dict[tuple[str, str], Any], live_rows: dict[tuple[str, str], Any]) -> dict[str, Any]:
    git_keys = set(git_rows)
    live_keys = set(live_rows)
    missing_in_live = [
        {"kind": kind, "identity": identity, "git_definition_sha256": digest(git_rows[(kind, identity)])}
        for kind, identity in sorted(git_keys - live_keys)
    ]
    extra_in_live = [
        {"kind": kind, "identity": identity, "live_definition_sha256": digest(live_rows[(kind, identity)])}
        for kind, identity in sorted(live_keys - git_keys)
    ]
    changed = []
    for key in sorted(git_keys & live_keys):
        if canonical(git_rows[key]) == canonical(live_rows[key]):
            continue
        kind, identity = key
        changed.append(
            {
                "kind": kind,
                "identity": identity,
                "git_definition_sha256": digest(git_rows[key]),
                "live_definition_sha256": digest(live_rows[key]),
            }
        )
    result = "MATCH" if not (missing_in_live or extra_in_live or changed) else "DRIFT_DETECTED"
    return {
        "schema_version": SCHEMA_VERSION,
        "result": result,
        "git_fingerprint_sha256": fingerprint(git_rows),
        "live_fingerprint_sha256": fingerprint(live_rows),
        "git_object_count": len(git_rows),
        "live_object_count": len(live_rows),
        "difference_count": len(missing_in_live) + len(extra_in_live) + len(changed),
        "missing_in_live": missing_in_live,
        "extra_in_live": extra_in_live,
        "changed": changed,
        "security_boundary": "GOVERNED_DB_CHANGE_EXECUTION_NOT_INTERNAL_TRIGGER",
        "live_access_mode": "READ_ONLY",
    }


def _fixture(**values: Any) -> dict[tuple[str, str], Any]:
    return {(kind, identity): definition for (kind, identity), definition in values["rows"]}


def self_test() -> int:
    base = {
        ("RELATION", "public.account"): {"relkind": "r"},
        ("COLUMN", "public.account.id"): {"type": "uuid", "not_null": True},
        ("FUNCTION", "public.touch() "): {"body": "return new"},
    }
    same = dict(base)
    assert compare(base, same)["result"] == "MATCH"

    missing = dict(base)
    missing.pop(("COLUMN", "public.account.id"))
    got = compare(base, missing)
    assert got["result"] == "DRIFT_DETECTED" and len(got["missing_in_live"]) == 1

    extra = dict(base)
    extra[("COLUMN", "public.account.external_note")] = {"type": "text"}
    got = compare(base, extra)
    assert got["result"] == "DRIFT_DETECTED" and len(got["extra_in_live"]) == 1

    changed = dict(base)
    changed[("COLUMN", "public.account.id")] = {"type": "text", "not_null": True}
    got = compare(base, changed)
    assert got["result"] == "DRIFT_DETECTED" and len(got["changed"]) == 1

    function_changed = dict(base)
    function_changed[("FUNCTION", "public.touch() ")] = {"body": "return old"}
    got = compare(base, function_changed)
    assert got["result"] == "DRIFT_DETECTED" and got["changed"][0]["kind"] == "FUNCTION"

    print("PASS_DB_SCHEMA_DRIFT_AUDIT_SELFTEST=5/5")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--git-jsonl", type=Path)
    parser.add_argument("--live-jsonl", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    if args.git_jsonl is None or args.live_jsonl is None or args.output is None:
        raise SystemExit("FAIL_DB_SCHEMA_DRIFT_AUDIT_USAGE")
    try:
        git_rows = load_rows(args.git_jsonl)
        live_rows = load_rows(args.live_jsonl)
    except (OSError, UnicodeError, ValueError) as exc:
        raise SystemExit(f"FAIL_DB_SCHEMA_DRIFT_AUDIT_INPUT:{exc}") from exc
    report = compare(git_rows, live_rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("result", "git_fingerprint_sha256", "live_fingerprint_sha256", "difference_count")}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
