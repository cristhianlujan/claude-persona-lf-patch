from __future__ import annotations

import base64
import binascii
import re
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .hashing import canonical_json_sha256, sha256_bytes

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_]{0,79}$")
CODE_RE = re.compile(r"^[A-Z0-9][A-Z0-9_-]{0,119}$")
MAX_IMAGE_BYTES = 12 * 1024 * 1024
MAX_CARD_CHARS = 8_000
KNOWN_PROFILE_BINDINGS = {
    "product_director_lf": "PERFIL-PRODUCT-DIRECTOR-LF",
    "ui_architect": "PERFIL-UI-ARCHITECT",
    "quality_pack": "PERFIL-QUALITY-PACK",
}


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Observation(StrictModel):
    id: str | int | None = None
    text: str = Field(min_length=1, max_length=1000)
    bbox: tuple[float, float, float, float]
    conf: float = Field(default=100.0, ge=-1.0, le=100.0)

    @model_validator(mode="after")
    def validate_bbox(self) -> "Observation":
        _x, _y, width, height = self.bbox
        if width <= 0 or height <= 0:
            raise ValueError("OBSERVATION_BBOX_SIZE_INVALID")
        return self


class Artifact(StrictModel):
    screen_code: str = Field(min_length=1, max_length=120)
    filename: str = Field(min_length=1, max_length=255)
    image_sha256: str = Field(pattern=SHA256_RE.pattern)
    width_px: int = Field(gt=0, le=20_000)
    height_px: int = Field(gt=0, le=20_000)
    observations: list[Observation] = Field(default_factory=list, max_length=2000)
    image_base64: str | None = None
    image_media_type: Literal["image/png", "image/jpeg", "image/webp"] | None = None

    @model_validator(mode="after")
    def validate_image_binding(self) -> "Artifact":
        if (self.image_base64 is None) != (self.image_media_type is None):
            raise ValueError("ARTIFACT_IMAGE_BINDING_INCOMPLETE")
        if self.image_base64 is not None:
            try:
                raw = base64.b64decode(self.image_base64, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise ValueError("ARTIFACT_IMAGE_BASE64_INVALID") from exc
            if not raw or len(raw) > MAX_IMAGE_BYTES:
                raise ValueError("ARTIFACT_IMAGE_SIZE_INVALID")
            if sha256_bytes(raw) != self.image_sha256:
                raise ValueError("ARTIFACT_IMAGE_SHA256_MISMATCH")
        return self

    def image_bytes(self) -> bytes | None:
        return base64.b64decode(self.image_base64, validate=True) if self.image_base64 else None


class CanonicalInputGovernanceEvidence(StrictModel):
    """Source-bound LF Input Governance receipt fields preserved by the runtime envelope."""

    run_id: int = Field(gt=0)
    governance_agent_used: Literal["INPUT_GOVERNANCE_AGENT"] = "INPUT_GOVERNANCE_AGENT"
    governance_version: str = Field(min_length=1, max_length=80)
    consumer: Literal["CONTEXT_PACK"]
    sections_consumed: list[str] = Field(min_length=1, max_length=40)
    source_refs: list[str] = Field(min_length=1, max_length=40)
    source_snapshot_sha256: str = Field(pattern=SHA256_RE.pattern)
    contract_snapshot_sha256: str = Field(pattern=SHA256_RE.pattern)
    currentness: Literal["LIVE_CURRENT"]
    decision: Literal["PASS"]
    agent_output_sha256: str | None = Field(default=None, pattern=SHA256_RE.pattern)


class InputGovernanceReceipt(StrictModel):
    receipt_ref: str = Field(min_length=1, max_length=500)
    current: bool
    ready: bool
    context_sha256: str = Field(pattern=SHA256_RE.pattern)
    context: dict[str, Any]
    status: str = Field(min_length=1, max_length=120)
    canonical_receipt: CanonicalInputGovernanceEvidence | None = None

    @model_validator(mode="after")
    def validate_current_context(self) -> "InputGovernanceReceipt":
        if self.current is not True:
            raise ValueError("INPUT_GOVERNANCE_NOT_CURRENT")
        if self.ready is not True:
            raise ValueError("INPUT_GOVERNANCE_NOT_READY")
        if canonical_json_sha256(self.context) != self.context_sha256:
            raise ValueError("INPUT_GOVERNANCE_CONTEXT_SHA256_MISMATCH")
        return self


class RouterAdapterSource(StrictModel):
    adapter_code: str = Field(pattern=CODE_RE.pattern)
    adapter_version: str | None = Field(default=None, min_length=1, max_length=120)
    assurance_revision: str = Field(min_length=1, max_length=120)
    activation_source: Literal["ROUTER"]
    binding_ref: str = Field(min_length=1, max_length=500)
    target_ref: str = Field(pattern=CODE_RE.pattern)
    ref: str = Field(min_length=1, max_length=500)
    content: str = Field(min_length=1, max_length=2000)


class CardSource(StrictModel):
    """Bounded JIT Card capsule; content is data/context, not a new runtime authority."""

    card_ref: str = Field(min_length=1, max_length=500)
    card_version: str = Field(min_length=1, max_length=120)
    source_ref: str = Field(min_length=1, max_length=500)
    content_sha256: str = Field(pattern=SHA256_RE.pattern)
    selected_sections: list[str] = Field(min_length=1, max_length=20)
    budget_chars: int = Field(gt=0, le=MAX_CARD_CHARS)
    content: str = Field(min_length=1, max_length=MAX_CARD_CHARS)

    @model_validator(mode="after")
    def validate_content_binding(self) -> "CardSource":
        raw = self.content.encode("utf-8")
        if len(self.content) > self.budget_chars:
            raise ValueError("LF_CARD_CONTENT_BUDGET_EXCEEDED")
        if sha256_bytes(raw) != self.content_sha256:
            raise ValueError("LF_CARD_CONTENT_SHA256_MISMATCH")
        if len(self.selected_sections) != len(set(self.selected_sections)):
            raise ValueError("LF_CARD_SELECTED_SECTIONS_DUPLICATE")
        return self


class ProfileTask(StrictModel):
    request_id: str = Field(min_length=1, max_length=200)
    operation_code: Literal["EJECUCION_PERFIL_LF"] = "EJECUCION_PERFIL_LF"
    profile_code: str = Field(pattern=CODE_RE.pattern)
    profile_slug: str = Field(pattern=SLUG_RE.pattern)
    profile_source_paths: list[str] = Field(min_length=1, max_length=20)
    input_literal: str = Field(min_length=1, max_length=100_000)
    lf_adapter_sources: list[RouterAdapterSource] = Field(default_factory=list, max_length=4)
    required_adapter_codes: list[str] = Field(default_factory=list, max_length=4)
    lf_card_sources: list[CardSource] = Field(default_factory=list, max_length=4)
    required_card_refs: list[str] = Field(default_factory=list, max_length=4)
    send_image_to_model: bool = False

    @model_validator(mode="after")
    def validate_bound_sources(self) -> "ProfileTask":
        expected_code = KNOWN_PROFILE_BINDINGS.get(self.profile_slug)
        if expected_code is not None and self.profile_code != expected_code:
            raise ValueError("PROFILE_SLUG_CODE_BINDING_MISMATCH")

        seen_adapters: set[str] = set()
        adapter_versions: dict[str, str | None] = {}
        for item in self.lf_adapter_sources:
            if item.target_ref != self.profile_code:
                raise ValueError("LF_ADAPTER_TARGET_MISMATCH")
            if item.adapter_code in seen_adapters:
                raise ValueError("LF_ADAPTER_DUPLICATE")
            seen_adapters.add(item.adapter_code)
            adapter_versions[item.adapter_code] = item.adapter_version
        if len(self.required_adapter_codes) != len(set(self.required_adapter_codes)):
            raise ValueError("LF_ADAPTER_REQUIRED_CODES_DUPLICATE")
        missing_adapters = sorted(set(self.required_adapter_codes) - seen_adapters)
        if missing_adapters:
            raise ValueError("LF_ADAPTER_REQUIRED_SOURCE_MISSING:" + ",".join(missing_adapters))
        missing_versions = sorted(
            code for code in self.required_adapter_codes if not adapter_versions.get(code)
        )
        if missing_versions:
            raise ValueError("LF_ADAPTER_REQUIRED_VERSION_MISSING:" + ",".join(missing_versions))

        seen_cards: set[str] = set()
        for item in self.lf_card_sources:
            if item.card_ref in seen_cards:
                raise ValueError("LF_CARD_DUPLICATE")
            seen_cards.add(item.card_ref)
        if len(self.required_card_refs) != len(set(self.required_card_refs)):
            raise ValueError("LF_CARD_REQUIRED_REFS_DUPLICATE")
        missing_cards = sorted(set(self.required_card_refs) - seen_cards)
        if missing_cards:
            raise ValueError("LF_CARD_REQUIRED_SOURCE_MISSING:" + ",".join(missing_cards))
        return self


class ExecuteRequest(StrictModel):
    artifact: Artifact
    input_governance: InputGovernanceReceipt
    profile: ProfileTask


class QueueExecuteRequest(StrictModel):
    """Queue-native profile execution without screen/artifact requirements.

    This preserves the legacy queue contract used by normal profile invocations while
    moving inference transport to the persistent Hetzner API. Screen-bound requests
    continue to use ExecuteRequest with explicit Input Governance + artifact lineage.
    """

    profile: ProfileTask


class BatchRequest(StrictModel):
    batch_id: str = Field(min_length=1, max_length=200)
    artifact: Artifact
    input_governance: InputGovernanceReceipt
    profiles: list[ProfileTask] = Field(min_length=1, max_length=16)

    @model_validator(mode="after")
    def unique_requests(self) -> "BatchRequest":
        ids = [item.request_id for item in self.profiles]
        if len(ids) != len(set(ids)):
            raise ValueError("BATCH_REQUEST_ID_DUPLICATE")
        return self


class JobAccepted(StrictModel):
    job_id: str
    status: str
    reused: bool
    status_url: str
