#!/usr/bin/env python3
"""Zero-cost narrow semantic mini-judge on one resident pinned llama.cpp server."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import github_actions_local_runtime as local
from profile_runtime_runner import RuntimeExecutionBlocked
from semantic_mini_judge import CheckResult, compact_semantic_payload, parse_model_response
from validate_profile_execution import canonical_json_sha256

ADAPTER_ID = "github-standard-qwen25vl-semantic-minijudge-server-v2"
VERIFIER_ID = "github-standard-qwen25vl-semantic-minijudge-readback-v2"
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
    """Keeps one model process resident and sends only atomic checks over localhost."""

    adapter_id = ADAPTER_ID
    is_test_double = False

    def __init__(self, *, work_dir: Path, timeout_seconds: int = 90,
                 max_output_tokens: int = 96, context_tokens: int = 2048,
                 port: int = 18080) -> None:
        self.work_dir = work_dir
        self.timeout_seconds = timeout_seconds
        self.max_output_tokens = max_output_tokens
        self.context_tokens = context_tokens
        self.port = port
        self.execution_files: dict[str, Path] = {}
        self.asset_paths: dict[str, Path] = {}
        self.server_process: subprocess.Popen[str] | None = None
        self.server_stdout_path: Path | None = None
        self.server_stderr_path: Path | None = None
        self._server_stdout_handle = None
        self._server_stderr_handle = None

    def __enter__(self) -> "GitHubHostedSemanticMiniJudge":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _assets(self) -> dict[str, Path]:
        local._require_zero_cost_runner()
        server = local._required_asset("LF_LLAMA_SERVER_PATH")
        model = local._required_asset("LF_MODEL_PATH", local.MODEL_SHA256)
        if not os.access(server, os.X_OK):
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_SERVER_NOT_EXECUTABLE")
        self.asset_paths = {"llama_server": server, "model": model}
        return self.asset_paths

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def _health_ready(self) -> bool:
        request = urllib.request.Request(f"{self.base_url}/health", method="GET")
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                if response.status != 200:
                    return False
                body = json.loads(response.read().decode("utf-8"))
                return isinstance(body, dict) and body.get("status") == "ok"
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError):
            return False

    def start(self) -> None:
        if self.server_process is not None and self.server_process.poll() is None:
            return
        assets = self._assets()
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.server_stdout_path = self.work_dir / "semantic-server.stdout.log"
        self.server_stderr_path = self.work_dir / "semantic-server.stderr.log"
        self._server_stdout_handle = self.server_stdout_path.open("w", encoding="utf-8")
        self._server_stderr_handle = self.server_stderr_path.open("w", encoding="utf-8")
        command = [
            str(assets["llama_server"]),
            "-m", str(assets["model"]),
            "--host", "127.0.0.1",
            "--port", str(self.port),
            "-c", str(self.context_tokens),
            "-t", "4",
        ]
        self.server_process = subprocess.Popen(
            command,
            cwd=self.work_dir,
            stdin=subprocess.DEVNULL,
            stdout=self._server_stdout_handle,
            stderr=self._server_stderr_handle,
            text=True,
        )
        deadline = time.monotonic() + self.timeout_seconds
        while time.monotonic() < deadline:
            if self.server_process.poll() is not None:
                detail = ""
                if self.server_stderr_path.is_file():
                    detail = self.server_stderr_path.read_text(encoding="utf-8", errors="replace")[-1600:].replace("\n", " ")
                self.close()
                raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_SERVER_START_FAILED", detail)
            if self._health_ready():
                return
            time.sleep(0.5)
        self.close()
        raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_SERVER_START_TIMEOUT")

    def close(self) -> None:
        process = self.server_process
        self.server_process = None
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        for handle_name in ("_server_stdout_handle", "_server_stderr_handle"):
            handle = getattr(self, handle_name)
            if handle is not None:
                handle.close()
                setattr(self, handle_name, None)

    def _chat_completion(self, payload: dict[str, str]) -> str:
        request_payload = {
            "model": local.MODEL_ID,
            "messages": [
                {"role": "system", "content": SYSTEM_TEXT},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False, sort_keys=True)},
            ],
            "temperature": 0,
            "top_p": 1,
            "seed": 42,
            "max_tokens": self.max_output_tokens,
            "stream": False,
        }
        body = json.dumps(request_payload, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}/v1/chat/completions",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                envelope = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[-1200:]
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_HTTP_ERROR", f"status={exc.code} body={detail}") from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_HTTP_FAILURE", type(exc).__name__) from exc
        try:
            content = envelope["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_RESPONSE_SHAPE_INVALID") from exc
        if not isinstance(content, str) or not content.strip():
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_OUTPUT_EMPTY")
        return content.strip()

    def classify(self, check: dict[str, Any]) -> tuple[CheckResult, dict[str, Any]]:
        self.start()
        assets = self.asset_paths
        payload = compact_semantic_payload(check)
        run_dir = Path(tempfile.mkdtemp(prefix="lf-semantic-judge-", dir=self.work_dir))
        system_file = run_dir / "system.txt"
        input_file = run_dir / "check.json"
        output_file = run_dir / "raw-output.txt"
        system_file.write_text(SYSTEM_TEXT, encoding="utf-8")
        input_file.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        raw_text = self._chat_completion(payload)
        output_file.write_text(raw_text, encoding="utf-8")
        result = parse_model_response(raw_text, check_id=check["check_id"])
        self.execution_files = {"system": system_file, "input": input_file, "output": output_file}
        evidence = {
            "adapter_id": self.adapter_id,
            "provider": "local_llama_cpp_github_standard_public",
            "transport": "LOCALHOST_LLAMA_SERVER",
            "model_id": local.MODEL_ID,
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "runner_label": os.environ.get("LF_RUNNER_LABEL", ""),
            "repository_visibility": os.environ.get("LF_REPOSITORY_VISIBILITY", ""),
            "llama_source_commit": local.LLAMA_SOURCE_COMMIT,
            "model_sha256": _sha256_file(assets["model"]),
            "llama_server_sha256": _sha256_file(assets["llama_server"]),
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
        if set(assets) != {"llama_server", "model"} or set(files) != {"system", "input", "output"}:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_EVIDENCE_PATHS_MISSING")
        expected = {
            "model_sha256": local.MODEL_SHA256,
            "llama_server_sha256": evidence.get("llama_server_sha256"),
            "system_prompt_sha256": evidence.get("system_prompt_sha256"),
            "check_input_sha256": evidence.get("check_input_sha256"),
            "raw_output_sha256": evidence.get("raw_output_sha256"),
        }
        observed = {
            "model_sha256": _sha256_file(assets["model"]),
            "llama_server_sha256": _sha256_file(assets["llama_server"]),
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
        if evidence.get("transport") != "LOCALHOST_LLAMA_SERVER":
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_TRANSPORT_MISMATCH")
        verification_payload = {
            "verifier_id": self.verifier_id,
            "check_id": check["check_id"],
            "classification": result.as_dict(),
            "observed_hashes": observed,
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "llama_source_commit": local.LLAMA_SOURCE_COMMIT,
            "transport": "LOCALHOST_LLAMA_SERVER",
        }
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "evidence_sha256": canonical_json_sha256(verification_payload),
        }
