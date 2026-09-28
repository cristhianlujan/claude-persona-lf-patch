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
    validator = (
        "import sys\n"
        "print('E2E_LOCAL_VALIDATOR')\n"
        + ("raise SystemExit(9)\n" if validator_fails else "raise SystemExit(0)\n")
    )
    write(repo / "skills/e2e_probe/validators/validate_pack.py", validator)
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "head")
    head = git(repo, "rev-parse", "HEAD")
    return td, repo, base, head


def run_probe(*, validator_fails: bool) -> tuple[dict, dict, dict]:
    td, repo, base, head = make_repo(validator_fails=validator_fails)
    try:
        output_dir = repo / ".lf_pack_validation"
        changed = [
            "skills/e2e_probe/SKILL.md",
            "skills/e2e_probe/validators/validate_pack.py",
        ]
        completed = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--repo-root",
                str(repo),
                "--validation-contract",
                str(VALIDATION),
                "--discovery-contract",
                str(DISCOVERY),
                "--base-sha",
                base,
                "--head-sha",
                head,
                "--changed-paths-json",
                json.dumps(changed, separators=(",", ":")),
                "--output-dir",
                str(output_dir),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        expected_rc = 1 if validator_fails else 0
        assert completed.returncode == expected_rc, completed.stdout + completed.stderr
        discovery = json.loads((output_dir / "discovery.json").read_text(encoding="utf-8"))
        result = json.loads((output_dir / "result.json").read_text(encoding="utf-8"))
        summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))

        assert discovery["status"] == "PASS", discovery
        assert len(discovery["affected_packs"]) == 1, discovery
        assert discovery["affected_packs"][0]["pack_root"] == "skills/e2e_probe", discovery
        assert result["evidence"]["exact_head_verified"] is True, result
        assert result["base_sha"] == base and result["head_sha"] == head, result
        assert summary["base_sha"] == base and summary["head_sha"] == head, summary
        assert summary["affected_pack_count"] == 1 and summary["executed_pack_count"] == 1, summary

        for field in (
            "runtime_authorized",
            "git_write_authorized",
            "db_write_authorized",
            "deployment_authorized",
            "production_authorized",
        ):
            assert result[field] is False, (field, result)
            assert summary[field] is False, (field, summary)
        assert result["semantic_quality_review_authorized"] is False, result

        if validator_fails:
            assert result["status"] == "FAIL" and summary["status"] == "FAIL", (result, summary)
            assert any("PACK_LOCAL_VALIDATOR_FAILED" in code for code in result["blocking_codes"]), result
            assert result["affected_packs"][0]["status"] == "FAIL", result
        else:
            assert result["status"] == "PASS" and summary["status"] == "PASS", (result, summary)
            assert result["blocking_codes"] == [], result
            assert result["affected_packs"][0]["status"] == "PASS", result
            assert summary["pass_count"] == 1 and summary["fail_count"] == 0, summary

        return discovery, result, summary
    finally:
        td.cleanup()


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert contract["durable_name"] == "PACK_VALIDATION_VERIFY_E2E_FLOW"
    assert contract["owner"] == "PACK_VALIDATION"
    assert contract["next_handoff"] == "STEP_08_READBACK_TRACEABILITY_CLOSE"
    assert contract["proof_model"]["positive_pack_probe"]["repository_pack_mutation"] is False
    assert contract["proof_model"]["negative_pack_probe"]["repository_pack_mutation"] is False

    source = SOURCE_WORKFLOW.read_text(encoding="utf-8")
    assert "LF_CHANGED_PATHS_JSON: ${{ steps.ci_plan.outputs.changed_paths_json }}" in source
    assert "LF_PACK_BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before || inputs.base_main_sha }}" in source
    assert "LF_PACK_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}" in source
    assert source.count("run_pack_validation_flow_v1.py") == 1
    assert "Persist bounded Pack Validation evidence" in source

    positive = run_probe(validator_fails=False)
    negative = run_probe(validator_fails=True)
    print(
        "PACK_VALIDATION_VERIFY_E2E_FLOW=PASS "
        f"positive={positive[2]['status']} negative={negative[2]['status']}"
    )


if __name__ == "__main__":
    main()
