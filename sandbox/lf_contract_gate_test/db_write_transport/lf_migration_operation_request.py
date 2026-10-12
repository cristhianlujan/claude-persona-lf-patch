#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

MODES = {"NORMAL", "RECOVER", "RECONCILE", "RESUME"}
PATH_RE = re.compile(r"^supabase/migrations/\d{14}_[A-Za-z0-9][A-Za-z0-9_]*\.sql$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")


def field(body: str, key: str) -> str | None:
    m = re.search(rf"(?mi)^\s*{re.escape(key)}\s*:\s*(\S+)\s*$", body)
    return m.group(1).strip() if m else None


def parse(body: str) -> dict[str, str]:
    mode = (field(body, "LF_MIGRATION_MODE") or "NORMAL").upper()
    if mode not in MODES:
        raise ValueError(f"LF_MIGRATION_MODE_INVALID:{mode}")
    out = {"operation_mode": mode}
    if mode == "RECOVER":
        path = field(body, "LF_RECOVER_PATH") or ""
        blob = (field(body, "LF_RECOVER_BLOB") or "").lower()
        issue = field(body, "LF_RECOVER_ISSUE") or ""
        if PATH_RE.fullmatch(path) is None:
            raise ValueError("LF_RECOVER_PATH_INVALID")
        if SHA1_RE.fullmatch(blob) is None:
            raise ValueError("LF_RECOVER_BLOB_INVALID")
        if not issue.isdigit():
            raise ValueError("LF_RECOVER_ISSUE_INVALID")
        out.update(recover_path=path, recover_blob=blob, recover_issue=issue)
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--body-file", required=True)
    p.add_argument("--github-output")
    args = p.parse_args()
    parsed = parse(Path(args.body_file).read_text(encoding="utf-8"))
    if args.github_output:
        with Path(args.github_output).open("a", encoding="utf-8") as h:
            for k, v in parsed.items():
                h.write(f"{k}={v}\n")
    print(json.dumps(parsed, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
