#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from lf_repository_path_admission import (
    RepositoryPathAdmissionError,
    compile_repository_path_admission,
    load_repository_path_admission,
)

REGISTRY_PATH = Path(__file__).with_name("lf_change_family_registry_v1.json")


def expect_error(data: dict, code: str) -> None:
    try:
        compile_repository_path_admission(data)
    except RepositoryPathAdmissionError as exc:
        assert exc.code == code, (exc.code, code)
        return
    raise AssertionError(f"expected {code}")


def main() -> int:
    checks = 0
    policy = load_repository_path_admission()

    expected_exact = {
        ".github/workflows/pase-merge-gate.yml",
        ".github/workflows/pase.yml",
        ".github/workflows/visual-evidence-gate.yml",
        ".github/workflows/lf-pack-validation-core.yml",
        ".github/workflows/lf-migration-source-parity-core.yml",
        ".github/workflows/lf-migration-merge-train.yml",
        ".github/workflows/lf-input-governance-recurate.yml",
    }
    assert expected_exact.issubset(policy.github_exact)
    checks += 1

    for path in sorted(policy.github_exact):
        result = policy.evaluate(path)
        assert result == {"verdict": "ADMIT", "code": "PASS_GITHUB_EXACT_PATH_ADMISSION"}, (path, result)
        checks += 1

    for path in sorted(expected_exact):
        stem = path[:-4]
        lookalikes = (
            path + ".bak",
            stem + ".yaml",
            stem + "-copy.yml",
            stem + "/child.yml",
        )
        for lookalike in lookalikes:
            result = policy.evaluate(lookalike)
            assert result == {"verdict": "BLOCK", "code": "FAIL_UNAUTHORIZED_GITHUB_PATH"}, (lookalike, result)
            checks += 1

    for path in (
        ".github/workflows/unregistered.yml",
        ".github/CODEOWNERS",
        ".github/pull_request_template.md",
    ):
        result = policy.evaluate(path)
        assert result == {"verdict": "BLOCK", "code": "FAIL_UNAUTHORIZED_GITHUB_PATH"}, (path, result)
        checks += 1

    retired = ".github/workflows/lf-bootstrap-reproducibility.yml"
    assert policy.evaluate(retired, exists_after_change=True)["code"] == "FAIL_RETIRED_GITHUB_PATH_REINTRODUCED"
    checks += 1
    assert policy.evaluate(retired, exists_after_change=False) == {
        "verdict": "ADMIT", "code": "PASS_RETIRED_GITHUB_DELETE_ONLY"
    }
    checks += 1

    assert policy.evaluate("skills/profile_creator/SKILL.md") == {
        "verdict": "NOT_APPLICABLE", "code": "PATH_ADMISSION_NOT_APPLICABLE"
    }
    checks += 1
    assert policy.evaluate("../.github/workflows/lf-contract-check.yml")["code"] == "FAIL_REPOSITORY_PATH_INVALID"
    checks += 1

    base = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    bad = copy.deepcopy(base)
    bad["path_admission"]["default_github"] = "ALLOW"
    expect_error(bad, "FAIL_REPOSITORY_PATH_ADMISSION_DEFAULT_NOT_DENY")
    checks += 1

    bad = copy.deepcopy(base)
    bad["path_admission"]["github_exact"].append(".github/workflows/subdir/evil.yml")
    expect_error(bad, "FAIL_REPOSITORY_PATH_ADMISSION_EXACT_PATHS")
    checks += 1

    bad = copy.deepcopy(base)
    duplicate = bad["path_admission"]["github_exact"][0]
    bad["path_admission"]["github_exact"].append(duplicate)
    expect_error(bad, "FAIL_REPOSITORY_PATH_ADMISSION_DUPLICATE")
    checks += 1

    bad = copy.deepcopy(base)
    overlap = bad["path_admission"]["github_exact"][0]
    bad["path_admission"]["github_retired_delete_only"].append(overlap)
    expect_error(bad, "FAIL_REPOSITORY_PATH_ADMISSION_ACTIVE_RETIRED_OVERLAP")
    checks += 1

    print(f"PASS_REPOSITORY_PATH_ADMISSION_V1={checks}/{checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
