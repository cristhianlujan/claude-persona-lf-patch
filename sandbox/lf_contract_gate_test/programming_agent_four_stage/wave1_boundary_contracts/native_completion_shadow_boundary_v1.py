"""Candidate metadata boundary for Native shadow observation.

Pure functions only: no DB, transport, dispatch, model, or authority issuance.
Inputs must be trusted readbacks plus independently configured context pins.
A structurally valid notice never proves operational execution or admission.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Any, Mapping, Sequence
from uuid import UUID
import re

_HASH = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class ExpectedNativeContext:
    execution_id: str
    profile_code: str
    context_id: str
    context_sha256: str

    def __post_init__(self) -> None:
        if not self.execution_id.strip() or not self.profile_code.strip():
            raise ValueError("EXPECTED_NATIVE_IDENTITY_REQUIRED")
        if str(UUID(self.context_id)) != self.context_id:
            raise ValueError("EXPECTED_CONTEXT_ID_INVALID")
        if not _HASH.fullmatch(self.context_sha256):
            raise ValueError("EXPECTED_CONTEXT_SHA_INVALID")


def prepare_native_shadow_notice(
    execution: Mapping[str, Any],
    steps: Sequence[Mapping[str, Any]],
    expected: ExpectedNativeContext,
    *,
    enabled: bool = False,
) -> dict[str, Any]:
    """Prepare an advisory notice after COMPLETED/report_output readback.

    This is NOT a SQL function and is not wired to the deployed caller.
    Do not pass model output as execution/steps/expected.
    """
    if type(enabled) is not bool:
        raise ValueError("SHADOW_ENABLED_MUST_BE_BOOL")

    def skip(code: str) -> dict[str, Any]:
        return {"state": code, "notice": None, "effect_authority": False,
                "downstream_execution_allowed": False}

    if not enabled:
        return skip("DISABLED")
    if not isinstance(execution, Mapping) or not isinstance(steps, (list, tuple)):
        return skip("SKIPPED_INVALID_READBACK")
    manifest = execution.get("manifest")
    if not isinstance(manifest, Mapping):
        return skip("SKIPPED_INVALID_READBACK")
    handoff = manifest.get("router_profile_handoff")
    if not isinstance(handoff, Mapping):
        return skip("SKIPPED_INVALID_READBACK")
    if (execution.get("execution_id") != expected.execution_id
            or execution.get("operation_code") != "EJECUCION_PERFIL_LF"
            or execution.get("target_type") != "PERFIL"
            or execution.get("target_code") != expected.profile_code
            or execution.get("status") != "COMPLETED"
            or manifest.get("executor_mode") != "GPT_NATIVE"
            or manifest.get("executor_provider") != "OPENAI_CHATGPT_NATIVE"
            or handoff.get("channel") != "PROGRAMACION"
            or handoff.get("profile_code") != expected.profile_code):
        return skip("SKIPPED_EXECUTION_MISMATCH")
    for step_id in ("semantic_judge", "report_output"):
        matching = [s for s in steps if isinstance(s, Mapping)
                    and s.get("execution_id") == expected.execution_id
                    and s.get("step_id") == step_id]
        if len(matching) != 1 or matching[0].get("status") != "STEP_PASS_WITH_EVIDENCE":
            return skip("SKIPPED_TERMINAL_STEPS_NOT_CLEAN")
    return {
        "state": "NOTICE_PREPARED",
        "effect_authority": False,
        "downstream_execution_allowed": False,
        "notice": {
            "schema_version": "LF_NATIVE_A6_A9_SHADOW_NOTICE_CANDIDATE_V1",
            "execution_id": expected.execution_id,
            "profile_code": expected.profile_code,
            "context_id": expected.context_id,
            "context_sha256": expected.context_sha256,
            "phase": "AFTER_COMPLETED_REPORT_OUTPUT_READBACK",
        },
    }
