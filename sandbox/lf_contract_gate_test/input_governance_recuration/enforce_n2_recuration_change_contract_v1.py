#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

N2_SCOPE = {1, 2, 3, 5, 43, 51, 52, 53, 54, 55, 56, 57, 58}
AUTHORITY_MARKERS = (
    "lf_ops.pantallas",
    "lf_ops.pantallas_perfiles",
    "lf_ops.pantallas_permisos",
    "lf_ops.perfiles",
    "lf_ops.permisos",
    "programacion.input_readiness_runs",
    "programacion.input_family_assessments",
    "programacion.input_gap_proposals",
    "programacion.input_source_",
    "programacion.input_family_",
)
REQUIRED_RE = re.compile(
    r"(?mi)^\s*--\s*LF_INPUT_GOV_RECURATION\s*:\s*REQUIRED\s*$"
)
SCREENS_RE = re.compile(
    r"(?mi)^\s*--\s*LF_INPUT_GOV_PANTALLAS\s*:\s*(ALL_N2|[0-9,\s]+)\s*$"
)


class ContractError(RuntimeError):
    pass


def _git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise ContractError(
            f"FAIL_N2_RECURATION_GIT:{' '.join(args)}:{proc.stderr.strip()}"
        )
    return proc.stdout


def _changed_migrations(repo: Path, base: str, head: str) -> list[str]:
    out = _git(
        repo,
        "diff",
        "--name-only",
        "--diff-filter=AMCR",
        base,
        head,
        "--",
        "supabase/migrations/*.sql",
    )
    return [line.strip() for line in out.splitlines() if line.strip()]


def _read_at(repo: Path, head: str, path: str) -> str:
    return _git(repo, "show", f"{head}:{path}")


def impacted_markers(sql: str) -> list[str]:
    lowered = sql.lower()
    return sorted({m for m in AUTHORITY_MARKERS if m.lower() in lowered})


def parse_declared_screens(sql: str) -> set[int]:
    match = SCREENS_RE.search(sql)
    if not match:
        raise ContractError("FAIL_N2_RECURATION_PANTALLAS_DECLARATION_MISSING")
    raw = match.group(1).strip()
    if raw == "ALL_N2":
        return set(N2_SCOPE)
    values = {int(part.strip()) for part in raw.split(",") if part.strip()}
    if not values:
        raise ContractError("FAIL_N2_RECURATION_PANTALLAS_EMPTY")
    invalid = sorted(values - N2_SCOPE)
    if invalid:
        raise ContractError(
            "FAIL_N2_RECURATION_PANTALLAS_OUTSIDE_SCOPE:" + ",".join(map(str, invalid))
        )
    return values


def validate_sql(path: str, sql: str) -> tuple[bool, list[str], set[int]]:
    markers = impacted_markers(sql)
    if not markers:
        return False, [], set()
    if not REQUIRED_RE.search(sql):
        raise ContractError(
            f"FAIL_N2_RECURATION_REQUIRED_DECLARATION_MISSING:{path}:"
            + ",".join(markers)
        )
    screens = parse_declared_screens(sql)
    return True, markers, screens


def self_test() -> int:
    harmless = "select 1;"
    touched_ok = """-- LF_INPUT_GOV_RECURATION: REQUIRED
-- LF_INPUT_GOV_PANTALLAS: 1,2,57
insert into lf_ops.pantallas_perfiles values (1,1,'VIGENTE');
"""
    touched_all = """-- LF_INPUT_GOV_RECURATION: REQUIRED
-- LF_INPUT_GOV_PANTALLAS: ALL_N2
update lf_ops.perfiles set status='VIGENTE';
"""
    touched_missing = "update lf_ops.permisos set status='VIGENTE';"
    touched_bad_scope = """-- LF_INPUT_GOV_RECURATION: REQUIRED
-- LF_INPUT_GOV_PANTALLAS: 999
update programacion.input_readiness_runs set status='CURATING';
"""

    assert validate_sql("harmless.sql", harmless) == (False, [], set())
    required, markers, screens = validate_sql("ok.sql", touched_ok)
    assert required and "lf_ops.pantallas_perfiles" in markers
    assert screens == {1, 2, 57}
    assert validate_sql("all.sql", touched_all)[2] == N2_SCOPE

    try:
        validate_sql("missing.sql", touched_missing)
    except ContractError as exc:
        assert "REQUIRED_DECLARATION_MISSING" in str(exc)
    else:
        raise AssertionError("missing declaration should fail")

    try:
        validate_sql("bad_scope.sql", touched_bad_scope)
    except ContractError as exc:
        assert "PANTALLAS_OUTSIDE_SCOPE" in str(exc)
    else:
        raise AssertionError("out-of-scope declaration should fail")

    print("PASS_N2_RECURATION_CHANGE_CONTRACT_SELF_TEST=5/5")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--base")
    parser.add_argument("--head")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    if not args.base or not args.head:
        raise SystemExit("FAIL_N2_RECURATION_BASE_HEAD_REQUIRED")

    repo = Path(args.repo_root).resolve()
    changed = _changed_migrations(repo, args.base, args.head)
    checked = 0
    declarations = 0
    for path in changed:
        sql = _read_at(repo, args.head, path)
        required, markers, screens = validate_sql(path, sql)
        checked += 1
        if required:
            declarations += 1
            print(
                "PASS_N2_RECURATION_DECLARATION "
                f"path={path} markers={','.join(markers)} "
                f"screens={','.join(map(str, sorted(screens)))}"
            )

    print(
        "PASS_N2_RECURATION_CHANGE_CONTRACT "
        f"migrations_checked={checked} declarations_required={declarations}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ContractError as exc:
        raise SystemExit(str(exc))
