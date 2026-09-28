#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/run_pack_validation_flow_v1.py"
VALIDATION = ROOT / "gobernanza/contratos/pack_validation_define_contract_v1.json"
DISCOVERY = ROOT / "gobernanza/contratos/pack_discovery_resolve_affected_packs_v1.json"
CONTRACT = ROOT / "gobernanza/contratos/pack_validation_verify_e2e_flow_v1.json"
SOURCE_WORKFLOW = ROOT / ".github/workflows/validate-lf-packs.yml"
CORE = ROOT / ".github/workflows/lf-pack-validation-core.yml"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def make_repo(*, validator_fails: bool) -> tuple[tempfile.TemporaryDirectory[str], Path, str, str]:
    td = tempfile.TemporaryDirectory()
    repo = Path(td.name)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    git(repo, "config", "user.email", "pack-validation-e2e@example.invalid")
    git(repo, "config", "user.name", "Pack Validation E2E")
    write(repo / "README.md", "base\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "base")
    base = git(repo, "rev-parse", "HEAD")
    write(repo / "skills/e2e_probe/SKILL.md", "# e2e probe\n")
    write(repo / "skills/e2e_probe/validators/validate_pack.py", "raise SystemExit(%d)\n" % (9 if validator_fails else 0))
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "head")
    head = git(repo, "rev-parse", "HEAD")
    return td, repo, base, head


def run_probe(*, validator_fails: bool) -> dict:
    td, repo, base, head = make_repo(validator_fails=validator_fails)
    try:
        out = repo / ".lf_pack_validation"
        changed = ["skills/e2e_probe/SKILL.md", "skills/e2e_probe/validators/validate_pack.py"]
        cp = subprocess.run([
            sys.executable, str(RUNNER), "--repo-root", str(repo),
            "--validation-contract", str(VALIDATION), "--discovery-contract", str(DISCOVERY),
            "--base-sha", base, "--head-sha", head,
            "--changed-paths-json", json.dumps(changed, separators=(",", ":")),
            "--output-dir", str(out),
        ], cwd=ROOT, text=True, capture_output=True, check=False)
        assert cp.returncode == (1 if validator_fails else 0), cp.stdout + cp.stderr
        summary = json.loads((out / "summary.json").read_text(encoding="utf-8"))
        result = json.loads((out / "result.json").read_text(encoding="utf-8"))
        assert summary["affected_pack_count"] == 1 and summary["executed_pack_count"] == 1, summary
        assert result["evidence"]["exact_head_verified"] is True, result
        if validator_fails:
            assert summary["status"] == "FAIL"
            assert any("PACK_LOCAL_VALIDATOR_FAILED" in x for x in result["blocking_codes"])
        else:
            assert summary["status"] == "PASS"
        for field in ("runtime_authorized", "git_write_authorized", "db_write_authorized", "deployment_authorized", "production_authorized"):
            assert summary[field] is False
        return summary
    finally:
        td.cleanup()


def run_tamper_probe() -> dict:
    td, repo, base, head = make_repo(validator_fails=False)
    try:
        out = repo / ".lf_pack_validation"
        cp = subprocess.run([
            sys.executable, str(RUNNER), "--repo-root", str(repo),
            "--validation-contract", str(VALIDATION), "--discovery-contract", str(DISCOVERY),
            "--base-sha", base, "--head-sha", head,
            "--changed-paths-json", json.dumps(["skills/e2e_probe/SKILL.md"]),
            "--output-dir", str(out),
        ], cwd=ROOT, text=True, capture_output=True, check=False)
        assert cp.returncode == 1, cp.stdout + cp.stderr
        summary = json.loads((out / "summary.json").read_text(encoding="utf-8"))
        assert summary["blocking_codes"] == ["CHANGED_PATHS_MISMATCH"], summary
        assert not (out / "discovery.json").exists()
        return summary
    finally:
        td.cleanup()


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert contract["owner"] == "PACK_VALIDATION"
    source = SOURCE_WORKFLOW.read_text(encoding="utf-8")
    core = CORE.read_text(encoding="utf-8")
    assert source.count("uses: ./.github/workflows/lf-pack-validation-core.yml") == 1
    assert "base_sha: ${{ needs.pack-context.outputs.base_sha }}" in source
    assert "head_sha: ${{ needs.pack-context.outputs.head_sha }}" in source
    assert "changed_paths_json: ${{ needs.pack-context.outputs.changed_paths_json }}" in source
    assert "run_pack_validation_flow_v1.py" in core
    for foreign in ("PROFILE_RUNTIME_V3", "S30_BOUNDED_REGRESSION", "GATE_CHECK_OBSERVABILITY", "TRANSVERSAL_README"):
        assert foreign not in source
        assert foreign not in core
    positive = run_probe(validator_fails=False)
    negative = run_probe(validator_fails=True)
    tamper = run_tamper_probe()
    print(f"PACK_VALIDATION_VERIFY_E2E_FLOW=PASS positive={positive['status']} negative={negative['status']} tamper={tamper['blocking_codes'][0]}")


if __name__ == "__main__":
    main()
