#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNNER_PATH = ROOT / "lf_governed_canary_runner.py"
spec = importlib.util.spec_from_file_location("lf_governed_canary_runner", RUNNER_PATH)
assert spec and spec.loader
runner = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runner
spec.loader.exec_module(runner)


def step(step_id: str, code: str, token: str):
    return {
        "id": step_id,
        "argv": [sys.executable, "-c", code],
        "timeout_seconds": 10,
        "env_names": [],
        "expect": {"exit_codes": [0], "stdout_contains": [token]},
    }


def build_manifest(workdir: Path) -> dict:
    marker = workdir / "repository_only_candidate.txt"
    evidence = workdir / "repository_only_evidence.json"
    return {
        "contract_version": runner.VERSION,
        "canary_id": "S28:REPOSITORY-ONLY-REFERENCE-001",
        "change_mode": "REPOSITORY_ONLY",
        "target": {
            "environment": "ephemeral",
            "production": False,
            "merge_authorized": False,
            "automatic_promotion": False,
        },
        "steps": {
            "preflight": [step("REPO_PREFLIGHT", "print('REPO_PREFLIGHT_PASS')", "REPO_PREFLIGHT_PASS")],
            "forward": [step("REPO_FORWARD", f"from pathlib import Path; Path(r'{marker}').write_text('candidate', encoding='utf-8'); print('REPO_FORWARD_PASS')", "REPO_FORWARD_PASS")],
            "tests": [step("REPO_TEST", f"from pathlib import Path; assert Path(r'{marker}').read_text(encoding='utf-8') == 'candidate'; print('REPO_TEST_PASS')", "REPO_TEST_PASS")],
            "rollback": [step("REPO_ROLLBACK", f"from pathlib import Path; p=Path(r'{marker}'); p.unlink(missing_ok=True); print('REPO_ROLLBACK_PASS')", "REPO_ROLLBACK_PASS")],
            "post_readback": [step("REPO_POST_READBACK", f"from pathlib import Path; assert not Path(r'{marker}').exists(); print('ZERO_RESIDUE_PASS')", "ZERO_RESIDUE_PASS")],
        },
        "evidence": {
            "output_path": str(evidence),
            "include_raw_output": False,
            "require_post_readback": True,
            "require_zero_residue": True,
            "zero_residue_token": "ZERO_RESIDUE_PASS",
        },
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", type=Path, required=True)
    args = parser.parse_args(argv)
    args.workdir.mkdir(parents=True, exist_ok=True)
    packet = runner.execute_manifest(build_manifest(args.workdir))
    print(json.dumps({
        "consumer": "REPOSITORY_ONLY_REFERENCE",
        "result": packet["result"],
        "rollback_attempted": packet["rollback_attempted"],
        "post_readback_attempted": packet["post_readback_attempted"],
        "step_count": len(packet["steps"]),
        "claim_ceiling": packet["claim_ceiling"],
    }, sort_keys=True, separators=(",", ":")))
    return 0 if packet["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
