#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any

SHA40 = re.compile(r"^[0-9a-f]{40}$")
ALLOWED_MODES = {"DIRECT_CHILD", "ENUMERATE_CHILDREN"}


class ResolutionError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ResolutionError("JSON_OBJECT_REQUIRED")
    return value


def normalize_prefix(raw: Any) -> str:
    if not isinstance(raw, str) or not raw.endswith("/"):
        raise ResolutionError("PREFIX_INVALID")
    normalized = normalize_changed_path(raw[:-1])
    return normalized + "/"


def normalize_changed_path(raw: Any) -> str:
    if not isinstance(raw, str) or not raw or raw.startswith("/") or "\\" in raw:
        raise ResolutionError("PATH_INVALID")
    parts = raw.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ResolutionError("PATH_INVALID")
    path = PurePosixPath(raw)
    normalized = path.as_posix()
    if normalized != raw:
        raise ResolutionError("PATH_NOT_CANONICAL")
    return normalized


def validate_sha(value: Any, field: str) -> str:
    if not isinstance(value, str) or not SHA40.fullmatch(value):
        raise ResolutionError(f"{field.upper()}_INVALID")
    return value


def contract_roots(validation_contract: dict[str, Any]) -> dict[str, set[str]]:
    pack_types = validation_contract.get("pack_types")
    if not isinstance(pack_types, dict) or not pack_types:
        raise ResolutionError("VALIDATION_PACK_TYPES_MISSING")
    roots: dict[str, set[str]] = {}
    for pack_type, cfg in pack_types.items():
        if not isinstance(pack_type, str) or not isinstance(cfg, dict):
            raise ResolutionError("VALIDATION_PACK_TYPE_INVALID")
        raw_roots = cfg.get("roots")
        if not isinstance(raw_roots, list) or not raw_roots:
            raise ResolutionError("VALIDATION_ROOTS_MISSING")
        roots[pack_type] = {normalize_prefix(root) for root in raw_roots}
    return roots


def validated_rules(
    discovery_contract: dict[str, Any],
    validation_contract: dict[str, Any],
) -> list[dict[str, str]]:
    if discovery_contract.get("durable_name") != "PACK_DISCOVERY_RESOLVE_AFFECTED_PACKS":
        raise ResolutionError("DISCOVERY_IDENTITY_INVALID")
    if discovery_contract.get("depends_on") != "PACK_VALIDATION_DEFINE_CONTRACT":
        raise ResolutionError("DISCOVERY_DEPENDENCY_INVALID")
    if validation_contract.get("durable_name") != "PACK_VALIDATION_DEFINE_CONTRACT":
        raise ResolutionError("VALIDATION_CONTRACT_IDENTITY_INVALID")

    allowed_roots = contract_roots(validation_contract)
    raw_rules = discovery_contract.get("rules")
    if not isinstance(raw_rules, list) or not raw_rules:
        raise ResolutionError("DISCOVERY_RULES_MISSING")

    seen_ids: set[str] = set()
    rules: list[dict[str, str]] = []
    for raw in raw_rules:
        if not isinstance(raw, dict):
            raise ResolutionError("DISCOVERY_RULE_INVALID")
        rule_id = raw.get("rule_id")
        pack_type = raw.get("pack_type")
        mode = raw.get("mode")
        if not isinstance(rule_id, str) or not rule_id or rule_id in seen_ids:
            raise ResolutionError("DISCOVERY_RULE_ID_INVALID")
        if not isinstance(pack_type, str) or pack_type not in allowed_roots:
            raise ResolutionError("DISCOVERY_PACK_TYPE_INVALID")
        if mode not in ALLOWED_MODES:
            raise ResolutionError("DISCOVERY_MODE_INVALID")
        trigger_prefix = normalize_prefix(raw.get("trigger_prefix"))
        target_root = normalize_prefix(raw.get("target_root"))
        if trigger_prefix not in allowed_roots[pack_type]:
            raise ResolutionError("DISCOVERY_TRIGGER_NOT_AUTHORIZED_BY_VALIDATION_CONTRACT")
        if target_root not in allowed_roots[pack_type]:
            raise ResolutionError("DISCOVERY_TARGET_NOT_AUTHORIZED_BY_VALIDATION_CONTRACT")
        if mode == "DIRECT_CHILD" and trigger_prefix != target_root:
            raise ResolutionError("DIRECT_CHILD_TRIGGER_TARGET_MISMATCH")
        seen_ids.add(rule_id)
        rules.append(
            {
                "rule_id": rule_id,
                "pack_type": pack_type,
                "mode": mode,
                "trigger_prefix": trigger_prefix,
                "target_root": target_root,
            }
        )
    return rules


