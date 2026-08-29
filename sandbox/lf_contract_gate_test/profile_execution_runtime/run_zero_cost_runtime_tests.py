#!/usr/bin/env python3
"""Offline regression for the zero-cost GitHub-hosted local profile runtime."""

from __future__ import annotations

import base64
import os
import tempfile
from pathlib import Path

import github_actions_local_runtime as local
from profile_runtime_runner import RuntimeExecutionBlocked, build_runtime_request
from run_zero_cost_profile_request import _materialize_image, _resolve_lf_adapters, _safe_source_paths
from validate_profile_execution import build_receipt, canonical_json_sha256, sha256_text, validate_receipt


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


def shell_binding(version="v0.2-candidate"):
    return [{
        "adapter_asset_code": "ADAPTER-LF-SHELL-PROFILE-20260827",
        "adapter_version": version,
        "target_asset_code": "PERFIL-UI-ARCHITECT",
    }]


def shell_resolution(decision="APPLY"):
    return [{
        "adapter_asset_code": "ADAPTER-LF-SHELL-PROFILE-20260827",
        "decision": decision,
        "activation_reason": "LF screen remediation requires Shell placement constraints",
    }]


def verified_attestation():
    return {
        "provider": "test", "model_id": "test", "run_id": "test",
        "attested_at": "2026-08-29T00:00:00Z",
        "attestation_verifier": "test-verifier",
        "attestation_evidence_sha256": "b" * 64,
        "verified_request_sha256": "c" * 64,
        "verified_response_sha256": "d" * 64,
    }


def main() -> int:
    passed = 0
    prior = set_good_env()
    repo_root = Path.cwd().resolve()
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

        base_request = {
            "profile_code": "PERFIL-UI-ARCHITECT",
            "governed_adapter_bindings": [],
            "lf_adapter_resolution": [],
        }
        resolution, contexts = _resolve_lf_adapters(base_request, repo_root=repo_root)
        assert resolution == [] and contexts == []
        passed += 1

        bound = dict(base_request)
        bound["governed_adapter_bindings"] = shell_binding()
        expect_block("QUEUE_ADAPTER_RESOLUTION_BINDING_MISMATCH",
                     lambda: _resolve_lf_adapters(bound, repo_root=repo_root))
        passed += 1

        applied = dict(bound)
        applied["lf_adapter_resolution"] = shell_resolution("APPLY")
        resolution, contexts = _resolve_lf_adapters(applied, repo_root=repo_root)
        assert len(resolution) == 1 and len(contexts) == 1
        assert contexts[0]["adapter_code"] == "ADAPTER_LF_SHELL_PROFILE"
        assert len(contexts[0]["capsule_content"]) <= 2000
        passed += 1

        skipped = dict(bound)
        skipped["lf_adapter_resolution"] = shell_resolution("SKIP")
        resolution, contexts = _resolve_lf_adapters(skipped, repo_root=repo_root)
        assert len(resolution) == 1 and contexts == []
        passed += 1

        extra = dict(base_request)
        extra["lf_adapter_resolution"] = shell_resolution("APPLY")
        expect_block("QUEUE_ADAPTER_RESOLUTION_BINDING_MISMATCH",
                     lambda: _resolve_lf_adapters(extra, repo_root=repo_root))
        passed += 1

        version_mismatch = dict(applied)
        version_mismatch["governed_adapter_bindings"] = shell_binding("v0.1")
        expect_block("QUEUE_ADAPTER_VERSION_MISMATCH",
                     lambda: _resolve_lf_adapters(version_mismatch, repo_root=repo_root))
        passed += 1

        request = build_runtime_request(
            execution_id="EXEC-ADAPTER-TEST", profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_sources=[{"ref": "profiles/ui_architect/SKILL.md", "content": "profile"}],
            input_literal="test",
            lf_adapter_resolution=shell_resolution("APPLY"),
            lf_adapter_contexts=_resolve_lf_adapters(applied, repo_root=repo_root)[1],
        )
        rendered = local._render_profile_instructions(request)
        assert "BEGIN GOVERNED LF ADAPTER CAPSULE: ADAPTER_LF_SHELL_PROFILE" in rendered
        passed += 1

        request_no_adapter = build_runtime_request(
            execution_id="EXEC-NO-ADAPTER", profile_code="UNBOUND-PROFILE",
            profile_slug="ui_architect",
            profile_sources=[{"ref": "profiles/ui_architect/SKILL.md", "content": "profile"}],
            input_literal="test",
        )
        assert "BEGIN GOVERNED LF ADAPTER CAPSULE" not in local._render_profile_instructions(request_no_adapter)
        passed += 1

        receipt = build_receipt(
            execution_id="EXEC-RECEIPT", profile_code="PERFIL-UI-ARCHITECT", profile_slug="ui_architect",
            profile_source_refs=["profiles/ui_architect/SKILL.md"], profile_source_sha256="a" * 64,
            input_literal="test", raw_output={"ok": True}, runtime_attestation=verified_attestation(),
            lf_adapter_resolution=shell_resolution("APPLY"), lf_adapter_invocations=[],
        )
        assert "LF_ADAPTER_INVOCATION_CARDINALITY_MISMATCH" in validate_receipt(receipt)
        passed += 1

        provider_only = build_receipt(
            execution_id="EXEC-PROVIDER-ONLY", profile_code="PERFIL-UI-ARCHITECT", profile_slug="ui_architect",
            profile_source_refs=["profiles/ui_architect/SKILL.md"], profile_source_sha256="a" * 64,
            input_literal="test", raw_output={"ok": True}, runtime_attestation=verified_attestation(),
            lf_adapter_resolution=shell_resolution("APPLY"), lf_adapter_invocations=[],
        )
        provider_only["runtime_attestation"]["adapter_id"] = "github-standard-llamacpp-qwen25vl-v1"
        provider_only["receipt_sha256"] = canonical_json_sha256({k: v for k, v in provider_only.items() if k != "receipt_sha256"})
        assert "LF_ADAPTER_INVOCATION_CARDINALITY_MISMATCH" in validate_receipt(provider_only)
        passed += 1
    finally:
        restore_env(prior)
    if passed != 20:
        raise SystemExit(f"ZERO_COST_PROFILE_RUNTIME_TESTS_FAIL {passed}/20")
    print("ZERO_COST_PROFILE_RUNTIME_TESTS_PASS 20/20")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
