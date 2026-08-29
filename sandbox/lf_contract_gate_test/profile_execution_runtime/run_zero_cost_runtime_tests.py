#!/usr/bin/env python3
"""Offline regression for the zero-cost GitHub-hosted local profile runtime."""

from __future__ import annotations

import base64
import os
import tempfile
from pathlib import Path

import github_actions_local_runtime as local
from github_actions_queue_worker import _assistant_completion, _enforce_nonempty_completion
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
        assert "context_tokens: int = 16384" in runtime_source
        assert "max_output_tokens: int = 2048" in runtime_source
        assert '"context_tokens": str(self.context_tokens)' in runtime_source
        assert '"max_output_tokens": str(self.max_output_tokens)' in runtime_source
        passed += 1
        with tempfile.TemporaryDirectory() as td:
            copied = _materialize_runtime_output_schema("ui_architect", Path.cwd(), Path(td))
            canonical = Path("profiles/ui_architect/schemas/runtime_output.schema.json")
            assert copied is not None and copied.read_bytes() == canonical.read_bytes()
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
    finally:
        restore_env(prior)
    if passed != 13:
        raise SystemExit(f"ZERO_COST_PROFILE_RUNTIME_TESTS_FAIL {passed}/13")
    print("ZERO_COST_PROFILE_RUNTIME_TESTS_PASS 13/13")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
