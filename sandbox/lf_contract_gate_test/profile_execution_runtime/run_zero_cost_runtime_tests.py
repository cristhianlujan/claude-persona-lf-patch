#!/usr/bin/env python3
"""Offline regression for the zero-cost GitHub-hosted local profile runtime."""

from __future__ import annotations

import base64
import os
import tempfile
from pathlib import Path

import github_actions_local_runtime as local
from github_actions_queue_worker import (
    _assistant_completion,
    _enforce_nonempty_completion,
    _enforce_profile_output_contract,
)
from profile_runtime_runner import RuntimeExecutionBlocked
from run_zero_cost_profile_request import _materialize_image, _materialize_runtime_output_schema, _safe_source_paths


def expect_block(code: str, fn) -> None:
    try:
        fn()
    except RuntimeExecutionBlocked as exc:
        if exc.code != code:
            raise AssertionError(f"expected {code}, got {exc.code}") from exc
    else:
        raise AssertionError(f"expected block {code}")


def set_good_env() -> dict[str, str | None]:
    keys = {
        "GITHUB_ACTIONS": "true", "RUNNER_OS": "Linux", "RUNNER_ARCH": "X64",
        "GITHUB_REPOSITORY": local.TARGET_REPOSITORY, "LF_REPOSITORY_VISIBILITY": "public",
        "LF_RUNNER_LABEL": "ubuntu-latest", "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1",
        "GITHUB_SHA": "a" * 40, "LF_LLAMA_SOURCE_COMMIT": local.LLAMA_SOURCE_COMMIT,
    }
    prior = {key: os.environ.get(key) for key in keys}
    os.environ.update(keys)
    return prior


def restore_env(prior: dict[str, str | None]) -> None:
    for key, value in prior.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


def quality_pack_result(completion: str) -> dict:
    return {
        "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
        "status": "SUCCEEDED",
        "raw_output": f"User:\nnegative\n\nAssistant:\n{completion}",
        "package": {"request": {"profile_code": "PERFIL-QUALITY-PACK"}},
    }


