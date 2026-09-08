#!/usr/bin/env python3
"""S26 canonical v3 challenger-only gate using Llama 4 Scout as semantic judge.

This wrapper reuses the canonical S26 direct/Router/manifest/receipt path while
keeping the configured semantic authority route unchanged. The base canonical
gate therefore remains fail-closed on route parity; this wrapper separately
reports challenger compatibility and never authorizes promotion or production.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

import run_s26_canonical_profile_gate as canonical
from run_s26_cloudflare_judge_challenger_calibration import SYSTEM_TEXT, call_cloudflare
from semantic_mini_judge import CheckResult, compact_semantic_payload

CHALLENGER_MODEL = "@cf/meta/llama-4-scout-17b-16e-instruct"
CHALLENGER_PROTOCOL = "OPENAI_CHAT_COMPLETIONS"
CHALLENGER_CALIBRATION_SHA256 = "d344dde550748ec383cce9ad6394bf9bbb296344c827cde3e35e29f3885790fc"
CHALLENGER_CALIBRATION_ARTIFACT_DIGEST = "sha256:bfea4619d2711412c42dab0860ee7c97a30495489246788b81295b40ac461276"
CHALLENGER_CALIBRATION_RUN_ID = "34187027614"
CHALLENGER_CALIBRATION_ARTIFACT_ID = "10040854675"
OFFICIAL_SEMANTIC_MODEL = canonical.SEMANTIC_MODEL_ID
PLAN_PATH = canonical.RUNTIME_DIR / "s26_canonical_profile_gate_plan_v3.json"
MAX_OUTPUT_TOKENS = 512


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class Llama4ScoutSemanticJudge:
    adapter_id = "cloudflare-workers-ai-llama4-scout-semantic-challenger-v1"
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
        self.account = ""
        self.token = ""
        self.execution_files: dict[str, Path] = {}

    def __enter__(self) -> "Llama4ScoutSemanticJudge":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def start(self) -> None:
        self.account = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
        self.token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
        if not self.account or not self.token:
            raise RuntimeError("S26_CHALLENGER_CLOUDFLARE_SECRET_MISSING")
        self.work_dir.mkdir(parents=True, exist_ok=True)

    def close(self) -> None:
        self.token = ""

    def classify(self, check: dict[str, Any]) -> tuple[CheckResult, dict[str, Any]]:
        if not self.account or not self.token:
            self.start()
        payload = compact_semantic_payload(check)
        case = {
            "rule": payload["rule"],
            "evidence": payload["evidence"],
            "question": payload["question"],
        }
        parsed, raw, usage, elapsed = call_cloudflare(
            self.account,
            self.token,
            case,
            model=CHALLENGER_MODEL,
            protocol=CHALLENGER_PROTOCOL,
            max_tokens=self.max_output_tokens,
        )
        run_dir = Path(tempfile.mkdtemp(prefix="lf-s26-llama4-challenger-", dir=self.work_dir))
        system_file = run_dir / "system.txt"
        input_file = run_dir / "check.json"
        output_file = run_dir / "raw-output.txt"
        system_file.write_text(SYSTEM_TEXT, encoding="utf-8")
        input_file.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        output_file.write_text(raw, encoding="utf-8")
        self.execution_files = {"system": system_file, "input": input_file, "output": output_file}
        result = CheckResult(
            check_id=str(check["check_id"]),
            verdict=parsed["verdict"],
            reason_code=parsed["reason_code"],
            decided_by="REMOTE_SEMANTIC_MODEL_CHALLENGER",
        )
        evidence = {
            "adapter_id": self.adapter_id,
            "provider": "cloudflare_workers_ai",
            "transport": CHALLENGER_PROTOCOL,
            "model_id": CHALLENGER_MODEL,
            "authority_status": "QUALIFIED_REMOTE_JUDGE_CHALLENGER",
            "challenger_only": True,
            "canonical_authority_changed": False,
            "official_semantic_model": OFFICIAL_SEMANTIC_MODEL,
            "calibration_sha256": CHALLENGER_CALIBRATION_SHA256,
            "calibration_artifact_digest": CHALLENGER_CALIBRATION_ARTIFACT_DIGEST,
            "calibration_run_id": CHALLENGER_CALIBRATION_RUN_ID,
            "calibration_artifact_id": CHALLENGER_CALIBRATION_ARTIFACT_ID,
            "provider_infrastructure_shared_with_primary": True,
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
            "elapsed_s": elapsed,
            "usage": {
                str(key): value
                for key, value in usage.items()
                if isinstance(value, (int, float, bool)) or value is None
            },
            "classification": result.as_dict(),
        }
        return result, evidence


class Llama4ScoutSemanticJudgeVerifier:
    verifier_id = "cloudflare-workers-ai-llama4-scout-semantic-challenger-readback-v1"
    is_test_double = False

    def verify(
        self,
        *,
        check: dict[str, Any],
        result: CheckResult,
        evidence: dict[str, Any],
        adapter: Llama4ScoutSemanticJudge,
    ) -> dict[str, Any]:
        if adapter.adapter_id != Llama4ScoutSemanticJudge.adapter_id:
            raise RuntimeError("S26_CHALLENGER_ADAPTER_MISMATCH")
        files = adapter.execution_files
        if set(files) != {"system", "input", "output"}:
            raise RuntimeError("S26_CHALLENGER_EVIDENCE_PATHS_MISSING")
        observed = {
            "system_prompt_sha256": _sha256_file(files["system"]),
            "check_input_sha256": _sha256_file(files["input"]),
            "raw_output_sha256": _sha256_file(files["output"]),
        }
        for key, value in observed.items():
            if evidence.get(key) != value:
                raise RuntimeError("S26_CHALLENGER_HASH_MISMATCH:" + key)
        expected = {
            "provider": "cloudflare_workers_ai",
            "transport": CHALLENGER_PROTOCOL,
            "model_id": CHALLENGER_MODEL,
            "authority_status": "QUALIFIED_REMOTE_JUDGE_CHALLENGER",
            "calibration_sha256": CHALLENGER_CALIBRATION_SHA256,
            "calibration_artifact_digest": CHALLENGER_CALIBRATION_ARTIFACT_DIGEST,
            "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
            "limit_behavior": "FAIL_CLOSED",
        }
        for key, value in expected.items():
            if evidence.get(key) != value:
                raise RuntimeError("S26_CHALLENGER_BINDING_MISMATCH:" + key)
        for key in ("challenger_only", "provider_infrastructure_shared_with_primary", "provider_managed_model_weights"):
            if evidence.get(key) is not True:
                raise RuntimeError("S26_CHALLENGER_REQUIRED_TRUE_MISSING:" + key)
        for key in ("canonical_authority_changed", "model_weights_downloaded", "local_model_fallback_used", "paid_fallback_used"):
            if evidence.get(key) is not False:
                raise RuntimeError("S26_CHALLENGER_REQUIRED_FALSE_MISMATCH:" + key)
        if evidence.get("classification") != result.as_dict():
            raise RuntimeError("S26_CHALLENGER_CLASSIFICATION_MISMATCH")
        if evidence.get("repository_visibility") != "public" or evidence.get("runner_label") != "ubuntu-latest":
            raise RuntimeError("S26_CHALLENGER_RUNNER_CONTEXT_MISMATCH")
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "check_id": check["check_id"],
            "classification": result.as_dict(),
            "observed_hashes": observed,
            "model_id": CHALLENGER_MODEL,
            "challenger_only": True,
            "canonical_authority_changed": False,
        }


def _install_challenger_mode() -> None:
    original_validate_route = canonical._validate_route

    def validate_official_route_unchanged(route: dict[str, Any]) -> None:
        challenger_value = canonical.SEMANTIC_MODEL_ID
        try:
            canonical.SEMANTIC_MODEL_ID = OFFICIAL_SEMANTIC_MODEL
            original_validate_route(route)
        finally:
            canonical.SEMANTIC_MODEL_ID = challenger_value

    canonical.PLAN_PATH = PLAN_PATH
    canonical.GitHubHostedSemanticMiniJudge = Llama4ScoutSemanticJudge
    canonical.GitHubHostedSemanticMiniJudgeVerifier = Llama4ScoutSemanticJudgeVerifier
    canonical._validate_route = validate_official_route_unchanged
    canonical.SEMANTIC_MODEL_ID = CHALLENGER_MODEL


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, required=True)
    args = parser.parse_args()
    _install_challenger_mode()
    try:
        base_payload = canonical.live_gate(args.result_dir)
        parity = dict(base_payload.get("parity_checks") or {})
        route_mismatch_expected = parity.get("route_semantic_model_matches") is False
        challenger_checks = {key: value for key, value in parity.items() if key != "route_semantic_model_matches"}
        challenger_compatibility = (
            route_mismatch_expected
            and bool(challenger_checks)
            and all(challenger_checks.values())
            and base_payload.get("semantic_verdict") == "PASS"
            and base_payload.get("semantic_checks_total") == 12
            and base_payload.get("semantic_checks_comply") == 12
            and (base_payload.get("downstream_validation") or {}).get("status") == "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY"
        )
        final_payload = dict(base_payload)
        final_payload.update({
            "schema": "S26_CANONICAL_PROFILE_GATE_CHALLENGER_RESULT_V1",
            "status": "PASS_SANDBOX_CANONICAL_CHALLENGER_ONLY" if challenger_compatibility else "FAIL_CLOSED",
            "scope": "SANDBOX_CHALLENGER_ONLY_NOT_AUTHORITY_NOT_GOLDEN_NOT_PRODUCTION",
            "plan_revision": "v3",
            "challenger_model": CHALLENGER_MODEL,
            "official_route_semantic_model": OFFICIAL_SEMANTIC_MODEL,
            "official_route_unchanged": route_mismatch_expected,
            "challenger_compatibility_parity": challenger_compatibility,
            "canonical_authority_changed": False,
            "authority_promotion_authorized": False,
            "golden_promotion_authorized": False,
            "production_mutation": False,
            "promotion_authorized": False,
        })
        _write_json(args.result_dir / "result.json", final_payload)
        print("S26_CANONICAL_V3_CHALLENGER=" + json.dumps(final_payload, ensure_ascii=False, sort_keys=True))
        print("S26_CANONICAL_V3_CHALLENGER_STATUS=" + final_payload["status"])
        return 0 if challenger_compatibility else 2
    except Exception as exc:
        failure = {
            "schema": "S26_CANONICAL_PROFILE_GATE_CHALLENGER_RESULT_V1",
            "strategy": "S26",
            "status": "FAIL_CLOSED",
            "error_type": type(exc).__name__,
            "error": str(exc)[:1600],
            "challenger_model": CHALLENGER_MODEL,
            "official_route_semantic_model": OFFICIAL_SEMANTIC_MODEL,
            "canonical_authority_changed": False,
            "authority_promotion_authorized": False,
            "golden_promotion_authorized": False,
            "production_mutation": False,
            "promotion_authorized": False,
        }
        _write_json(args.result_dir / "result.json", failure)
        print("S26_CANONICAL_V3_CHALLENGER=" + json.dumps(failure, ensure_ascii=False, sort_keys=True))
        print("S26_CANONICAL_V3_CHALLENGER_STATUS=FAIL_CLOSED")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
