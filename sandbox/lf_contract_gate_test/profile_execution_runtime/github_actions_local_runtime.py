#!/usr/bin/env python3
"""Zero-cost GitHub standard-runner llama.cpp adapter and independent verifier."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from validate_profile_execution import canonical_json_sha256, sha256_text

TARGET_REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
ADAPTER_ID = "github-standard-llamacpp-qwen25vl-v1"
VERIFIER_ID = "github-standard-llamacpp-readback-v1"

LLAMA_RELEASE = "b10642"
LLAMA_SOURCE_COMMIT = "925e1179947ea0c0ebfb0032df18af3a729822be"
MODEL_REPO = "ggml-org/Qwen2.5-VL-3B-Instruct-GGUF"
MODEL_COMMIT = "5037fcf163dd95d1e41d1974465f0898ed108ca2"
MODEL_FILENAME = "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
MODEL_SHA256 = "d02fe9b69ad8cadbbd228e387667af66612c44bed29ffc8eb1e7caf9ac486c12"
MMPROJ_FILENAME = "mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"
MMPROJ_SHA256 = "980c9b2f78c04e6cff93d277ada09e768394f112d75db3b4e9dea8a69f9fb904"
MODEL_ID = f"{MODEL_REPO}@{MODEL_COMMIT}:{MODEL_FILENAME}"
MAX_IMAGE_BYTES = 12 * 1024 * 1024


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _require_zero_cost_runner() -> dict[str, str]:
    observed = {
        "github_actions": os.getenv("GITHUB_ACTIONS", ""),
        "runner_os": os.getenv("RUNNER_OS", ""),
        "runner_arch": os.getenv("RUNNER_ARCH", ""),
        "repository": os.getenv("GITHUB_REPOSITORY", ""),
        "visibility": os.getenv("LF_REPOSITORY_VISIBILITY", ""),
        "runner_label": os.getenv("LF_RUNNER_LABEL", ""),
        "llama_source_commit": os.getenv("LF_LLAMA_SOURCE_COMMIT", ""),
    }
    expected = {
        "github_actions": "true",
        "runner_os": "Linux",
        "runner_arch": "X64",
        "repository": TARGET_REPOSITORY,
        "visibility": "public",
        "runner_label": "ubuntu-latest",
        "llama_source_commit": LLAMA_SOURCE_COMMIT,
    }
    for key, value in expected.items():
        if observed[key] != value:
            raise RuntimeExecutionBlocked("ZERO_COST_GITHUB_RUNNER_PRECONDITION_FAILED", f"{key}={observed[key]!r}")
    return observed


def _required_asset(env_name: str, expected_sha: str | None = None) -> Path:
    raw = os.getenv(env_name, "").strip()
    if not raw:
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_ASSET_ENV_MISSING", env_name)
    path = Path(raw).resolve()
    if not path.is_file():
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_ASSET_MISSING", env_name)
    if expected_sha and _sha256_file(path) != expected_sha:
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_ASSET_SHA256_MISMATCH", env_name)
    return path


def _resolve_runtime_output_schema(work_dir: Path, profile_slug: str) -> Path | None:
    if not profile_slug or "/" in profile_slug or "\\" in profile_slug or profile_slug in {".", ".."}:
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_SCHEMA_PROFILE_SLUG_INVALID")
    repo_root = work_dir.resolve()
    profiles_root = (repo_root / "profiles").resolve()
    profile_root = (profiles_root / profile_slug).resolve()
    try:
        profile_root.relative_to(profiles_root)
    except ValueError as exc:
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_SCHEMA_PATH_ESCAPE") from exc
    schema_root = (profile_root / "schemas").resolve()
    schema_path = (schema_root / "runtime_output.schema.json").resolve()
    try:
        schema_path.relative_to(schema_root)
    except ValueError as exc:
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_SCHEMA_PATH_ESCAPE") from exc
    if not schema_path.exists():
        return None
    if not schema_path.is_file():
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_SCHEMA_INVALID")
    try:
        payload = json.loads(schema_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_SCHEMA_INVALID_JSON") from exc
    if not isinstance(payload, dict):
        raise RuntimeExecutionBlocked("LOCAL_RUNTIME_SCHEMA_INVALID")
    return schema_path


def _render_profile_instructions(request: dict[str, Any]) -> str:
    parts = [
        "Execute the governed repository profile defined by the canonical sources below.",
        "Treat those sources as the governing profile instructions for this run.",
        "Apply them to the user's literal input and attached image, if present.",
        "Return the profile's direct output only.",
        "Do not reconstruct an expected answer or discuss the runtime wrapper.",
        "Do not invent facts absent from the canonical sources, literal input, image, or Router-bound adapter capsules.",
        "",
    ]
    for source in request["profile_sources"]:
        parts.extend([
            f"--- BEGIN CANONICAL PROFILE SOURCE: {source['ref']} ---",
            source["content"],
            f"--- END CANONICAL PROFILE SOURCE: {source['ref']} ---",
            "",
        ])

    adapter_sources = request.get("lf_adapter_sources") or []
    if adapter_sources:
        parts.extend([
            "The LF Router resolved the following adapter capsules for this SAME model execution.",
            "They constrain how the profile decision is applied; they do not replace or expand profile authority.",
            "Apply each capsule in this execution only. Never call, simulate, or delegate to a separate adapter worker or second model call.",
            "",
        ])
        for source in adapter_sources:
            parts.extend([
                f"--- BEGIN ROUTER-BOUND LF ADAPTER CAPSULE: {source['adapter_code']} | {source['ref']} ---",
                source["content"],
                f"--- END ROUTER-BOUND LF ADAPTER CAPSULE: {source['adapter_code']} | {source['ref']} ---",
                "",
            ])
    return "\n".join(parts).rstrip()


class GitHubHostedLlamaCppAdapter:
    adapter_id = ADAPTER_ID
    is_test_double = False

    def __init__(self, *, work_dir: Path, image_path: Path | None = None,
                 image_sha256: str | None = None, timeout_seconds: int = 900,
                 max_output_tokens: int = 2048, context_tokens: int = 16384) -> None:
        self.work_dir = work_dir
        self.image_path = image_path
        self.image_sha256 = image_sha256
        self.timeout_seconds = timeout_seconds
        self.max_output_tokens = max_output_tokens
        self.context_tokens = context_tokens
        self.asset_paths: dict[str, Path] = {}
        self.execution_files: dict[str, Path] = {}
        self.structured_output_schema_path: Path | None = None
        if (image_path is None) != (image_sha256 is None):
            raise RuntimeExecutionBlocked("LOCAL_RUNTIME_IMAGE_BINDING_INCOMPLETE")
        if image_path is not None:
            if not image_path.is_file() or image_path.stat().st_size > MAX_IMAGE_BYTES:
                raise RuntimeExecutionBlocked("LOCAL_RUNTIME_IMAGE_INVALID")
            if _sha256_file(image_path) != image_sha256:
                raise RuntimeExecutionBlocked("LOCAL_RUNTIME_IMAGE_SHA256_MISMATCH")

    def _assets(self) -> dict[str, Path]:
        cli = _required_asset("LF_LLAMA_CLI_PATH")
        model = _required_asset("LF_MODEL_PATH", MODEL_SHA256)
        mmproj = _required_asset("LF_MMPROJ_PATH", MMPROJ_SHA256)
        if not os.access(cli, os.X_OK):
            raise RuntimeExecutionBlocked("LOCAL_RUNTIME_CLI_NOT_EXECUTABLE")
        self.asset_paths = {"llama_cli": cli, "model": model, "mmproj": mmproj}
        return self.asset_paths

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        runner = _require_zero_cost_runner()
        assets = self._assets()
        self.structured_output_schema_path = _resolve_runtime_output_schema(self.work_dir, request["profile_slug"])
        run_dir = Path(tempfile.mkdtemp(prefix="lf-profile-run-", dir=self.work_dir))
        system_file = run_dir / "system.txt"
        input_file = run_dir / "input.txt"
        output_file = run_dir / "raw-output.txt"
        system_file.write_text(_render_profile_instructions(request), encoding="utf-8")
        input_file.write_text(request["input_literal"], encoding="utf-8")

        command = [
            str(assets["llama_cli"]), "-m", str(assets["model"]),
            "-mm", str(assets["mmproj"]), "-sysf", str(system_file),
            "-f", str(input_file), "-st", "--simple-io", "--no-display-prompt",
            "--no-show-timings", "--log-disable", "-co", "off",
            "-c", str(self.context_tokens), "-n", str(self.max_output_tokens),
            "-t", "4", "--temp", "0.2", "--top-p", "0.9", "-s", "42",
            "-o", str(output_file),
        ]
        if self.structured_output_schema_path is not None:
            command.extend(["-jf", str(self.structured_output_schema_path)])
        if self.image_path is not None:
            command.extend(["--image", str(self.image_path)])
        try:
            completed = subprocess.run(
                command, cwd=self.work_dir, stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=self.timeout_seconds, check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeExecutionBlocked("LOCAL_RUNTIME_TIMEOUT") from exc
        if completed.returncode != 0:
            detail = completed.stderr[-1500:].replace("\n", " ").strip()
            raise RuntimeExecutionBlocked("LOCAL_RUNTIME_PROCESS_FAILED", f"rc={completed.returncode} stderr={detail}")
        if not output_file.is_file():
            raise RuntimeExecutionBlocked("LOCAL_RUNTIME_OUTPUT_FILE_MISSING")
        raw_text = output_file.read_text(encoding="utf-8").strip()
        if not raw_text:
            raise RuntimeExecutionBlocked("LOCAL_RUNTIME_OUTPUT_EMPTY")

        self.execution_files = {"system": system_file, "input": input_file, "output": output_file}
        attestation = {
            "provider": "local_llama_cpp_github_standard_public",
            "model_id": MODEL_ID,
            "run_id": f"github-actions:{os.environ['GITHUB_RUN_ID']}:{os.getenv('GITHUB_RUN_ATTEMPT','1')}",
            "attested_at": _utc_now(), "adapter_id": self.adapter_id,
            "request_sha256": request["request_sha256"],
            "profile_source_sha256": request["profile_source_sha256"],
            "input_sha256": request["input_sha256"],
            "operation_code": request["operation_code"],
            "profile_code": request["profile_code"], "profile_slug": request["profile_slug"],
            "zero_cost_policy": "ZERO_COST_ONLY", "github_repository": runner["repository"],
            "github_sha": os.getenv("GITHUB_SHA", ""), "github_run_id": os.environ["GITHUB_RUN_ID"],
            "github_run_attempt": os.getenv("GITHUB_RUN_ATTEMPT", "1"),
            "runner_label": runner["runner_label"], "repository_visibility": runner["visibility"],
            "llama_release": LLAMA_RELEASE, "llama_source_commit": LLAMA_SOURCE_COMMIT,
            "llama_cli_sha256": _sha256_file(assets["llama_cli"]),
            "model_sha256": MODEL_SHA256, "mmproj_sha256": MMPROJ_SHA256,
            "system_prompt_sha256": _sha256_file(system_file),
            "literal_input_file_sha256": _sha256_file(input_file),
            "raw_output_file_sha256": _sha256_file(output_file),
            "lf_adapter_invocation_count": str(len(request.get("lf_adapter_sources") or [])),
        }
        if self.structured_output_schema_path is not None:
            attestation["structured_output_schema_ref"] = str(
                self.structured_output_schema_path.relative_to(self.work_dir.resolve())
            )
            attestation["structured_output_schema_sha256"] = _sha256_file(self.structured_output_schema_path)
        if request.get("lf_adapter_source_sha256"):
            attestation["lf_adapter_source_sha256"] = request["lf_adapter_source_sha256"]
        if self.image_path is not None:
            attestation["input_image_sha256"] = self.image_sha256
            attestation["input_image_size_bytes"] = str(self.image_path.stat().st_size)
        return {"response_type": RESPONSE_TYPE, "raw_output": raw_text, "runtime_attestation": attestation}


class GitHubHostedLlamaCppVerifier:
    verifier_id = VERIFIER_ID
    is_test_double = False

    def __init__(self, *, expected_image_path: Path | None = None,
                 expected_image_sha256: str | None = None) -> None:
        self.expected_image_path = expected_image_path
        self.expected_image_sha256 = expected_image_sha256
        if (expected_image_path is None) != (expected_image_sha256 is None):
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_IMAGE_BINDING_INCOMPLETE")

    def verify(self, *, request: dict[str, Any], response: dict[str, Any], adapter: Any) -> dict[str, Any]:
        runner = _require_zero_cost_runner()
        if getattr(adapter, "adapter_id", None) != ADAPTER_ID:
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_ADAPTER_MISMATCH")
        attestation = response.get("runtime_attestation")
        if not isinstance(attestation, dict):
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_ATTESTATION_MISSING")
        assets = getattr(adapter, "asset_paths", {})
        files = getattr(adapter, "execution_files", {})
        if set(assets) != {"llama_cli", "model", "mmproj"} or set(files) != {"system", "input", "output"}:
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_EVIDENCE_PATHS_MISSING")

        expected_hashes = {
            "model_sha256": MODEL_SHA256, "mmproj_sha256": MMPROJ_SHA256,
            "llama_cli_sha256": attestation.get("llama_cli_sha256"),
            "system_prompt_sha256": attestation.get("system_prompt_sha256"),
            "raw_output_file_sha256": attestation.get("raw_output_file_sha256"),
        }
        observed_hashes = {
            "model_sha256": _sha256_file(assets["model"]),
            "mmproj_sha256": _sha256_file(assets["mmproj"]),
            "llama_cli_sha256": _sha256_file(assets["llama_cli"]),
            "system_prompt_sha256": _sha256_file(files["system"]),
            "raw_output_file_sha256": _sha256_file(files["output"]),
        }
        for key, expected in expected_hashes.items():
            if observed_hashes[key] != expected:
                raise RuntimeExecutionBlocked("LOCAL_VERIFIER_HASH_MISMATCH", key)
        if sha256_text(files["input"].read_text(encoding="utf-8")) != request["input_sha256"]:
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_LITERAL_INPUT_MISMATCH")
        if files["output"].read_text(encoding="utf-8").strip() != response.get("raw_output"):
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_RAW_OUTPUT_MISMATCH")
        if attestation.get("llama_source_commit") != LLAMA_SOURCE_COMMIT:
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_LLAMA_COMMIT_MISMATCH")
        if attestation.get("repository_visibility") != "public" or runner["visibility"] != "public":
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_VISIBILITY_MISMATCH")
        if attestation.get("runner_label") != "ubuntu-latest":
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_RUNNER_LABEL_MISMATCH")
        if attestation.get("github_run_id") != os.environ.get("GITHUB_RUN_ID"):
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_RUN_ID_MISMATCH")
        expected_adapter_count = str(len(request.get("lf_adapter_sources") or []))
        if attestation.get("lf_adapter_invocation_count") != expected_adapter_count:
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_LF_ADAPTER_COUNT_MISMATCH")
        if request.get("lf_adapter_source_sha256") and attestation.get("lf_adapter_source_sha256") != request["lf_adapter_source_sha256"]:
            raise RuntimeExecutionBlocked("LOCAL_VERIFIER_LF_ADAPTER_SOURCE_SHA_MISMATCH")

        schema_path = getattr(adapter, "structured_output_schema_path", None)
        schema_ref = attestation.get("structured_output_schema_ref")
        schema_sha = attestation.get("structured_output_schema_sha256")
        if schema_path is None:
            if schema_ref is not None or schema_sha is not None:
                raise RuntimeExecutionBlocked("LOCAL_VERIFIER_SCHEMA_ATTESTATION_UNEXPECTED")
        else:
            if not schema_path.is_file():
                raise RuntimeExecutionBlocked("LOCAL_VERIFIER_SCHEMA_MISSING")
            expected_ref = str(schema_path.relative_to(adapter.work_dir.resolve()))
            if schema_ref != expected_ref or schema_sha != _sha256_file(schema_path):
                raise RuntimeExecutionBlocked("LOCAL_VERIFIER_SCHEMA_ATTESTATION_MISMATCH")

        if self.expected_image_path is not None:
            if not self.expected_image_path.is_file() or _sha256_file(self.expected_image_path) != self.expected_image_sha256:
                raise RuntimeExecutionBlocked("LOCAL_VERIFIER_IMAGE_MISMATCH")
            if attestation.get("input_image_sha256") != self.expected_image_sha256:
                raise RuntimeExecutionBlocked("LOCAL_VERIFIER_IMAGE_ATTESTATION_MISMATCH")
        response_sha256 = canonical_json_sha256(response)
        evidence_sha256 = sha256_text("|".join([
            self.verifier_id, request["request_sha256"], response_sha256,
            observed_hashes["system_prompt_sha256"], observed_hashes["raw_output_file_sha256"],
        ]))
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha256,
            "evidence_sha256": evidence_sha256,
        }
