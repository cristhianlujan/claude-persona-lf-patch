#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
EMITTER_PATH = HERE / "emit_ci_execution_plan_v2.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot_load:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def _commit(repo: Path, message: str, *paths: str) -> str:
    _git(repo, "add", *paths)
    _git(repo, "commit", "-qm", message)
    return _git(repo, "rev-parse", "HEAD")


def _expect_system_exit(fn, prefix: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        if not str(exc).startswith(prefix):
            raise AssertionError(f"unexpected fail-closed code: {exc!s}") from exc
    else:
        raise AssertionError(f"expected fail-closed SystemExit:{prefix}")


def main() -> int:
    emitter = _load(EMITTER_PATH, "emit_ci_execution_plan_v2_manifest_transport_test")
    manifest_path = "sandbox/lf_contract_gate_test/changesets/SOL-X.json"
    second_manifest = "sandbox/lf_contract_gate_test/changesets/SOL-Y.json"
    custom_path = "custom/a.py"
    checks = 0

    with tempfile.TemporaryDirectory(prefix="lf-candidate-manifest-test-") as td:
        repo = Path(td)
        _git(repo, "init", "-q")
        _git(repo, "config", "user.email", "ci@example.invalid")
        _git(repo, "config", "user.name", "CI")
        (repo / "README.md").write_text("base\n", encoding="utf-8")
        base = _commit(repo, "base", "README.md")

        manifest = repo / manifest_path
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(
            json.dumps(
                {
                    "solution_ref": "SOL-X",
                    "paths": {custom_path: "CUSTOM"},
                },
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )
        custom = repo / custom_path
        custom.parent.mkdir(parents=True, exist_ok=True)
        custom.write_text("raise RuntimeError('CANDIDATE_CODE_MUST_NOT_EXECUTE')\n", encoding="utf-8")
        positive_head = _commit(repo, "candidate-positive", manifest_path, custom_path)

        _git(repo, "checkout", "-q", "--detach", base)
        if (repo / manifest_path).exists():
            raise AssertionError("candidate manifest leaked into trusted base checkout")

        changed = [custom_path, manifest_path]
        manifest_data = emitter._candidate_manifest_data(repo, changed, positive_head)
        if not isinstance(manifest_data, dict) or manifest_data.get("solution_ref") != "SOL-X":
            raise AssertionError(f"exact-head manifest not recovered: {manifest_data!r}")
        lane = emitter.ROUTER.classify(changed, manifest_data=manifest_data)
        if lane.mode == "CLASSIFICATION_REQUIRED":
            raise AssertionError(f"candidate manifest was not consumed: {lane.reasons!r}")
        solution_ref = emitter.HANDOFF._solution_ref(
            repo,
            manifest_path,
            manifest_data=manifest_data,
        )
        if solution_ref != "SOL-X":
            raise AssertionError(f"handoff lost candidate solution_ref: {solution_ref!r}")
        checks += 1

        # Exact-head absence must fail closed; never fall back to trusted-base filesystem.
        _expect_system_exit(
            lambda: emitter._candidate_manifest_data(repo, changed, base),
            "BLOCK_CI_CHANGESET_MANIFEST_EXACT_HEAD_READ:",
        )
        checks += 1

        # Malformed candidate JSON must fail closed before routing.
        _git(repo, "checkout", "-q", positive_head)
        manifest.write_text("{not-json\n", encoding="utf-8")
        malformed_head = _commit(repo, "candidate-malformed", manifest_path)
        _git(repo, "checkout", "-q", "--detach", base)
        _expect_system_exit(
            lambda: emitter._candidate_manifest_data(repo, changed, malformed_head),
            "BLOCK_CI_CHANGESET_MANIFEST_JSON:",
        )
        checks += 1

        # Multiple solution manifests remain rejected by trusted Changeset Governance.
        _git(repo, "checkout", "-q", positive_head)
        second = repo / second_manifest
        second.write_text(
            json.dumps({"solution_ref": "SOL-Y", "paths": {}}, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        multi_head = _commit(repo, "candidate-multiple", second_manifest)
        _git(repo, "checkout", "-q", "--detach", base)
        multi_changed = [custom_path, manifest_path, second_manifest]
        if emitter._candidate_manifest_data(repo, multi_changed, multi_head) is not None:
            raise AssertionError("multiple manifests must not be preselected by transport")
        try:
            emitter.ROUTER.classify(multi_changed, manifest_data=None)
        except emitter.ROUTER.ChangesetIntegrityError as exc:
            if exc.code != "FAIL_CHANGESET_MULTIPLE_SOLUTIONS":
                raise AssertionError(f"unexpected multiple-manifest failure: {exc}") from exc
        else:
            raise AssertionError("multiple manifests were not rejected")
        checks += 1

    if checks != 4:
        raise AssertionError(f"unexpected check count:{checks}")
    print("PASS_EXACT_HEAD_CANDIDATE_MANIFEST_TRANSPORT=4/4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
