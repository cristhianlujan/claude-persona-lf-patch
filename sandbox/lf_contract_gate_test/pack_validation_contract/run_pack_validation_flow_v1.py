#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
RESOLVER_PATH = HERE / "resolve_affected_packs_v1.py"
EXECUTOR_PATH = HERE / "execute_pack_checks_v1.py"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resolver = _load_module("pack_validation_resolver_v1", RESOLVER_PATH)
executor = _load_module("pack_validation_executor_v1", EXECUTOR_PATH)


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON_OBJECT_REQUIRED:{path}")
    return value


def _changed_paths(raw: str) -> list[str]:
    value = json.loads(raw)
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ValueError("CHANGED_PATHS_JSON_INVALID")
    return value


def _write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _summary(discovery: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    rows = result.get("affected_packs") if isinstance(result.get("affected_packs"), list) else []
    return {
        "schema_version": "lf-pack-validation-flow-summary/v1",
        "status": result.get("status", "FAIL"),
        "base_sha": result.get("base_sha"),
        "head_sha": result.get("head_sha"),
        "discovery_status": discovery.get("status"),
        "affected_pack_count": len(discovery.get("affected_packs") or []),
        "executed_pack_count": len(rows),
        "pass_count": sum(1 for row in rows if isinstance(row, dict) and row.get("status") == "PASS"),
        "fail_count": sum(1 for row in rows if isinstance(row, dict) and row.get("status") == "FAIL"),
        "blocking_codes": list(result.get("blocking_codes") or []),
        "runtime_authorized": False,
        "git_write_authorized": False,
        "db_write_authorized": False,
        "deployment_authorized": False,
        "production_authorized": False,
        "next_handoff": "CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS",
    }


def run_flow(
    *,
    repo_root: Path,
    validation_contract_path: Path,
    discovery_contract_path: Path,
    base_sha: str,
    head_sha: str,
    changed_paths: list[str],
    output_dir: Path,
    timeout_seconds: int = 120,
    verify_git: bool = True,
) -> dict[str, Any]:
    validation_contract = _load_json(validation_contract_path)
    discovery_contract = _load_json(discovery_contract_path)

    discovery = resolver.resolve_affected_packs(
        repo_root=repo_root,
        validation_contract=validation_contract,
        discovery_contract=discovery_contract,
        base_sha=base_sha,
        head_sha=head_sha,
        changed_paths=changed_paths,
    )
    _write(output_dir / "discovery.json", discovery)

    if discovery.get("status") == "FAIL":
        result = {
            "status": "FAIL",
            "base_sha": base_sha,
            "head_sha": head_sha,
            "affected_packs": [],
            "checks_executed": [],
            "blocking_codes": [f"DISCOVERY:{code}" for code in discovery.get("blocking_codes") or ["UNKNOWN"]],
            "evidence": {"exact_head_verified": False},
            "runtime_authorized": False,
            "git_write_authorized": False,
            "db_write_authorized": False,
            "deployment_authorized": False,
            "production_authorized": False,
            "semantic_quality_review_authorized": False,
            "handoff": None,
        }
    else:
        result = executor.execute_pack_checks(
            repo_root=repo_root,
            validation_contract=validation_contract,
            discovery_contract=discovery_contract,
            discovery_result=discovery,
            base_sha=base_sha,
            head_sha=head_sha,
            timeout_seconds=timeout_seconds,
            verify_git=verify_git,
        )

    _write(output_dir / "result.json", result)
    summary = _summary(discovery, result)
    _write(output_dir / "summary.json", summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--validation-contract", type=Path, required=True)
    parser.add_argument("--discovery-contract", type=Path, required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--changed-paths-json")
    parser.add_argument("--changed-paths-env", default="LF_CHANGED_PATHS_JSON")
    parser.add_argument("--output-dir", type=Path, default=Path(".lf_pack_validation"))
    parser.add_argument("--timeout-seconds", type=int, default=120)
    args = parser.parse_args()

    raw = args.changed_paths_json
    if raw is None:
        raw = os.environ.get(args.changed_paths_env, "")
    try:
        paths = _changed_paths(raw)
        summary = run_flow(
            repo_root=args.repo_root,
            validation_contract_path=args.validation_contract,
            discovery_contract_path=args.discovery_contract,
            base_sha=args.base_sha,
            head_sha=args.head_sha,
            changed_paths=paths,
            output_dir=args.output_dir,
            timeout_seconds=args.timeout_seconds,
            verify_git=True,
        )
    except (ValueError, RuntimeError, json.JSONDecodeError, OSError) as exc:
        summary = {
            "schema_version": "lf-pack-validation-flow-summary/v1",
            "status": "FAIL",
            "base_sha": args.base_sha,
            "head_sha": args.head_sha,
            "affected_pack_count": 0,
            "executed_pack_count": 0,
            "pass_count": 0,
            "fail_count": 0,
            "blocking_codes": [str(exc)],
            "runtime_authorized": False,
            "git_write_authorized": False,
            "db_write_authorized": False,
            "deployment_authorized": False,
            "production_authorized": False,
            "next_handoff": None,
        }
        _write(args.output_dir / "result.json", summary)
        _write(args.output_dir / "summary.json", summary)

    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))
    return 0 if summary.get("status") in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
