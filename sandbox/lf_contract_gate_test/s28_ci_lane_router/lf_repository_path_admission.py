#!/usr/bin/env python3
"""Repository path admission owned by existing Changeset Governance.

This module does not decide applicability and does not execute downstream controls.
It consumes the existing LF change-family registry as the single declarative source
for exact GitHub path admission. Unknown `.github/` paths fail closed.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

REGISTRY_PATH = Path(__file__).with_name("lf_change_family_registry_v1.json")
PATH_ADMISSION_VERSION = "LF_REPOSITORY_PATH_ADMISSION_V1"


class RepositoryPathAdmissionError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class RepositoryPathAdmission:
    github_exact: frozenset[str]
    github_retired_delete_only: frozenset[str]

    def evaluate(self, path: str, *, exists_after_change: bool = True) -> dict[str, str]:
        if not _safe_path(path):
            return {"verdict": "BLOCK", "code": "FAIL_REPOSITORY_PATH_INVALID"}
        if path in self.github_retired_delete_only:
            if exists_after_change:
                return {"verdict": "BLOCK", "code": "FAIL_RETIRED_GITHUB_PATH_REINTRODUCED"}
            return {"verdict": "ADMIT", "code": "PASS_RETIRED_GITHUB_DELETE_ONLY"}
        if path.startswith(".github/"):
            if path in self.github_exact:
                return {"verdict": "ADMIT", "code": "PASS_GITHUB_EXACT_PATH_ADMISSION"}
            return {"verdict": "BLOCK", "code": "FAIL_UNAUTHORIZED_GITHUB_PATH"}
        return {"verdict": "NOT_APPLICABLE", "code": "PATH_ADMISSION_NOT_APPLICABLE"}


def _safe_path(value: str) -> bool:
    if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value:
        return False
    if any(c in value for c in "*?[]"):
        return False
    return all(part not in {".", ".."} for part in PurePosixPath(value).parts)


def _exact_workflow_path(value: Any) -> bool:
    return (
        isinstance(value, str)
        and _safe_path(value)
        and value.startswith(".github/workflows/")
        and value.endswith(".yml")
        and "/" not in value.removeprefix(".github/workflows/")
    )


def compile_repository_path_admission(data: Mapping[str, Any]) -> RepositoryPathAdmission:
    if not isinstance(data, Mapping):
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_REGISTRY_SHAPE")
    raw = data.get("path_admission")
    if not isinstance(raw, Mapping) or set(raw) != {
        "version", "default_github", "github_exact", "github_retired_delete_only"
    }:
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_SHAPE")
    if raw.get("version") != PATH_ADMISSION_VERSION:
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_VERSION")
    if raw.get("default_github") != "DENY":
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_DEFAULT_NOT_DENY")

    exact = raw.get("github_exact")
    retired = raw.get("github_retired_delete_only")
    if not isinstance(exact, list) or not exact or any(not _exact_workflow_path(v) for v in exact):
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_EXACT_PATHS")
    if not isinstance(retired, list) or any(not _exact_workflow_path(v) for v in retired):
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_RETIRED_PATHS")
    if len(exact) != len(set(exact)) or len(retired) != len(set(retired)):
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_DUPLICATE")
    if set(exact) & set(retired):
        raise RepositoryPathAdmissionError("FAIL_REPOSITORY_PATH_ADMISSION_ACTIVE_RETIRED_OVERLAP")

    return RepositoryPathAdmission(frozenset(exact), frozenset(retired))


@lru_cache(maxsize=1)
def load_repository_path_admission() -> RepositoryPathAdmission:
    return compile_repository_path_admission(json.loads(REGISTRY_PATH.read_text(encoding="utf-8")))


def main() -> int:
    policy = load_repository_path_admission()
    print(
        "PASS_REPOSITORY_PATH_ADMISSION_LOADED "
        f"github_exact={len(policy.github_exact)} retired_delete_only={len(policy.github_retired_delete_only)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
