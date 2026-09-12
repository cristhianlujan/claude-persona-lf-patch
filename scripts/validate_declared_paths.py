#!/usr/bin/env python3
"""Fail-closed validation for governance paths declared in LF YAML assets."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path, PurePosixPath
from typing import Any

import yaml


MATRIX_PATH = Path("gobernanza/repositorios/matriz_repos_lf.yaml")
CONTRACT_PATH = Path("gobernanza/contratos/contrato_perfil_lf.yaml")


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected YAML mapping")
    return data


def entry_path(entry: Any, label: str) -> str:
    if isinstance(entry, str):
        value = entry
    elif isinstance(entry, dict) and isinstance(entry.get("path"), str):
        value = entry["path"]
    else:
        raise ValueError(f"{label}: expected path string or mapping with path")
    value = value.strip()
    if not value:
        raise ValueError(f"{label}: empty path")
    return value


def normalize_declared_path(value: str) -> str:
    raw = value.strip().replace("\\", "/")
    relative = raw.lstrip("/").rstrip("/")
    if not relative:
        return ""
    parts = PurePosixPath(relative).parts
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"unsafe declared path: {value}")
    return "/".join(parts)


def covered_by(path: str, allowed: list[str]) -> bool:
    return any(path == candidate or path.startswith(candidate + "/") for candidate in allowed)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    errors: list[str] = []
    verified = 0

    try:
        matrix = load_yaml(root / MATRIX_PATH)
        contract = load_yaml(root / CONTRACT_PATH)

        allowed_contract = contract.get("allowed")
        if not isinstance(allowed_contract, dict):
            raise ValueError(f"{CONTRACT_PATH}: allowed must be a mapping")
        repository = allowed_contract.get("repository")
        if not isinstance(repository, str) or not repository.strip():
            raise ValueError(f"{CONTRACT_PATH}: allowed.repository missing")

        repositories = matrix.get("repositories")
        if not isinstance(repositories, list):
            raise ValueError(f"{MATRIX_PATH}: repositories must be a list")
        repo_entry = next(
            (
                item
                for item in repositories
                if isinstance(item, dict) and item.get("repo") == repository
            ),
            None,
        )
        if repo_entry is None:
            raise ValueError(f"{MATRIX_PATH}: repository not declared: {repository}")

        raw_allowed = repo_entry.get("allowed_paths", [])
        if not isinstance(raw_allowed, list):
            raise ValueError(f"{MATRIX_PATH}: allowed_paths must be a list")
        allowed = [normalize_declared_path(entry_path(item, "allowed_paths")) for item in raw_allowed]

        for declared in allowed:
            candidate = root / declared
            if not candidate.is_dir():
                errors.append(f"FAIL_ALLOWED_PATH_NOT_DIRECTORY: /{declared}/")
            else:
                verified += 1

        raw_prefix = allowed_contract.get("path_prefix")
        if not isinstance(raw_prefix, str):
            raise ValueError(f"{CONTRACT_PATH}: allowed.path_prefix missing")
        prefix = normalize_declared_path(raw_prefix)
        prefix_candidate = root / prefix
        if not prefix_candidate.is_dir():
            errors.append(f"FAIL_PATH_PREFIX_NOT_DIRECTORY: /{prefix}/")
        else:
            verified += 1
        if not covered_by(prefix, allowed):
            errors.append(f"FAIL_PATH_PREFIX_NOT_COVERED: /{prefix}/")

        raw_legacy = repo_entry.get("legacy_exceptions", [])
        if not isinstance(raw_legacy, list):
            raise ValueError(f"{MATRIX_PATH}: legacy_exceptions must be a list")
        legacy = [normalize_declared_path(entry_path(item, "legacy_exceptions")) for item in raw_legacy]
        for declared in legacy:
            candidate = root / declared
            if not candidate.is_dir():
                errors.append(f"FAIL_LEGACY_EXCEPTION_NOT_DIRECTORY: /{declared}/")
            else:
                verified += 1

        raw_pending = repo_entry.get("pending_paths", [])
        if not isinstance(raw_pending, list):
            raise ValueError(f"{MATRIX_PATH}: pending_paths must be a list")
        pending = [normalize_declared_path(entry_path(item, "pending_paths")) for item in raw_pending]
        overlap = sorted(set(allowed).intersection(pending))
        for declared in overlap:
            errors.append(f"FAIL_PATH_BOTH_ALLOWED_AND_PENDING: /{declared}/")

    except (OSError, ValueError, yaml.YAMLError) as exc:
        errors.append(f"FAIL_DECLARED_PATH_VALIDATOR_INPUT: {exc}")

    if errors:
        for error in errors:
            print(error)
        print(f"FAIL declared governance paths: {len(errors)} finding(s)")
        return 1

    print(f"PASS declared governance paths: {verified} routes verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
