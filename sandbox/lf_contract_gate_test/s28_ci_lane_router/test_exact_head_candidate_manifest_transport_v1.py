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


def main() -> int:
    emitter = _load(EMITTER_PATH, "emit_ci_execution_plan_v2_manifest_transport_test")
    manifest_path = "sandbox/lf_contract_gate_test/changesets/SOL-X.json"
    custom_path = "custom/a.py"

    with tempfile.TemporaryDirectory(prefix="lf-candidate-manifest-test-") as td:
        repo = Path(td)
        _git(repo, "init", "-q")
        _git(repo, "config", "user.email", "ci@example.invalid")
        _git(repo, "config", "user.name", "CI")
        (repo / "README.md").write_text("base\n", encoding="utf-8")
        _git(repo, "add", "README.md")
        _git(repo, "commit", "-qm", "base")
        base = _git(repo, "rev-parse", "HEAD")

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
        custom.write_text("x = 1\n", encoding="utf-8")
        _git(repo, "add", manifest_path, custom_path)
        _git(repo, "commit", "-qm", "candidate")
        head = _git(repo, "rev-parse", "HEAD")

        _git(repo, "checkout", "-q", "--detach", base)
        if (repo / manifest_path).exists():
            raise AssertionError("candidate manifest leaked into trusted base checkout")

        changed = [custom_path, manifest_path]
        manifest_data = emitter._candidate_manifest_data(repo, changed, head)
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

    print("PASS_EXACT_HEAD_CANDIDATE_MANIFEST_TRANSPORT=1/1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
