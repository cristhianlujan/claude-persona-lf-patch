from __future__ import annotations

from typing import Any

from .hashing import canonical_json_sha256, sha256_text
from .models import ProfileTask
from .repository import SchemaBinding

TYPED_CONTEXT_SCHEMA = "lf-runtime-typed-context/v1"
NO_CARD_FALLBACK = "NO_CARD_GOVERNED"


class RuntimeAuthorityError(RuntimeError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


def _is_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(ch in "0123456789abcdef" for ch in value.lower())
    )


def _profile_authority(profile_sources: list[dict[str, str]], task: ProfileTask) -> dict[str, Any]:
    if not isinstance(profile_sources, list) or not profile_sources:
        raise RuntimeAuthorityError("RUNTIME_AUTHORITY_MISSING", "PROFILE_SOURCE")
    manifest: list[dict[str, str]] = []
    seen: set[str] = set()
    for source in profile_sources:
        if not isinstance(source, dict):
            raise RuntimeAuthorityError("RUNTIME_PROFILE_SOURCE_INVALID")
        ref = source.get("ref")
        content = source.get("content")
        if not isinstance(ref, str) or not ref.strip() or not isinstance(content, str) or not content:
            raise RuntimeAuthorityError("RUNTIME_PROFILE_SOURCE_INVALID")
        if ref in seen:
            raise RuntimeAuthorityError("RUNTIME_PROFILE_SOURCE_AMBIGUOUS", ref)
        seen.add(ref)
        manifest.append({"ref": ref, "content_sha256": sha256_text(content)})
    manifest.sort(key=lambda item: item["ref"])
    return {
        "authority_type": "PROFILE_SOURCE",
        "authority_id": task.profile_code,
        "source_refs": [item["ref"] for item in manifest],
        "source_sha256": canonical_json_sha256(manifest),
        "run_id": task.request_id,
        "cross_run_declared": False,
    }


def _resolve_cards(task: ProfileTask) -> dict[str, Any]:
    cards = [item.model_dump(mode="python") for item in task.lf_card_sources]
    required = list(task.required_card_refs)
    by_ref = {item["card_ref"]: item for item in cards}

    if not required:
        if cards:
            code = "RUNTIME_CARD_AMBIGUOUS" if len(cards) > 1 else "RUNTIME_CARD_SELECTION_UNDECLARED"
            raise RuntimeAuthorityError(code, ",".join(sorted(by_ref)))
        return {
            "status": "FALLBACK",
            "mode": NO_CARD_FALLBACK,
            "selected_card_refs": [],
            "reason": "NO_APPLICABLE_CARD_DECLARED",
            "schema_invention_allowed": False,
        }

    selected = set(required)
    supplied = set(by_ref)
    missing = sorted(selected - supplied)
    if missing:
        raise RuntimeAuthorityError("RUNTIME_CARD_REQUIRED_SOURCE_MISSING", ",".join(missing))
    extras = sorted(supplied - selected)
    if extras:
        raise RuntimeAuthorityError("RUNTIME_CARD_AMBIGUOUS", ",".join(extras))

    for ref in sorted(required):
        missing_fields = sorted(
            field
            for field in by_ref[ref].get("required_input_fields", [])
            if field not in task.input_fields
        )
        if missing_fields:
            raise RuntimeAuthorityError(
                "RUNTIME_CARD_REQUIRED_INPUT_MISSING",
                f"{ref}:" + ",".join(missing_fields),
            )

    return {
        "status": "RESOLVED",
        "mode": "ROUTER_SELECTED",
        "selected_card_refs": sorted(required),
        "cards": [
            {
                "card_ref": by_ref[ref]["card_ref"],
                "card_version": by_ref[ref]["card_version"],
                "source_ref": by_ref[ref]["source_ref"],
                "content_sha256": by_ref[ref]["content_sha256"],
                "selected_sections": by_ref[ref]["selected_sections"],
                "required_input_fields": by_ref[ref].get("required_input_fields", []),
            }
            for ref in sorted(required)
        ],
        "schema_invention_allowed": False,
    }


