#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_lf_migration_lifecycle_reconcile.sh \
    --owner-prefix s30_ \
    [--min-version YYYYMMDDHHMMSS] \
    [--max-version YYYYMMDDHHMMSS] \
    [--materialize]

Requires the standard PostgreSQL environment variables used by psql:
PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE PGSSLMODE.

The runner is intentionally local-worktree only. It never commits, pushes,
opens a PR, merges, or replays DDL.
EOF
}

owner_prefix=""
min_version=""
max_version=""
materialize="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner-prefix)
      owner_prefix="${2:-}"
      shift 2
      ;;
    --min-version)
      min_version="${2:-}"
      shift 2
      ;;
    --max-version)
      max_version="${2:-}"
      shift 2
      ;;
    --materialize)
      materialize="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "FAIL_MIGRATION_LIFECYCLE_UNKNOWN_ARG=$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$owner_prefix" ]]; then
  echo "FAIL_MIGRATION_LIFECYCLE_OWNER_PREFIX_REQUIRED" >&2
  exit 2
fi
if [[ -n "$min_version" && ! "$min_version" =~ ^20[0-9]{12}$ ]]; then
  echo "FAIL_MIGRATION_LIFECYCLE_MIN_VERSION_INVALID=$min_version" >&2
  exit 2
fi
if [[ -n "$max_version" && ! "$max_version" =~ ^20[0-9]{12}$ ]]; then
  echo "FAIL_MIGRATION_LIFECYCLE_MAX_VERSION_INVALID=$max_version" >&2
  exit 2
fi
if [[ -n "$min_version" && -n "$max_version" && "$min_version" > "$max_version" ]]; then
  echo "FAIL_MIGRATION_LIFECYCLE_VERSION_WINDOW_INVALID" >&2
  exit 2
fi

for cmd in git psql python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "FAIL_MIGRATION_LIFECYCLE_COMMAND_MISSING=$cmd" >&2
    exit 2
  }
done

required_pg=(PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE PGSSLMODE)
for var in "${required_pg[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "FAIL_MIGRATION_LIFECYCLE_ENV_MISSING=$var" >&2
    exit 2
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
branch="$(git -C "$repo_root" branch --show-current)"
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "BLOCK_MIGRATION_LIFECYCLE_MAIN_WORKTREE branch=$branch" >&2
  exit 3
fi

if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]]; then
  echo "BLOCK_MIGRATION_LIFECYCLE_TRACKED_WORKTREE_DIRTY" >&2
  git -C "$repo_root" status --short >&2
  exit 3
fi

migrations_dir="$repo_root/supabase/migrations"
export_sql="$script_dir/lf_migration_lifecycle_export.sql"
reconciler="$script_dir/lf_migration_lifecycle_reconcile.py"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
ledger_json="$work_dir/ledger.json"
receipt_json="$work_dir/receipt.json"

psql -X -q -A -t -v ON_ERROR_STOP=1 \
  -v owner_prefix="$owner_prefix" \
  -v min_version="$min_version" \
  -v max_version="$max_version" \
  -f "$export_sql" > "$ledger_json"

python3 - <<'PY' "$ledger_json"
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
payload = json.loads(p.read_text(encoding="utf-8"))
if not isinstance(payload, list):
    raise SystemExit("FAIL_MIGRATION_LIFECYCLE_LEDGER_EXPORT_NOT_ARRAY")
print(f"PASS_MIGRATION_LIFECYCLE_LEDGER_EXPORT entries={len(payload)}")
PY

args=(
  --ledger-json "$ledger_json"
  --migrations-dir "$migrations_dir"
  --owner-prefix "$owner_prefix"
  --min-version "$min_version"
  --max-version "$max_version"
  --receipt "$receipt_json"
)
if [[ "$materialize" == "true" ]]; then
  args+=(--materialize-remote-only)
fi

python3 "$reconciler" "${args[@]}"

if [[ "$materialize" == "true" ]]; then
  python3 - <<'PY' "$receipt_json" "$repo_root"
import json, pathlib, subprocess, sys
receipt_path = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])
r = json.loads(receipt_path.read_text(encoding="utf-8"))
if r.get("state") not in {"PASS", "RECOVERED_TO_WORKTREE"}:
    raise SystemExit(f"FAIL_MIGRATION_LIFECYCLE_MATERIALIZE_STATE={r.get('state')}")
expected = {item["path"] for item in r.get("materialized", [])}
status = subprocess.check_output(
    ["git", "-C", str(repo_root), "status", "--porcelain"], text=True
).splitlines()
untracked = set()
for line in status:
    if line.startswith("?? "):
        rel = line[3:]
        untracked.add((repo_root / rel).as_posix())
    else:
        raise SystemExit(f"FAIL_MIGRATION_LIFECYCLE_UNEXPECTED_TRACKED_CHANGE={line}")
if untracked != expected:
    raise SystemExit(
        "FAIL_MIGRATION_LIFECYCLE_WORKTREE_SCOPE "
        f"expected={sorted(expected)} actual={sorted(untracked)}"
    )
print(f"PASS_MIGRATION_LIFECYCLE_WORKTREE_SCOPE files={len(expected)}")
PY
fi

echo "PASS_MIGRATION_LIFECYCLE_RUNNER state=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' "$receipt_json")"
echo "receipt=$receipt_json"
