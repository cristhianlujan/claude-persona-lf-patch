#!/usr/bin/env python3
"""S26 zero-download semantic mini-judge over Cloudflare Workers AI Nemotron."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from profile_runtime_runner import RuntimeExecutionBlocked
from semantic_mini_judge import CheckResult, compact_semantic_payload
from validate_profile_execution import canonical_json_sha256

ADAPTER_ID = "cloudflare-workers-ai-nemotron3-120b-semantic-minijudge-v1"
VERIFIER_ID = "cloudflare-workers-ai-nemotron3-120b-semantic-minijudge-readback-v1"
SEMANTIC_MODEL_ID = "@cf/nvidia/nemotron-3-120b-a12b"
SEMANTIC_MODEL_PROVIDER = "cloudflare_workers_ai"
SEMANTIC_MODEL_BINDING_SHA256 = "345f068350a56ea809ea7de5e7a711a8f06dc0af881d555a50b42ccb9419ab39"
# Compatibility alias for older S26 runners; this is a provider/model binding digest, not a local weight digest.
SEMANTIC_MODEL_SHA256 = SEMANTIC_MODEL_BINDING_SHA256
SEMANTIC_MODEL_CALIBRATION_SHA256 = "ce96a3594aaba21629cdc54ac248dcf019068a52b095ffcef80d9b71379af5cf"
SEMANTIC_MODEL_CALIBRATION_ARTIFACT_DIGEST = "sha256:ee0a74a18406c323a5428700e8d7810038ff554a07898da11b112e8e6aea8621"
SEMANTIC_AUTHORITY_DECISION_REF = "S26-REMOTE-JUDGE-CHALLENGER-20260908"
PRIMARY_MODEL_ID = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
MAX_OUTPUT_TOKENS = 256
SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "verdict": {"type": "string", "enum": ["COMPLIES", "CONTRADICTS", "UNCERTAIN"]},
        "reason_code": {"type": "string", "minLength": 2, "maxLength": 80},
    },
    "required": ["verdict", "reason_code"],
}
SYSTEM_TEXT = """You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE directly establishes compliance with RULE.
Do not rewrite, repair, propose, or expand the evidence.
Do not infer missing implementation facts from plausibility or adjectives.
Return COMPLIES only when evidence directly establishes the rule.
Return CONTRADICTS only when evidence explicitly violates the rule.
Return UNCERTAIN when evidence does not establish either.
Return exactly the constrained JSON object and nothing else.
"""


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _parse_value(value: Any) -> tuple[dict[str, str], str, str, bool]:
    if isinstance(value, dict) and value:
        parsed = value
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True)
        shape = "object:" + ",".join(sorted(str(key) for key in value))
        fenced = False
    elif isinstance(value, str) and value.strip():
        raw = value.strip()
        shape = f"string:{len(raw)}"
        fenced = raw.startswith("```")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_OUTPUT_NOT_JSON") from exc
    else:
        raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_OUTPUT_EMPTY")
    if not isinstance(parsed, dict) or set(parsed) != {"verdict", "reason_code"}:
        raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_RESPONSE_SHAPE_INVALID", shape)
    verdict = parsed.get("verdict")
    reason = parsed.get("reason_code")
    if verdict not in {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}:
        raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_VERDICT_INVALID")
    if not isinstance(reason, str) or not 2 <= len(reason.strip()) <= 80:
        raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_REASON_CODE_INVALID")
    return {"verdict": str(verdict), "reason_code": reason.strip()}, raw, shape, fenced


def _extract_result(envelope: dict[str, Any]) -> tuple[dict[str, str], str, str, bool, dict[str, Any]]:
    if envelope.get("success") is True and isinstance(envelope.get("result"), dict):
        result = envelope["result"]
    else:
        result = envelope
    if not isinstance(result, dict):
        raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CLOUDFLARE_RESULT_INVALID")
    if "response" in result:
        parsed, raw, shape, fenced = _parse_value(result.get("response"))
    else:
        choices = result.get("choices")
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CHAT_CHOICES_MISSING")
        message = choices[0].get("message")
        if not isinstance(message, dict):
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CHAT_MESSAGE_MISSING")
        parsed, raw, inner_shape, fenced = _parse_value(message.get("content"))
        shape = "chat_content:" + inner_shape
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    return parsed, raw, shape, fenced, usage


class GitHubHostedSemanticMiniJudge:
    """Compatibility interface backed by the owner-approved remote Nemotron authority."""

    adapter_id = ADAPTER_ID
    is_test_double = False

    def __init__(
        self,
        *,
        work_dir: Path,
        timeout_seconds: int = 120,
        max_output_tokens: int = MAX_OUTPUT_TOKENS,
        context_tokens: int = 0,
        port: int = 0,
    ) -> None:
        self.work_dir = work_dir
        self.timeout_seconds = timeout_seconds
        self.max_output_tokens = max_output_tokens
        self.context_tokens = context_tokens
        self.port = port
        self.execution_files: dict[str, Path] = {}
        self.account = ""
        self.token = ""

    def __enter__(self) -> "GitHubHostedSemanticMiniJudge":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def start(self) -> None:
        self.account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
        self.token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
        if not self.account or not self.token:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CLOUDFLARE_SECRET_MISSING")
        self.work_dir.mkdir(parents=True, exist_ok=True)

    def close(self) -> None:
        self.token = ""

    def _chat_completion(self, payload: dict[str, str]) -> tuple[str, str, bool, dict[str, Any], float]:
        if not self.account or not self.token:
            self.start()
        request_payload = {
            "messages": [
                {"role": "system", "content": SYSTEM_TEXT},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False, sort_keys=True)},
            ],
            "response_format": {"type": "json_schema", "json_schema": SCHEMA},
            "stream": False,
            "temperature": 0,
            "top_p": 1,
            "seed": 42,
            "max_completion_tokens": self.max_output_tokens,
        }
        request = urllib.request.Request(
            f"https://api.cloudflare.com/client/v4/accounts/{self.account}/ai/run/{SEMANTIC_MODEL_ID}",
            data=json.dumps(request_payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method="POST",
        )
        started = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                envelope = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[-600:].replace("\n", " ")
            if exc.code in {403, 429}:
                raise RuntimeExecutionBlocked(
                    "SEMANTIC_JUDGE_ZERO_COST_LIMIT_FAIL_CLOSED",
                    f"status={exc.code} body={detail}",
                ) from exc
            raise RuntimeExecutionBlocked(
                "SEMANTIC_JUDGE_CLOUDFLARE_HTTP_ERROR",
                f"status={exc.code} body={detail}",
            ) from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise RuntimeExecutionBlocked(
                "SEMANTIC_JUDGE_CLOUDFLARE_TRANSPORT_FAILURE",
                type(exc).__name__,
            ) from exc
        elapsed = round(time.monotonic() - started, 3)
        if not isinstance(envelope, dict):
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CLOUDFLARE_ENVELOPE_INVALID")
        parsed, raw, shape, fenced, usage = _extract_result(envelope)
        if fenced:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_FENCED_OUTPUT_FORBIDDEN")
        return raw, shape, fenced, usage, elapsed

    def classify(self, check: dict[str, Any]) -> tuple[CheckResult, dict[str, Any]]:
        self.start()
        payload = compact_semantic_payload(check)
        run_dir = Path(tempfile.mkdtemp(prefix="lf-semantic-judge-", dir=self.work_dir))
        system_file = run_dir / "system.txt"
        input_file = run_dir / "check.json"
        output_file = run_dir / "raw-output.txt"
        system_file.write_text(SYSTEM_TEXT, encoding="utf-8")
        input_file.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        raw_text, response_shape, _, usage, elapsed_s = self._chat_completion(payload)
        output_file.write_text(raw_text, encoding="utf-8")
        parsed, _, _, _ = _parse_value(raw_text)
        result = CheckResult(
            check_id=str(check["check_id"]),
            verdict=parsed["verdict"],
            reason_code=parsed["reason_code"],
            decided_by="REMOTE_SEMANTIC_MODEL",
        )
        self.execution_files = {"system": system_file, "input": input_file, "output": output_file}
        evidence = {
            "adapter_id": self.adapter_id,
            "provider": SEMANTIC_MODEL_PROVIDER,
            "transport": "CLOUDFLARE_WORKERS_AI_REST",
            "model_id": SEMANTIC_MODEL_ID,
            "model_binding_sha256": SEMANTIC_MODEL_BINDING_SHA256,
            "calibration_sha256": SEMANTIC_MODEL_CALIBRATION_SHA256,
            "calibration_artifact_digest": SEMANTIC_MODEL_CALIBRATION_ARTIFACT_DIGEST,
            "authority_decision_ref": SEMANTIC_AUTHORITY_DECISION_REF,
            "authority_status": "ACTIVE_SANDBOX_SEMANTIC_AUTHORITY",
            "primary_model_id": PRIMARY_MODEL_ID,
            "provider_infrastructure_shared_with_primary": True,
            "shared_provider_owner_approved": True,
            "provider_managed_model_weights": True,
            "model_weights_downloaded": False,
            "local_model_fallback_used": False,
            "paid_fallback_used": False,
            "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
            "limit_behavior": "FAIL_CLOSED",
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "runner_label": os.environ.get("LF_RUNNER_LABEL", ""),
            "repository_visibility": os.environ.get("LF_REPOSITORY_VISIBILITY", ""),
            "system_prompt_sha256": _sha256_file(system_file),
            "check_input_sha256": _sha256_file(input_file),
            "raw_output_sha256": _sha256_file(output_file),
            "provider_response_shape": response_shape,
            "elapsed_s": elapsed_s,
            "usage": {
                str(key): value
                for key, value in usage.items()
                if isinstance(value, (int, float, bool)) or value is None
            },
            "classification": result.as_dict(),
        }
        return result, evidence


class GitHubHostedSemanticMiniJudgeVerifier:
    verifier_id = VERIFIER_ID
    is_test_double = False

    def verify(
        self,
        *,
        check: dict[str, Any],
        result: CheckResult,
        evidence: dict[str, Any],
        adapter: GitHubHostedSemanticMiniJudge,
    ) -> dict[str, Any]:
        if adapter.adapter_id != ADAPTER_ID:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_ADAPTER_MISMATCH")
        files = adapter.execution_files
        if set(files) != {"system", "input", "output"}:
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_EVIDENCE_PATHS_MISSING")
        observed = {
            "system_prompt_sha256": _sha256_file(files["system"]),
            "check_input_sha256": _sha256_file(files["input"]),
            "raw_output_sha256": _sha256_file(files["output"]),
        }
        for key, value in observed.items():
            if evidence.get(key) != value:
                raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_VERIFIER_HASH_MISMATCH", key)
        expected_pairs = {
            "provider": SEMANTIC_MODEL_PROVIDER,
            "transport": "CLOUDFLARE_WORKERS_AI_REST",
            "model_id": SEMANTIC_MODEL_ID,
            "model_binding_sha256": SEMANTIC_MODEL_BINDING_SHA256,
            "calibration_sha256": SEMANTIC_MODEL_CALIBRATION_SHA256,
            "authority_decision_ref": SEMANTIC_AUTHORITY_DECISION_REF,
            "authority_status": "ACTIVE_SANDBOX_SEMANTIC_AUTHORITY",
            "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
            "limit_behavior": "FAIL_CLOSED",
        }
        for key, value in expected_pairs.items():
            if evidence.get(key) != value:
                raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_AUTHORITY_BINDING_MISMATCH", key)
        for key in (
            "provider_infrastructure_shared_with_primary",
            "shared_provider_owner_approved",
            "provider_managed_model_weights",
        ):
            if evidence.get(key) is not True:
                raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_REQUIRED_TRUE_FLAG_MISSING", key)
        for key in (
            "model_weights_downloaded",
            "local_model_fallback_used",
            "paid_fallback_used",
        ):
            if evidence.get(key) is not False:
                raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_ZERO_DOWNLOAD_GUARD_MISMATCH", key)
        if evidence.get("classification") != result.as_dict():
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_CLASSIFICATION_MISMATCH")
        if evidence.get("repository_visibility") != "public":
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_VISIBILITY_MISMATCH")
        if evidence.get("runner_label") != "ubuntu-latest":
            raise RuntimeExecutionBlocked("SEMANTIC_JUDGE_RUNNER_MISMATCH")
        verification_payload = {
            "verifier_id": self.verifier_id,
            "check_id": check["check_id"],
            "classification": result.as_dict(),
            "observed_hashes": observed,
            "model_id": SEMANTIC_MODEL_ID,
            "model_binding_sha256": SEMANTIC_MODEL_BINDING_SHA256,
            "calibration_sha256": SEMANTIC_MODEL_CALIBRATION_SHA256,
            "authority_decision_ref": SEMANTIC_AUTHORITY_DECISION_REF,
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_sha": os.environ.get("GITHUB_SHA", ""),
            "transport": "CLOUDFLARE_WORKERS_AI_REST",
            "shared_provider_owner_approved": True,
        }
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "evidence_sha256": canonical_json_sha256(verification_payload),
        }