def _resolve_adapters(task: ProfileTask) -> list[dict[str, Any]]:
    sources = [item.model_dump(mode="python") for item in task.lf_adapter_sources]
    by_code: dict[str, dict[str, Any]] = {}
    for item in sources:
        code = item["adapter_code"]
        if code in by_code:
            raise RuntimeAuthorityError("RUNTIME_ADAPTER_AMBIGUOUS", code)
        by_code[code] = item
    for code in task.required_adapter_codes:
        if code not in by_code:
            raise RuntimeAuthorityError("RUNTIME_ADAPTER_MISSING", code)
    return [
        {
            "adapter_code": item["adapter_code"],
            "adapter_version": item["adapter_version"],
            "assurance_revision": item["assurance_revision"],
            "activation_source": item["activation_source"],
            "binding_ref": item["binding_ref"],
            "target_ref": item["target_ref"],
            "ref": item["ref"],
            "content_sha256": sha256_text(item["content"]),
        }
        for item in sorted(sources, key=lambda value: value["adapter_code"])
    ]


def _resolve_authorities(
    task: ProfileTask,
    *,
    profile_sources: list[dict[str, str]],
    context_pack: dict[str, Any],
) -> list[dict[str, Any]]:
    authorities = [_profile_authority(profile_sources, task)]
    input_governance = context_pack.get("input_governance")
    if input_governance is not None:
        if not isinstance(input_governance, dict):
            raise RuntimeAuthorityError("RUNTIME_INPUT_GOVERNANCE_AUTHORITY_INVALID")
        if input_governance.get("current") is not True or input_governance.get("ready") is not True:
            raise RuntimeAuthorityError("RUNTIME_INPUT_GOVERNANCE_AUTHORITY_NOT_READY")
        context_sha = input_governance.get("context_sha256")
        receipt_ref = input_governance.get("receipt_ref")
        if not _is_sha256(context_sha) or not isinstance(receipt_ref, str) or not receipt_ref:
            raise RuntimeAuthorityError("RUNTIME_INPUT_GOVERNANCE_PROVENANCE_MISSING")
        authorities.append(
            {
                "authority_type": "INPUT_GOVERNANCE",
                "authority_id": "INPUT_GOVERNANCE_AGENT",
                "source_refs": [receipt_ref],
                "source_sha256": context_sha,
                "run_id": task.request_id,
                "cross_run_declared": False,
            }
        )

    contract = context_pack.get("runtime_authority_contract") or {}
    if not isinstance(contract, dict):
        raise RuntimeAuthorityError("RUNTIME_AUTHORITY_CONTRACT_INVALID")
    declared_current_run_id = contract.get("current_run_id")
    if declared_current_run_id is not None:
        if not isinstance(declared_current_run_id, str) or not declared_current_run_id:
            raise RuntimeAuthorityError("RUNTIME_AUTHORITY_CURRENT_RUN_INVALID")
        if declared_current_run_id != task.request_id:
            raise RuntimeAuthorityError(
                "RUNTIME_AUTHORITY_CURRENT_RUN_MISMATCH",
                f"declared={declared_current_run_id};expected={task.request_id}",
            )
    current_run_id = task.request_id
    required_types = contract.get("required_authority_types", [])
    extra_sources = contract.get("authority_sources", [])
    if not isinstance(required_types, list) or any(not isinstance(v, str) or not v for v in required_types):
        raise RuntimeAuthorityError("RUNTIME_REQUIRED_AUTHORITY_TYPES_INVALID")
    if len(required_types) != len(set(required_types)):
        raise RuntimeAuthorityError("RUNTIME_REQUIRED_AUTHORITY_TYPES_INVALID", "duplicate")
    if not isinstance(extra_sources, list):
        raise RuntimeAuthorityError("RUNTIME_AUTHORITY_SOURCES_INVALID")

    for source in extra_sources:
        if not isinstance(source, dict):
            raise RuntimeAuthorityError("RUNTIME_AUTHORITY_SOURCE_INVALID")
        authority_type = source.get("authority_type")
        authority_id = source.get("authority_id")
        source_ref = source.get("source_ref")
        source_sha = source.get("source_sha256")
        run_id = source.get("run_id", current_run_id)
        if not all(isinstance(v, str) and v for v in (authority_type, authority_id, source_ref, run_id)):
            raise RuntimeAuthorityError("RUNTIME_AUTHORITY_SOURCE_INCOMPLETE")
        if not _is_sha256(source_sha):
            raise RuntimeAuthorityError("RUNTIME_AUTHORITY_PROVENANCE_INVALID", authority_id)
        if run_id != current_run_id and source.get("cross_run_declared") is not True:
            raise RuntimeAuthorityError("RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED", authority_id)
        authorities.append(
            {
                "authority_type": authority_type,
                "authority_id": authority_id,
                "source_refs": [source_ref],
                "source_sha256": source_sha,
                "run_id": run_id,
                "cross_run_declared": bool(source.get("cross_run_declared", False)),
            }
        )

    all_required = {"PROFILE_SOURCE", *required_types}
    if input_governance is not None:
        all_required.add("INPUT_GOVERNANCE")
    for authority_type in sorted(all_required):
        matches = [item for item in authorities if item["authority_type"] == authority_type]
        if not matches:
            raise RuntimeAuthorityError("RUNTIME_AUTHORITY_MISSING", authority_type)
        if len({item["source_sha256"] for item in matches}) > 1:
            raise RuntimeAuthorityError("RUNTIME_AUTHORITY_INCOMPATIBLE", authority_type)

    return sorted(authorities, key=lambda item: (item["authority_type"], item["authority_id"]))