def main() -> int:
    passed = 0
    prior = set_good_env()
    try:
        assert local._require_zero_cost_runner()["visibility"] == "public"
        passed += 1
        os.environ["LF_REPOSITORY_VISIBILITY"] = "private"
        expect_block("ZERO_COST_GITHUB_RUNNER_PRECONDITION_FAILED", local._require_zero_cost_runner)
        os.environ["LF_REPOSITORY_VISIBILITY"] = "public"
        passed += 1
        os.environ["LF_RUNNER_LABEL"] = "ubuntu-latest-8-cores"
        expect_block("ZERO_COST_GITHUB_RUNNER_PRECONDITION_FAILED", local._require_zero_cost_runner)
        os.environ["LF_RUNNER_LABEL"] = "ubuntu-latest"
        passed += 1
        assert _safe_source_paths("ui_architect", [
            "profiles/ui_architect/SKILL.md", "profiles/ui_architect/contracts/task_contract.md"
        ]) == ["profiles/ui_architect/SKILL.md", "profiles/ui_architect/contracts/task_contract.md"]
        passed += 1
        expect_block("QUEUE_SOURCE_PATH_OUT_OF_SCOPE",
                     lambda: _safe_source_paths("ui_architect", ["profiles/other/SKILL.md"]))
        passed += 1
        expect_block("QUEUE_SOURCE_PATH_OUT_OF_SCOPE",
                     lambda: _safe_source_paths("ui_architect", ["profiles/ui_architect/../other/SKILL.md"]))
        passed += 1
        raw = b"fake-image-bytes"
        sha = local._sha256_bytes(raw)
        with tempfile.TemporaryDirectory() as td:
            image, observed_sha = _materialize_image({
                "input_image_base64": base64.b64encode(raw).decode("ascii"),
                "input_image_media_type": "image/png", "input_image_sha256": sha,
            }, Path(td))
            assert image is not None and image.read_bytes() == raw and observed_sha == sha
        passed += 1
        with tempfile.TemporaryDirectory() as td:
            expect_block("QUEUE_IMAGE_SHA256_MISMATCH", lambda: _materialize_image({
                "input_image_base64": base64.b64encode(raw).decode("ascii"),
                "input_image_media_type": "image/png", "input_image_sha256": "0" * 64,
            }, Path(td)))
        passed += 1
        assert local.LLAMA_SOURCE_COMMIT == "925e1179947ea0c0ebfb0032df18af3a729822be"
        assert local.MODEL_SHA256 == "d02fe9b69ad8cadbbd228e387667af66612c44bed29ffc8eb1e7caf9ac486c12"
        assert local.MMPROJ_SHA256 == "980c9b2f78c04e6cff93d277ada09e768394f112d75db3b4e9dea8a69f9fb904"
        passed += 1
        assert local.MODEL_COMMIT == "5037fcf163dd95d1e41d1974465f0898ed108ca2"
        assert local.LLAMA_RELEASE == "b10642"
        passed += 1
        runtime_source = Path(local.__file__).read_text(encoding="utf-8")
        assert '"--log-disable"' not in runtime_source
        assert '"--prompt", request["input_literal"]' in runtime_source
        assert '"-f", str(input_file)' not in runtime_source
        assert "context_tokens: int = 16384" in runtime_source
        assert "max_output_tokens: int = 2048" in runtime_source
        assert '"context_tokens": str(self.context_tokens)' in runtime_source
        assert '"max_output_tokens": str(self.max_output_tokens)' in runtime_source
        passed += 1
        with tempfile.TemporaryDirectory() as td:
            copied = _materialize_runtime_output_schema("ui_architect", Path.cwd(), Path(td))
            assert copied is None
        passed += 1
        assert _assistant_completion("User:\nrequest\n\nAssistant:\n{\"ok\":true}") == '{"ok":true}'
        empty = _enforce_nonempty_completion({
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "SUCCEEDED",
            "raw_output": "User:\nrequest\n\nAssistant:",
        })
        assert empty["status"] == "BLOCKED"
        assert empty["error_code"] == "LOCAL_RUNTIME_ASSISTANT_COMPLETION_EMPTY"
        passed += 1

        bare_pass = _enforce_profile_output_contract(quality_pack_result("PASS_TO_COMPOSER"))
        assert bare_pass["status"] == "BLOCKED"
        assert bare_pass["error_code"] == "QUALITY_PACK_OUTPUT_NOT_JSON"
        passed += 1

        valid_return = {
            "review_id": "QP-NEG-001",
            "reviewed_artifact": "B2B-CARGA-001",
            "verdict": "RETURN_TO_ORCHESTRATOR",
            "score_breakdown": {
                "contract_schema_compliance": 5,
                "evidence_integrity": 0,
                "lf_safety_governance": 5,
                "handoff_readiness": 0,
                "leakage_scope_control": 5,
                "total": 15,
            },
            "evidence_map": [],
            "blocking_codes": ["VISUAL_BYTES_NOT_OBSERVED"],
            "repair_actions": [],
            "remaining_risks": ["visual evidence missing"],
            "next_gate": "AUTHORITY_OR_CONTEXT_RESOLUTION",
            "routing": {
                "activation_path": "ROUTER",
                "via": "ORCHESTRATOR",
                "pipeline_action": "RETURN_TO_ORCHESTRATOR",
                "resolution_target": "AUTHORITY_OR_CONTEXT_RESOLUTION",
            },
        }
        import json
        accepted = _enforce_profile_output_contract(quality_pack_result(json.dumps(valid_return)))
        assert accepted["status"] == "SUCCEEDED"
        assert accepted["normalized_profile_output"]["verdict"] == "RETURN_TO_ORCHESTRATOR"
        passed += 1

        invalid_pass = dict(valid_return)
        invalid_pass["verdict"] = "PASS_TO_COMPOSER"
        invalid_pass["routing"] = {
            "activation_path": "ROUTER",
            "via": "ORCHESTRATOR",
            "pipeline_action": "CONTINUE",
            "resolution_target": "COMPOSER",
        }
        invalid_pass["blocking_codes"] = []
        blocked = _enforce_profile_output_contract(quality_pack_result(json.dumps(invalid_pass)))
        assert blocked["status"] == "BLOCKED"
        assert blocked["error_code"] == "QUALITY_PACK_OUTPUT_CONTRACT_INVALID"
        assert "PASS_EVIDENCE_MAP_EMPTY" in blocked["error_detail"]
        passed += 1

        contradictory_pass = dict(invalid_pass)
        contradictory_pass["evidence_map"] = [{"evidence_type": "SHA-256", "evidence_value": "a" * 64}]
        contradictory_pass["blocking_codes"] = ["BLOCK_PIPELINE"]
        contradictory_pass["repair_actions"] = []
        blocked = _enforce_profile_output_contract(quality_pack_result(json.dumps(contradictory_pass)))
        assert blocked["status"] == "BLOCKED"
        assert "PASS_BLOCKING_CODES_NONEMPTY" in blocked["error_detail"]
        passed += 1

        pass_with_repair = dict(contradictory_pass)
        pass_with_repair["blocking_codes"] = []
        pass_with_repair["repair_actions"] = [{"required_fix": "repair before continuation"}]
        blocked = _enforce_profile_output_contract(quality_pack_result(json.dumps(pass_with_repair)))
        assert blocked["status"] == "BLOCKED"
        assert "PASS_TO_COMPOSER_REPAIR_ACTIONS_NONEMPTY" in blocked["error_detail"]
        passed += 1

        nonpass_without_blocker = dict(valid_return)
        nonpass_without_blocker["blocking_codes"] = []
        blocked = _enforce_profile_output_contract(quality_pack_result(json.dumps(nonpass_without_blocker)))
        assert blocked["status"] == "BLOCKED"
        assert "NONPASS_BLOCKING_CODES_EMPTY" in blocked["error_detail"]
        passed += 1
    finally:
        restore_env(prior)
    if passed != 19:
        raise SystemExit(f"ZERO_COST_PROFILE_RUNTIME_TESTS_FAIL {passed}/19")
    print("ZERO_COST_PROFILE_RUNTIME_TESTS_PASS 19/19")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
