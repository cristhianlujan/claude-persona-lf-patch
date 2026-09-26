#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/run_pack_validation_flow_v1.py"
WORKFLOW = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/lf-pack-validation-core.staged.yml"
TARGET_WORKFLOW = ROOT / ".github/workflows/lf-pack-validation-core.yml"
CONTRACT = ROOT / "gobernanza/contratos/pack_validation_clean_workflow_v1.json"

spec = importlib.util.spec_from_file_location("run_pack_validation_flow_v1", RUNNER)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run(*args: str, cwd: Path) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def git_repo() -> tuple[tempfile.TemporaryDirectory[str], Path, str, str, Path, Path]:
    td = tempfile.TemporaryDirectory()
    repo = Path(td.name)
    run("git", "init", "-q", cwd=repo)
    run("git", "config", "user.email", "pack-validation-test@example.invalid", cwd=repo)
    run("git", "config", "user.name", "Pack Validation Test", cwd=repo)
    write(repo / "README.md", "base\n")
    run("git", "add", ".", cwd=repo)
    run("git", "commit", "-qm", "base", cwd=repo)
    base = run("git", "rev-parse", "HEAD", cwd=repo)

    write(repo / "profiles/alpha/SKILL.md", "# alpha\n")
    write(
        repo / "profiles/alpha/validators/validate_pack.py",
        "import sys\nprint('LOCAL_PACK_PASS')\nraise SystemExit(0)\n",
    )
    run("git", "add", ".", cwd=repo)
    run("git", "commit", "-qm", "head", cwd=repo)
    head = run("git", "rev-parse", "HEAD", cwd=repo)

    validation = {
        "durable_name": "PACK_VALIDATION_DEFINE_CONTRACT",
        "pack_types": {
            "PROFILE_PACK": {
                "roots": ["profiles/"],
                "local_validator_contract": "validators/validate_pack.py",
            }
        },
    }
    discovery = {
        "durable_name": "PACK_DISCOVERY_RESOLVE_AFFECTED_PACKS",
        "depends_on": "PACK_VALIDATION_DEFINE_CONTRACT",
        "rules": [
            {
                "rule_id": "PROFILE_DIRECT",
                "pack_type": "PROFILE_PACK",
                "mode": "DIRECT_CHILD",
                "trigger_prefix": "profiles/",
                "target_root": "profiles/",
            }
        ],
    }
    validation_path = repo / "validation.json"
    discovery_path = repo / "discovery.json"
    write(validation_path, json.dumps(validation))
    write(discovery_path, json.dumps(discovery))
    return td, repo, base, head, validation_path, discovery_path


def test_contract_identity_and_handoff() -> None:
    c = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert c["durable_name"] == "PACK_VALIDATION_CLEAN_WORKFLOW"
    assert c["owner"] == "PACK_VALIDATION"
    assert c["workflow"]["activation"] == "STAGED_DEFINITION_ONLY"
    assert c["workflow"]["staged_definition_path"].endswith("lf-pack-validation-core.staged.yml")
    assert c["workflow"]["target_cutover_path"] == ".github/workflows/lf-pack-validation-core.yml"
    assert c["workflow"]["legacy_carrier_remains_active_until_cutover"] == ".github/workflows/validate-lf-packs.yml"
    assert c["next_handoff"] == "CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS"


def test_staged_definition_has_no_autonomous_trigger() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "workflow_call:" in text
    for forbidden in ("pull_request:", "push:", "workflow_dispatch:", "schedule:"):
        assert forbidden not in text, forbidden


def test_target_workflow_not_installed_before_cutover() -> None:
    assert not TARGET_WORKFLOW.exists(), "target carrier must remain absent until PR-6 cutover"


def test_workflow_contains_only_pack_validation_boundary() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    required = [
        "Execute PACK_VALIDATION",
        "run_pack_validation_flow_v1.py",
        "pack_validation_define_contract_v1.json",
        "pack_discovery_resolve_affected_packs_v1.json",
        "contents: read",
    ]
    for token in required:
        assert token in text, token
    forbidden = [
        "PROFILE_RUNTIME_V3",
        "S30_BOUNDED_REGRESSION",
        "S30_BROKER",
        "GATE_CHECK_OBSERVABILITY",
        "SUPABASE",
        "PGPASSWORD",
        "psql ",
        "persist_gate_failures_to_ekb",
        "semantic-to-render",
        "profile_runtime_api",
    ]
    lowered = text.lower()
    for token in forbidden:
        assert token.lower() not in lowered, token


def test_exact_head_pack_pass() -> None:
    td, repo, base, head, validation, discovery = git_repo()
    try:
        summary = mod.run_flow(
            repo_root=repo,
            validation_contract_path=validation,
            discovery_contract_path=discovery,
            base_sha=base,
            head_sha=head,
            changed_paths=["profiles/alpha/SKILL.md"],
            output_dir=repo / ".lf_pack_validation",
            verify_git=True,
        )
        assert summary["status"] == "PASS", summary
        assert summary["affected_pack_count"] == 1, summary
        assert summary["executed_pack_count"] == 1, summary
        assert summary["pass_count"] == 1 and summary["fail_count"] == 0, summary
        result = json.loads((repo / ".lf_pack_validation/result.json").read_text(encoding="utf-8"))
        assert result["affected_packs"][0]["pack_root"] == "profiles/alpha"
        assert result["evidence"]["exact_head_verified"] is True
    finally:
        td.cleanup()


def test_non_pack_change_skips_without_validator_execution() -> None:
    td, repo, base, head, validation, discovery = git_repo()
    try:
        summary = mod.run_flow(
            repo_root=repo,
            validation_contract_path=validation,
            discovery_contract_path=discovery,
            base_sha=base,
            head_sha=head,
            changed_paths=["README.md"],
            output_dir=repo / ".lf_pack_validation",
            verify_git=True,
        )
        assert summary["status"] == "SKIP", summary
        assert summary["affected_pack_count"] == 0, summary
        assert summary["executed_pack_count"] == 0, summary
    finally:
        td.cleanup()


def test_invalid_changed_paths_json_fails_closed() -> None:
    try:
        mod._changed_paths('{"not":"a-list"}')
    except ValueError as exc:
        assert str(exc) == "CHANGED_PATHS_JSON_INVALID"
    else:
        raise AssertionError("expected CHANGED_PATHS_JSON_INVALID")


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print(f"PASS_PACK_VALIDATION_CLEAN_WORKFLOW_V1={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
