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
CARRIER = ROOT / ".github/workflows/validate-lf-packs.yml"
CONTRACT = ROOT / "gobernanza/contratos/pack_validation_clean_workflow_v1.json"

spec = importlib.util.spec_from_file_location("run_pack_validation_flow_v1", RUNNER)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
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
    write(repo / "profiles/alpha/validators/validate_pack.py", "raise SystemExit(0)\n")
    run("git", "add", ".", cwd=repo)
    run("git", "commit", "-qm", "base", cwd=repo)
    base = run("git", "rev-parse", "HEAD", cwd=repo)
    write(repo / "profiles/alpha/SKILL.md", "# alpha\n")
    run("git", "add", ".", cwd=repo)
    run("git", "commit", "-qm", "head", cwd=repo)
    head = run("git", "rev-parse", "HEAD", cwd=repo)
    validation = {"durable_name":"PACK_VALIDATION_DEFINE_CONTRACT","pack_types":{"PROFILE_PACK":{"roots":["profiles/"],"local_validator_contract":"validators/validate_pack.py"}}}
    discovery = {"durable_name":"PACK_DISCOVERY_RESOLVE_AFFECTED_PACKS","depends_on":"PACK_VALIDATION_DEFINE_CONTRACT","rules":[{"rule_id":"PROFILE_DIRECT","pack_type":"PROFILE_PACK","mode":"DIRECT_CHILD","trigger_prefix":"profiles/","target_root":"profiles/"}]}
    validation_path = repo / "validation.json"
    discovery_path = repo / "discovery.json"
    write(validation_path, json.dumps(validation))
    write(discovery_path, json.dumps(discovery))
    return td, repo, base, head, validation_path, discovery_path


def test_contract_identity_and_boundary() -> None:
    c = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert c["durable_name"] == "PACK_VALIDATION_CLEAN_WORKFLOW"
    assert c["owner"] == "PACK_VALIDATION"
    assert c["workflow"]["activation"] == "LOCAL_CANDIDATE_READY_FOR_EXTERNAL_BINDING"
    assert c["workflow"]["consumer_wiring"] == "WAITING_FOR_PASE_ORCHESTRATOR"
    assert c["scope_invariants"]["foreign_owner_work_forbidden"] is True
    assert c["scope_invariants"]["orchestrator_design_not_owned_here"] is True
    assert c["operational_plan"]["local_progress_percent"] == 100


def test_core_matches_staged_and_has_no_autonomous_trigger() -> None:
    assert TARGET_WORKFLOW.read_text(encoding="utf-8") == WORKFLOW.read_text(encoding="utf-8")
    text = TARGET_WORKFLOW.read_text(encoding="utf-8")
    assert "workflow_call:" in text
    for forbidden in ("pull_request:", "push:", "workflow_dispatch:", "schedule:"):
        assert forbidden not in text, forbidden


def test_carrier_is_pack_only_and_calls_core_once() -> None:
    text = CARRIER.read_text(encoding="utf-8")
    assert text.count("uses: ./.github/workflows/lf-pack-validation-core.yml") == 1
    assert "workflow_call:" in text and "pull_request:" in text and "push:" in text
    for forbidden in (
        "PROFILE_RUNTIME_V3", "S30_BOUNDED_REGRESSION", "GATE_CHECK_OBSERVABILITY",
        "TRANSVERSAL_README", "work_protocol", "PGPASSWORD", "psql ",
        "persist_gate_failures_to_ekb", "lf-db-regression", "assurance"
    ):
        assert forbidden.lower() not in text.lower(), forbidden


def test_exact_head_pack_pass() -> None:
    td, repo, base, head, validation, discovery = git_repo()
    try:
        summary = mod.run_flow(repo_root=repo, validation_contract_path=validation, discovery_contract_path=discovery, base_sha=base, head_sha=head, changed_paths=["profiles/alpha/SKILL.md"], output_dir=repo / ".lf_pack_validation", verify_git=True)
        assert summary["status"] == "PASS", summary
        assert summary["affected_pack_count"] == 1 and summary["executed_pack_count"] == 1, summary
        assert summary["pass_count"] == 1 and summary["fail_count"] == 0, summary
    finally:
        td.cleanup()


def test_changed_paths_tamper_fails_closed() -> None:
    td, repo, base, head, validation, discovery = git_repo()
    try:
        try:
            mod.run_flow(repo_root=repo, validation_contract_path=validation, discovery_contract_path=discovery, base_sha=base, head_sha=head, changed_paths=[], output_dir=repo / ".lf_pack_validation", verify_git=True)
        except ValueError as exc:
            assert str(exc) == "CHANGED_PATHS_MISMATCH"
        else:
            raise AssertionError("expected CHANGED_PATHS_MISMATCH")
    finally:
        td.cleanup()


def test_authorizations_are_all_false() -> None:
    c = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert c["output_contract"]["authorizations"] == {
        "runtime_authorized": False,
        "git_write_authorized": False,
        "db_write_authorized": False,
        "deployment_authorized": False,
        "production_authorized": False,
    }


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print(f"PASS_PACK_VALIDATION_CLEAN_WORKFLOW_V1={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
