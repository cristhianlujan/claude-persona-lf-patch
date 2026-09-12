from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any, Iterable

ALLOWED_ACTIONS = {"CHANGE", "KEEP", "DO_NOT_CHANGE", "BLOCK", "RESTRICTION"}


def canonical_json_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


@dataclass(frozen=True)
class DecisionInstruction:
    instruction_id: str
    action: str
    region: str
    directive: str

    def as_dict(self) -> dict[str, str]:
        if self.action not in ALLOWED_ACTIONS:
            raise ValueError(f"INVALID_ACTION:{self.action}")
        if not self.instruction_id or not self.region or not self.directive:
            raise ValueError("EMPTY_REQUIRED_FIELD")
        return {
            "instruction_id": self.instruction_id,
            "action": self.action,
            "region": self.region,
            "directive": self.directive,
        }


def build_profile_decision_package(
    *,
    screen_code: str,
    base_artifact_sha256: str,
    input_governance_run_id: int,
    instructions: Iterable[DecisionInstruction],
) -> dict[str, Any]:
    rows = [item.as_dict() for item in instructions]
    ids = [row["instruction_id"] for row in rows]
    if len(rows) < 6 or len(rows) > 10:
        raise ValueError("INSTRUCTION_COUNT_OUT_OF_RANGE")
    if len(ids) != len(set(ids)):
        raise ValueError("DUPLICATE_INSTRUCTION_ID")
    package = {
        "schema": "lf-profile-decision-package/v1",
        "screen_code": screen_code,
        "base_artifact_sha256": base_artifact_sha256,
        "input_governance_run_id": input_governance_run_id,
        "instructions": rows,
    }
    package["package_sha256"] = canonical_json_sha256(package)
    return package


def validate_generator_receipt(
    *,
    package: dict[str, Any],
    generator_receipt: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    expected_package_sha = package.get("package_sha256")
    if not expected_package_sha:
        errors.append("PACKAGE_SHA_MISSING")
    elif generator_receipt.get("consumed_package_sha256") != expected_package_sha:
        errors.append("PACKAGE_SHA_NOT_CONSUMED_EXACTLY")

    source_ids = {row["instruction_id"] for row in package.get("instructions", [])}
    applied_ids = set(generator_receipt.get("applied_instruction_ids") or [])
    invented_ids = applied_ids - source_ids
    omitted_ids = source_ids - applied_ids
    if invented_ids:
        errors.append("INSTRUCTIONS_INVENTED:" + ",".join(sorted(invented_ids)))
    if omitted_ids:
        errors.append("INSTRUCTIONS_OMITTED:" + ",".join(sorted(omitted_ids)))

    if generator_receipt.get("outside_delta_changed") is True:
        errors.append("OUTSIDE_DELTA_CHANGED")

    new_sha = generator_receipt.get("new_artifact_sha256")
    if not new_sha or new_sha == package.get("base_artifact_sha256"):
        errors.append("NEW_ARTIFACT_SHA_REQUIRED")
    return errors


def validate_profile_review_receipt(
    *,
    expected_artifact_sha256: str,
    receipt: dict[str, Any],
    require_visual_bytes: bool,
) -> list[str]:
    errors: list[str] = []
    if receipt.get("artifact_sha256") != expected_artifact_sha256:
        errors.append("ARTIFACT_SHA_MISMATCH")
    if require_visual_bytes and not receipt.get("visual_bytes_observed"):
        errors.append("VISUAL_BYTES_NOT_OBSERVED")
    if receipt.get("verdict") == "PASS" and receipt.get("downstream_authorized") is not True:
        errors.append("PASS_WITHOUT_DOWNSTREAM_AUTHORIZATION")
    return errors
