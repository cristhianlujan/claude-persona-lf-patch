#!/usr/bin/env python3
"""M10.4 legacy-only source freeze. Executed from trusted main by independent admission.

Read-only GitHub API; no database changes, grants, production activation or
historical-retirement inference. The snapshot is sourced from the CP1 ledger.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import quote
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "legacy_freeze_manifest_v1.json"
PROTECTED = frozenset({
    "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_manifest_v1.json",
    "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_guard.py",
})
SOURCE_EXTENSIONS = (".sql", ".py", ".ts", ".js", ".mjs", ".cjs")
SOURCE_EXCLUDED_PREFIXES = ("docs/", "sandbox/", "tests/", ".github/")

# DDL destinations, not incidental references/calls. Unqualified frozen names
# fail closed because the connection search_path can resolve to their schema.
DDL_TARGET = re.compile(
    r"""(?ix)
    \b(?:
      create\s+(?:or\s+replace\s+)?(?:function|procedure)
     |alter\s+(?:function|procedure)
     |drop\s+(?:function|procedure)(?:\s+if\s+exists)?
     |comment\s+on\s+(?:function|procedure)
     |(?:grant|revoke)\b[^\n;]{0,200}?\bon\s+(?:function|procedure)
    )\s+
    ((?:"?[a-z_][a-z_0-9]*"?\s*\.\s*)?"?[a-z_][a-z_0-9]*"?)
    \s*\(
    """
)
IDENTITY = re.compile(r"^([a-z_][a-z_0-9]*)\.([a-z_][a-z_0-9]*)\((.*)\)$", re.I)


def load_manifest() -> tuple[dict, set[tuple[str, str]]]:
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if m.get("schema_version") != "IG_M104_LEGACY_FREEZE_MANIFEST_V1":
        raise ValueError("FAIL_M104_MANIFEST_SCHEMA")
    members = m.get("legacy_functions")
    if not isinstance(members, list) or not members:
        raise ValueError("FAIL_M104_EMPTY_MANIFEST")
    identities = [item.get("identity", "") for item in members]
    if len(identities) != len(set(identities)):
        raise ValueError("FAIL_M104_DUPLICATE_IDENTITIES")
    targets = set()
    for item in members:
        identity = item["identity"]
        match = IDENTITY.fullmatch(identity)
        if match is None or not re.fullmatch(r"[0-9a-f]{32}", item.get("prosrc_md5", "")):
            raise ValueError("FAIL_M104_INVALID_FUNCTION_FINGERPRINT:" + identity)
        if item.get("historical_class") not in {"LEGACY_REFERENCED", "LEGACY_UNREFERENCED"}:
            raise ValueError("FAIL_M104_NON_LEGACY_MEMBER:" + identity)
        targets.add((match.group(1).lower(), match.group(2).lower()))
    digest = hashlib.md5("|".join(
        f"{item['identity']}:{item['prosrc_md5']}"
        for item in members
    ).encode()).hexdigest()
    if digest != m.get("source_aggregate_md5"):
        raise ValueError("FAIL_M104_MANIFEST_DRIFT:" + digest)
    if m.get("classification_event_id") != 20193:
        raise ValueError("FAIL_M104_CLASSIFICATION_SOURCE")
    excluded = m.get("active_vnext_edge_excluded", [])
    if not isinstance(excluded, list) or len(excluded) != len(set(excluded)):
        raise ValueError("FAIL_M104_EXCLUSION_SET")
    if any(str(code).startswith("EDGE_") for code in identities):
        raise ValueError("FAIL_M104_EDGE_SCOPE")
    return m, targets


def strip_comments(source: str) -> str:
    return re.sub(r"(?m)--[^\n]*", "", re.sub(r"/\*.*?\*/", "", source, flags=re.S))


def touched_targets(source: str, targets: set[tuple[str, str]]) -> list[str]:
    hits = set()
    for match in DDL_TARGET.finditer(strip_comments(source)):
        token = re.sub(r'[\s"]', "", match.group(1)).lower()
        parts = token.split(".")
        if len(parts) == 2:
            if (parts[0], parts[1]) in targets:
                hits.add(token)
        elif len(parts) == 1:
            if any(fn == parts[0] for _, fn in targets):
                hits.add(token + "[UNQUALIFIED]")
    return sorted(hits)


def rest(repo: str, endpoint: str) -> object:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise ValueError("FAIL_M104_GITHUB_TOKEN_UNAVAILABLE")
    req = Request(
        f"https://api.github.com/repos/{repo}/{endpoint}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urlopen(req, timeout=25) as reply:
        return json.load(reply)


def file_text(repo: str, path: str, ref: str) -> str:
    result = rest(repo, f"contents/{quote(path, safe='/')}?ref={quote(ref, safe='')}")
    if not isinstance(result, dict) or result.get("encoding") != "base64":
        raise ValueError("FAIL_M104_UNREADABLE_SOURCE:" + path)
    return base64.b64decode(result["content"]).decode("utf-8")


def source_candidate(path: str) -> bool:
    return path.endswith(SOURCE_EXTENSIONS) and not path.startswith(SOURCE_EXCLUDED_PREFIXES)


def check_pr(repo: str, number: int) -> None:
    manifest, targets = load_manifest()
    pr = rest(repo, f"pulls/{number}")
    if pr["head"]["repo"]["full_name"] != repo:
        raise ValueError("FAIL_M104_FOREIGN_HEAD")
    head = pr["head"]["sha"]
    base = pr["base"]["sha"]
    changed = []
    for page in range(1, 41):
        batch = rest(repo, f"pulls/{number}/files?per_page=100&page={page}")
        if not isinstance(batch, list):
            raise ValueError("FAIL_M104_FILES_RESPONSE")
        changed.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise ValueError("FAIL_M104_TOO_MANY_FILES")

    for f in changed:
        path = f["filename"]
        old = f.get("previous_filename", path)
        if path in PROTECTED or old in PROTECTED:
            raise ValueError("FAIL_M104_FROZEN_GUARD_ASSET_CHANGED:" + path)
        if not source_candidate(path) and not source_candidate(old):
            continue
        versions = []
        if f["status"] != "removed" and source_candidate(path):
            versions.append((path, head))
        if f["status"] in ("removed", "modified", "renamed") and source_candidate(old):
            versions.append((old, base))
        for source_path, ref in versions:
            hits = touched_targets(file_text(repo, source_path, ref), targets)
            if hits:
                raise ValueError(
                    "FAIL_M104_FROZEN_LEGACY_MUTATION:"
                    + source_path + ":" + ",".join(hits)
                )
    print(
        "PASS_M104_LEGACY_FREEZE"
        f" pr={number} head={head} sources={len(changed)}"
        f" frozen_identities={len(manifest['legacy_functions'])}"
        " legacy_edge=0"
    )


def self_test() -> None:
    manifest, targets = load_manifest()
    schema, name = sorted(targets)[0]
    assert touched_targets(f"select {schema}.{name}('x');", targets) == []
    assert touched_targets("create or replace function programacion.other_function(x int) returns int language sql as $$select 1$$;", targets) == []
    for stmt in (
        f"CREATE OR REPLACE FUNCTION {schema}.{name}(x integer) RETURNS int LANGUAGE SQL AS $$ SELECT 1 $$;",
        f"DROP FUNCTION IF EXISTS {schema}.{name}(integer);",
        f"ALTER FUNCTION {schema}.{name}(integer) RENAME TO something;",
        f"GRANT EXECUTE ON FUNCTION {schema}.{name}(integer) TO PUBLIC;",
        f"CREATE FUNCTION {name}(integer) RETURNS integer LANGUAGE sql AS $$ SELECT 1 $$;",
    ):
        if not touched_targets(stmt, targets):
            raise AssertionError("FAIL_M104_MUTANT_ACCEPTED:" + stmt[:70])
    # Mentioning a frozen name in a comment cannot trigger a false failure.
    assert touched_targets(f"-- DROP FUNCTION {schema}.{name}(integer)\nselect 1;", targets) == []
    print("PASS_M104_GUARD_SELF_TEST 8/8; frozen=" + str(len(manifest["legacy_functions"])))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("self-test", "check-pr"))
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    p.add_argument("--pr", type=int)
    args = p.parse_args()
    try:
        if args.mode == "self-test":
            self_test()
        else:
            if not args.repo or not args.pr:
                raise ValueError("FAIL_M104_PR_CONTEXT_REQUIRED")
            check_pr(args.repo, args.pr)
    except (ValueError, AssertionError, KeyError, UnicodeDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