def is_triggered(path: str, prefix: str) -> bool:
    return path.startswith(prefix)


def direct_child_pack(path: str, target_root: str) -> str | None:
    if not path.startswith(target_root):
        return None
    remainder = path[len(target_root):]
    parts = remainder.split("/")
    if len(parts) < 2 or not parts[0]:
        return None
    return target_root + parts[0]


def enumerate_children(repo_root: Path, target_root: str) -> list[str]:
    root = repo_root / target_root.rstrip("/")
    if not root.is_dir() or root.is_symlink():
        raise ResolutionError("ENUMERATION_ROOT_MISSING_OR_UNSAFE")
    result: list[str] = []
    for child in sorted(root.iterdir(), key=lambda p: p.name):
        if child.name.startswith((".", "_")):
            continue
        if child.is_symlink() or not child.is_dir():
            continue
        result.append(target_root + child.name)
    return result


def resolve_affected_packs(
    *,
    repo_root: Path,
    validation_contract: dict[str, Any],
    discovery_contract: dict[str, Any],
    base_sha: str,
    head_sha: str,
    changed_paths: list[str],
) -> dict[str, Any]:
    try:
        base_sha = validate_sha(base_sha, "base_sha")
        head_sha = validate_sha(head_sha, "head_sha")
        rules = validated_rules(discovery_contract, validation_contract)
        normalized_paths = sorted({normalize_changed_path(path) for path in changed_paths})
        repo_root = repo_root.resolve()

        affected: dict[tuple[str, str], dict[str, Any]] = {}
        for path in normalized_paths:
            for rule in rules:
                if not is_triggered(path, rule["trigger_prefix"]):
                    continue
                if rule["mode"] == "DIRECT_CHILD":
                    roots = [direct_child_pack(path, rule["target_root"])]
                    roots = [root for root in roots if root is not None]
                else:
                    roots = enumerate_children(repo_root, rule["target_root"])

                for pack_root in roots:
                    key = (rule["pack_type"], pack_root)
                    item = affected.setdefault(
                        key,
                        {
                            "pack_type": rule["pack_type"],
                            "pack_root": pack_root,
                            "trigger_rules": [],
                            "trigger_paths": [],
                            "exists_at_head": False,
                        },
                    )
                    if rule["rule_id"] not in item["trigger_rules"]:
                        item["trigger_rules"].append(rule["rule_id"])
                    if path not in item["trigger_paths"]:
                        item["trigger_paths"].append(path)

        rows = []
        for key in sorted(affected):
            item = affected[key]
            candidate = repo_root / item["pack_root"]
            item["exists_at_head"] = candidate.is_dir() and not candidate.is_symlink()
            item["trigger_rules"].sort()
            item["trigger_paths"].sort()
            rows.append(item)

        return {
            "status": "PASS" if rows else "SKIP",
            "base_sha": base_sha,
            "head_sha": head_sha,
            "changed_paths": normalized_paths,
            "affected_packs": rows,
            "blocking_codes": [],
            "validators_executed": False,
            "runtime_authorized": False,
            "git_write_authorized": False,
            "db_write_authorized": False,
            "deployment_authorized": False,
            "production_authorized": False,
            "handoff": "PACK_VALIDATION_EXECUTE_PACK_CHECKS",
        }
    except (ResolutionError, json.JSONDecodeError, OSError) as exc:
        return {
            "status": "FAIL",
            "base_sha": base_sha,
            "head_sha": head_sha,
            "changed_paths": changed_paths,
            "affected_packs": [],
            "blocking_codes": [str(exc)],
            "validators_executed": False,
            "runtime_authorized": False,
            "git_write_authorized": False,
            "db_write_authorized": False,
            "deployment_authorized": False,
            "production_authorized": False,
            "handoff": None,
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--validation-contract", type=Path, required=True)
    parser.add_argument("--discovery-contract", type=Path, required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--changed-path", action="append", default=[])
    args = parser.parse_args()

    result = resolve_affected_packs(
        repo_root=args.repo_root,
        validation_contract=load_json(args.validation_contract),
        discovery_contract=load_json(args.discovery_contract),
        base_sha=args.base_sha,
        head_sha=args.head_sha,
        changed_paths=args.changed_path,
    )
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if result["status"] in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