def _assert_provenance_reconstructible(
    *,
    card_resolution: dict[str, Any],
    authority_resolution: list[dict[str, Any]],
    adapter_binding: list[dict[str, Any]],
    schema: SchemaBinding,
) -> None:
    if not _is_sha256(schema.sha256) or len(schema.source_refs) != 1 or not schema.source_refs[0]:
        raise RuntimeAuthorityError("RUNTIME_PROVENANCE_NOT_RECONSTRUCTIBLE", "RUNTIME_SCHEMA")

    if card_resolution.get("status") == "RESOLVED":
        for card in card_resolution.get("cards", []):
            if not card.get("source_ref") or not _is_sha256(card.get("content_sha256")):
                raise RuntimeAuthorityError("RUNTIME_PROVENANCE_NOT_RECONSTRUCTIBLE", "CARD")

    for authority in authority_resolution:
        refs = authority.get("source_refs")
        if (
            not isinstance(refs, list)
            or not refs
            or any(not isinstance(ref, str) or not ref for ref in refs)
            or not _is_sha256(authority.get("source_sha256"))
        ):
            raise RuntimeAuthorityError("RUNTIME_PROVENANCE_NOT_RECONSTRUCTIBLE", "AUTHORITY")

    for adapter in adapter_binding:
        if (
            not adapter.get("ref")
            or not adapter.get("binding_ref")
            or not _is_sha256(adapter.get("content_sha256"))
        ):
            raise RuntimeAuthorityError("RUNTIME_PROVENANCE_NOT_RECONSTRUCTIBLE", "ADAPTER")


def resolve_typed_runtime_context(
    task: ProfileTask,
    *,
    profile_sources: list[dict[str, str]],
    context_pack: dict[str, Any],
    schema: SchemaBinding,
) -> dict[str, Any]:
    if len(schema.source_refs) != 1:
        raise RuntimeAuthorityError("RUNTIME_SCHEMA_AMBIGUOUS", ",".join(schema.source_refs))

    artifact = context_pack.get("artifact")
    screen_code = artifact.get("screen_code") if isinstance(artifact, dict) else None
    classification = {
        "surface_code": screen_code or f"PROFILE:{task.profile_slug}",
        "task_code": f"{task.operation_code}:{task.runtime_output_mode}",
    }

    card_resolution = _resolve_cards(task)
    authority_resolution = _resolve_authorities(
        task, profile_sources=profile_sources, context_pack=context_pack
    )
    adapter_binding = _resolve_adapters(task)
    _assert_provenance_reconstructible(
        card_resolution=card_resolution,
        authority_resolution=authority_resolution,
        adapter_binding=adapter_binding,
        schema=schema,
    )

    typed = {
        "schema": TYPED_CONTEXT_SCHEMA,
        "current_run_id": task.request_id,
        "classification": classification,
        "input": {
            "input_literal_sha256": sha256_text(task.input_literal),
            "input_fields": task.input_fields,
            "input_fields_sha256": canonical_json_sha256(task.input_fields),
            "profile_code": task.profile_code,
            "profile_slug": task.profile_slug,
        },
        "card_resolution": card_resolution,
        "authority_resolution": authority_resolution,
        "adapter_binding": adapter_binding,
        "runtime_schema": {
            "source_ref": schema.source_refs[0],
            "sha256": schema.sha256,
            "mode": schema.mode,
            "schema_invention_allowed": False,
        },
        "provenance_reconstructible": True,
    }
    typed["typed_context_sha256"] = canonical_json_sha256(typed)
    return typed
