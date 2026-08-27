#!/usr/bin/env python3
"""Zero-cost narrow semantic mini-judge on the pinned GitHub Actions llama.cpp runtime."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import github_actions_local_runtime as local
from profile_runtime_runner import RuntimeExecutionBlocked
from semantic_mini_judge import CheckResult, compact_semantic_payload, parse_model_response
from validate_profile_execution import canonical_json_sha256

ADAPTER_ID = "github-standard-qwen25vl-semantic-minijudge-v1"
VERIFIER_ID = "github-standard-qwen25vl-semantic-minijudge-readback-v1"
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE complies with RULE.
Do not rewrite, repair, propose, or expand the evidence.
Return exactly one JSON object with two keys:
{"verdict":"COMPLIES|CONTRADICTS|UNCERTAIN","reason_code":"SHORT_MACHINE_CODE"}
Use CONTRADICTS when the evidence reverses, violates, or ignores an explicit rule.
Use UNCERTAIN when the relationship cannot be established from the supplied text.
Never use UNCERTAIN as a substitute for an obvious contradiction.
"""


def _sha256_file(path: Path) -> str:
    return local._sha256_file(path)


class GitHubHostedSemanticMiniJudge:
    adapter_id = ADAPTER_ID
    is_test_double = False

    def __init__(self, *, work_dir: Path, timeout_seconds: int = 180,
                 max_output_tokens: int = 128, context_tokens: int = 2048) -> None:
        self.work_dir = work_dir
        self.timeout_seconds = timeout_seconds
        self.max_output_tokens = max_output_tokens
        self.context_tokens = context_tokens
        self.execution_files: dict[str, Path] = {}
        self.asset_paths: dict[str, Path] = {}

    def _assets(self) -> dict[str, Path]:
        local._require_zero_cost_runner()
        cli = local._required_asset("LF_LLAMA_CLI_PATH")
        model = local._required_asset("LF_MODEL_PATH", local.MODEL_SHA256)
        if not os.access(cli, os.X_OK):
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CLI_NOT_EXECUTABLE")
        self.asset_paths = {"llama_cli": cli, "model": model}
        return self.asset_paths

    def classify(self, check: dict[str, Any]) -> tuple[CheckResult, dict[str, Any]]:
        assets = self._assets()
        payload = compact_semantic_payload(check)
        run_dir = Path(tempfile.mkdtemp(prefix="lf-semantic-judge-", dir=self.work_dir))
        system_file = run_dir / "system.txt"
        input_file = run_dir / "check.json"
        output_file = run_dir / "raw-output.txt"
        system_file.write_text(SYSTEM_TEXT, encoding="utf-8")
        input_file.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        command = [
            str(assets["llama_cli"]),
            "-m", str(assets["model"]),
            "-sysf", str(system_file),
            "-f", str(input_file),
            "--simple-io", "--no-display-prompt", "--no-show-timings", "--log-disable",
            "-co", "off", "-c", str(self.context_tokens), "-n", str(self.max_output_tokens),
            "-t", "4", "--temp", "0", "--top-p", "1", "-s", "42", "-o", str(output_file),
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=self.work_dir,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.timeout_seconds,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_TIMEOUT") from exc
        if completed.returncode != 0:
            detail = completed.stderr[-1200:].replace("\n", " ").strip()
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_PROCESS_FAILED", f"rc={completed.returncode} stderr={detail}")
        if not output_file.is_file():
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_OUTPUT_FILE_MISSING")
        raw_text = output_file.read_text(encoding="utf-8").strip()
        if not raw_text:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_OUTPUT_EMPTY")
        result = parse_model_response(raw_text, check_id=check["check_id"])
        self.execution_files = {"system": system_file, "input": input_file, "output": output_file}
        evidence = {
            "adapter_id": self.adapter_id,
            "provider": "local_llama_cpp_github_standard_public",
            "model_id": local.MODEL_ID,
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "runner_label": os.environ.get("LF_RUNNER_LABEL", ""),
            "repository_visibility": os.environ.get("LF_REPOSITORY_VISIBILITY", ""),
            "llama_source_commit": local.LLAMA_SOURCE_COMMIT,
            "model_sha256": _sha256_file(assets["model"]),
            "llama_cli_sha256": _sha256_file(assets["llama_cli"]),
            "system_prompt_sha256": _sha256_file(system_file),
            "check_input_sha256": _sha256_file(input_file),
            "raw_output_sha256": _sha256_file(output_file),
            "classification": result.as_dict(),
        }
        return result, evidence


class GitHubHostedSemanticMiniJudgeVerifier:
    verifier_id = VERIFIER_ID
    is_test_double = False

    def verify(self, *, check: dict[str, Any], result: CheckResult,
               evidence: dict[str, Any], adapter: GitHubHostedSemanticMiniJudge) -> dict[str, Any]:
        local._require_zero_cost_runner()
        if adapter.adapter_id != ADAPTER_ID:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_ADAPTER_MISMATCH")
        assets = adapter.asset_paths
        files = adapter.execution_files
        if set(assets) != {"llama_cli", "model"} or set(files) != {"system", "input", "output"}:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_EVIDENCE_PATHS_MISSING")
        expected = {
            "model_sha256": local.MODEL_SHA256,
            "llama_cli_sha256": evidence.get("llama_cli_sha256"),
            "system_prompt_sha256": evidence.get("system_prompt_sha256"),
            "check_input_sha256": evidence.get("check_input_sha256"),
            "raw_output_sha256": evidence.get("raw_output_sha256"),
        }
        observed = {
            "model_sha256": _sha256_file(assets["model"]),
            "llama_cli_sha256": _sha256_file(assets["llama_cli"]),
            "system_prompt_sha256": _sha256_file(files["system"]),
            "check_input_sha256": _sha256_file(files["input"]),
            "raw_output_sha256": _sha256_file(files["output"]),
        }
        for key, value in expected.items():
            if observed[key] != value:
                raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_VERIFIER_HASH_MISMATCH", key)
        if evidence.get("classification") != result.as_dict():
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CLASSIFICATION_MISMATCH")
        if evidence.get("llama_source_commit") != local.LLAMA_SOURCE_COMMIT:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_LLAMA_COMMIT_MISMATCH")
        if evidence.get("repository_visibility") != "public":
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_VISIBILITY_MISMATCH")
        verification_payload = {
            "verifier_id": self.verifier_id,
            "check_id": check["check_id"],
            "classification": result.as_dict(),
            "observed_hashes": observed,
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "llama_source_commit": local.LLAMA_SOURCE_COMMIT,
        }
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "evidence_sha256": canonical_json_sha256(verification_payload),
        }
