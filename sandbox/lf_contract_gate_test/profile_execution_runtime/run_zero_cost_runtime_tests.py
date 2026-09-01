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
    _prepare_governed_payload,
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


def _governance_dispatch() -> dict:
    return {
        "applicable": True,
        "status": "INPUT_GOVERNANCE_REQUIRED",
        "blocking_code": "BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED",
        "decision": "PENDING",
        "continuation_allowed": False,
        "pantalla_id": 2,
        "screen_code": "ONB_002",
        "required_by_adapters": ["ADAPTER_LF_SHELL_PROFILE"],
        "dispatch": {
            "runtime_orchestrator": "SUPABASE_EDGE_FUNCTION:input-governance-agent-v1",
            "consumer": "STORY_CREATOR",
        },
    }


def _governance_pass() -> dict:
    receipt = {
        "governance_agent_used": True,
        "governance_agent": "input-governance-agent-v1",
        "governance_version": "5.12",
        "sections_consumed": ["APPLICABILITY_READINESS"],
        "source_refs": ["programacion.input_readiness_runs/9001"],
        "snapshot_hash": "a" * 64,
        "contract_snapshot_hash": "b" * 64,
        "decision": "PASS",
        "gap_or_na": "NONE",
        "timestamp": "2026-08-31T23:50:00Z",
        "run_id": 9001,
        "pantalla_id": 2,
        "screen_code": "ONB_002",
        "run_created_at": "2026-08-31T23:49:00Z",
        "agent_output_sha256": "c" * 64,
        "currentness": "LIVE_CURRENT",
    }
    return {
        "applicable": True,
        "status": "READY",
        "decision": "PASS",
        "continuation_allowed": True,
        "pantalla_id": 2,
        "screen_code": "ONB_002",
        "required_by_adapters": ["ADAPTER_LF_SHELL_PROFILE"],
        "governance_receipt": receipt,
    }


def _router_result(*, status="READY_TO_EXECUTE", governance_required=True, input_governance=None, blocking_code=None) -> dict:
    return {
        "router": "ACT-0001",
        "status": status,
        "blocking_code": blocking_code,
        "operation_code": "EJECUCION_PERFIL_LF",
        "asset": {"codigo_activo": "PERFIL-UI-ARCHITECT"},
        "adapters": [{
            "adapter_code": "ADAPTER-LF-SHELL-PROFILE-20260827",
            "adapter_version": "v0.1",
            "relacion_tipo": "ADAPTER_APLICA_A",
            "adapter_metadata": {
                "canonical_adapter_id": "ADAPTER_LF_SHELL_PROFILE",
                "current_path": "adapters/lf_shell_profile_adapter/ADAPTER.md",
                "runtime_enabled": True,
                "router_discoverable": True,
                "input_governance_receipt_required": governance_required,
                "input_governance_continuation_policy": "PASS_ONLY" if governance_required else None,
                "input_governance_contract_resolution": "LIVE_CURRENT" if governance_required else None,
                "input_governance_authority_contract": "INPUT_READINESS_CONTRACT" if governance_required else None,
            },
        }],
        "input_governance": input_governance,
        "downstream_execution_allowed": True if status == "READY_TO_EXECUTE" else False,
    }


def _queue_payload() -> dict:
    return {
        "request_id": "11111111-1111-4111-8111-111111111111",
        "operation_code": "EJECUCION_PERFIL_LF",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "input_literal": "Evalúa ONB_002",
    }


def _sequence_resolver(results):
    pending = list(results)

    def resolve(_payload):
        if not pending:
            raise AssertionError("router resolver called too many times")
        return pending.pop(0)

    return resolve


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

        dispatch_calls = []
        prepared = _prepare_governed_payload(
            _queue_payload(),
            router_resolver=_sequence_resolver([
                _router_result(status="INPUT_GOVERNANCE_REQUIRED", input_governance=_governance_dispatch()),
                _router_result(input_governance=_governance_pass()),
            ]),
            governance_dispatcher=lambda gov: dispatch_calls.append(gov) or {"runtime": "input-governance-agent-v1", "result": {"status": "READY"}},
        )
        assert len(dispatch_calls) == 1
        assert [item["status"] for item in prepared["router_trace"]] == ["INPUT_GOVERNANCE_REQUIRED", "READY_TO_EXECUTE"]
        assert prepared["input_governance"]["decision"] == "PASS"
        assert prepared["lf_adapter_bindings"][0]["input_governance_receipt_required"] is True
        passed += 1

        expect_block(
            "INPUT_GOVERNANCE_RECEIPT_MISSING",
            lambda: _prepare_governed_payload(
                _queue_payload(),
                router_resolver=_sequence_resolver([_router_result(input_governance=None)]),
                governance_dispatcher=lambda _gov: (_ for _ in ()).throw(AssertionError("unexpected dispatch")),
            ),
        )
        passed += 1

        expect_block(
            "BLOCK_INPUT_GOVERNANCE_RECEIPT_STALE",
            lambda: _prepare_governed_payload(
                _queue_payload(),
                router_resolver=_sequence_resolver([
                    _router_result(status="INPUT_GOVERNANCE_REQUIRED", input_governance=_governance_dispatch()),
                    _router_result(status="INPUT_GOVERNANCE_REQUIRED", input_governance=_governance_dispatch(), blocking_code="BLOCK_INPUT_GOVERNANCE_RECEIPT_STALE"),
                ]),
                governance_dispatcher=lambda _gov: {"runtime": "input-governance-agent-v1", "result": {"status": "READY"}},
            ),
        )
        passed += 1

        expect_block(
            "BLOCK_INPUT_GOVERNANCE",
            lambda: _prepare_governed_payload(
                _queue_payload(),
                router_resolver=_sequence_resolver([_router_result(status="BLOCKED", input_governance={"status": "BLOCKED"}, blocking_code="BLOCK_INPUT_GOVERNANCE")]),
                governance_dispatcher=lambda _gov: (_ for _ in ()).throw(AssertionError("unexpected dispatch")),
            ),
        )
        passed += 1

        expect_block(
            "BLOCK_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED",
            lambda: _prepare_governed_payload(
                _queue_payload(),
                router_resolver=_sequence_resolver([_router_result(status="HUMAN_DECISION_REQUIRED", input_governance={"status": "HUMAN_DECISION_REQUIRED"}, blocking_code="BLOCK_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED")]),
                governance_dispatcher=lambda _gov: (_ for _ in ()).throw(AssertionError("unexpected dispatch")),
            ),
        )
        passed += 1

        dispatch_calls = []
        prepared = _prepare_governed_payload(
            _queue_payload(),
            router_resolver=_sequence_resolver([_router_result(governance_required=False)]),
            governance_dispatcher=lambda gov: dispatch_calls.append(gov) or {},
        )
        assert not dispatch_calls
        assert "input_governance" not in prepared
        passed += 1
    finally:
        restore_env(prior)
    if passed != 19:
        raise SystemExit(f"ZERO_COST_PROFILE_RUNTIME_TESTS_FAIL {passed}/19")
    print("ZERO_COST_PROFILE_RUNTIME_TESTS_PASS 19/19")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
