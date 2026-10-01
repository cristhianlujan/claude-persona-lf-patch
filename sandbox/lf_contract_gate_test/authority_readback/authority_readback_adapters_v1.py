#!/usr/bin/env python3
from __future__ import annotations

from typing import Any

from authority_readback_v1 import observation_digest

CONTROL_SYSTEM_READBACK_REF = (
    "dbfunc://public.lf_control_system_qualification_readback_v1"
    "(p_candidate_id text, p_repository text, p_base_sha text, p_head_sha text)"
)
PROFILE_UPDATE_LEGACY_REF = "public.lf_profile_update_post_merge_reconcile_v1"
PROFILE_RUNTIME_LEGACY_REF = "public.lf_profile_runtime_refresh_reconcile_asset_v1"


def _observation(
    *,
    check: dict[str, Any],
    decision: str,
    evidence_refs: list[str],
    currentness_receipt: dict[str, Any] | None = None,
) -> dict[str, Any]:
    row = {
        "schema_version": "LF_AUTHORITY_ADAPTER_OBSERVATION_V1",
        "check_id": check["check_id"],
        "adapter_code": check["adapter_code"],
        "subject_ref": check["subject_ref"],
        "authority_ref": check["authority_ref"],
        "source_revision": check["expected_source_revision"],
        "decision": decision,
        "read_only": True,
        "mutation_performed": False,
        "evidence_refs": evidence_refs,
    }
    if currentness_receipt is not None:
        row["currentness_receipt"] = currentness_receipt
    row["receipt_digest"] = observation_digest(row)
    return row


def control_system_qualification_observation(
    *,
    check: dict[str, Any],
    raw_readback: dict[str, Any],
    expected_identity: dict[str, Any],
    currentness_receipt: dict[str, Any] | None = None,
) -> dict[str, Any]:
    identity_ok = all(
        raw_readback.get(field) == expected_identity.get(field)
        for field in ("candidate_id", "repository", "base_sha", "head_sha")
    )
    authority_ok = raw_readback.get("qualification_authority") in (
        None if raw_readback.get("status") == "MISSING" else "PASE_CONTROL_QUALIFICATION_V1",
    )
    qualified = raw_readback.get("status") == "QUALIFIED" and identity_ok and authority_ok

    evidence = [CONTROL_SYSTEM_READBACK_REF]
    if raw_readback.get("qualification_id") is not None:
        evidence.append(f"qualification://{raw_readback['qualification_id']}")
    if raw_readback.get("source_execution_id"):
        evidence.append(f"execution://{raw_readback['source_execution_id']}")

    return _observation(
        check=check,
        decision="AUTHORITY_MATCH" if qualified else "AUTHORITY_MISMATCH",
        evidence_refs=evidence,
        currentness_receipt=currentness_receipt,
    )


def profile_update_readonly_observation(
    *,
    check: dict[str, Any],
    execution: dict[str, Any] | None,
    asset: dict[str, Any] | None,
    expected_identity: dict[str, Any],
    currentness_receipt: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not execution or not asset:
        return _observation(
            check=check,
            decision="AUTHORITY_MISMATCH",
            evidence_refs=[f"legacy-source://{PROFILE_UPDATE_LEGACY_REF}", "readback://missing"],
            currentness_receipt=currentness_receipt,
        )

    metadata = asset.get("metadata") if isinstance(asset.get("metadata"), dict) else {}
    raw_payload = asset.get("raw_payload") if isinstance(asset.get("raw_payload"), dict) else {}

    observed = {
        "profile_code": asset.get("codigo_activo"),
        "repository": execution.get("target_repo"),
        "merge_sha": metadata.get("last_governed_merge_sha"),
        "pr_number": str(metadata.get("last_governed_pr")) if metadata.get("last_governed_pr") is not None else None,
        "entrypoint_sha": metadata.get("entrypoint_sha"),
        "manifest_sha": metadata.get("manifest_sha"),
        "profile_pack_id": metadata.get("profile_pack_id") or raw_payload.get("profile_pack_id"),
    }
    expected = {
        "profile_code": expected_identity.get("profile_code"),
        "repository": expected_identity.get("repository"),
        "merge_sha": expected_identity.get("merge_sha"),
        "pr_number": str(expected_identity.get("pr_number")) if expected_identity.get("pr_number") is not None else None,
        "entrypoint_sha": expected_identity.get("entrypoint_sha"),
        "manifest_sha": expected_identity.get("manifest_sha"),
        "profile_pack_id": expected_identity.get("profile_pack_id"),
    }
    execution_ok = (
        execution.get("operation_code") == "ACTUALIZACION_PERFIL_LF"
        and execution.get("target_type") == "PERFIL"
        and execution.get("target_code") == expected["profile_code"]
        and execution.get("target_repo") == expected["repository"]
    )
    asset_ok = asset.get("tipo_activo") == "PERFIL" and asset.get("archived_at") in (None, "")
    matched = execution_ok and asset_ok and observed == expected

    return _observation(
        check=check,
        decision="AUTHORITY_MATCH" if matched else "AUTHORITY_MISMATCH",
        evidence_refs=[
            f"legacy-source://{PROFILE_UPDATE_LEGACY_REF}",
            f"asset://{asset.get('codigo_activo')}",
            f"execution://{execution.get('execution_id') or execution.get('id') or 'observed'}",
        ],
        currentness_receipt=currentness_receipt,
    )


def profile_runtime_refresh_readonly_observation(
    *,
    check: dict[str, Any],
    execution: dict[str, Any] | None,
    asset: dict[str, Any] | None,
    expected_identity: dict[str, Any],
    currentness_receipt: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not execution or not asset:
        return _observation(
            check=check,
            decision="AUTHORITY_MISMATCH",
            evidence_refs=[f"legacy-source://{PROFILE_RUNTIME_LEGACY_REF}", "readback://missing"],
            currentness_receipt=currentness_receipt,
        )

    metadata = asset.get("metadata") if isinstance(asset.get("metadata"), dict) else {}
    manifest = execution.get("manifest") if isinstance(execution.get("manifest"), dict) else {}
    expected_main = expected_identity.get("expected_main_sha")
    expected_release = expected_identity.get("runtime_release_ref")

    execution_ok = (
        execution.get("operation_code") == "REFRESCO_RUNTIME_PERFIL_LF"
        and execution.get("target_type") == "PERFIL"
        and execution.get("target_code") == expected_identity.get("profile_code")
        and manifest.get("expected_main_sha") == expected_main
    )
    asset_ok = asset.get("tipo_activo") == "PERFIL" and asset.get("archived_at") in (None, "")
    source_ok = (
        metadata.get("runtime_source_sha") == expected_main
        and metadata.get("runtime_release_ref") == expected_release
        and expected_release == f"/opt/lf-profile-runtime-api/releases/{expected_main}"
    )
    matched = execution_ok and asset_ok and source_ok

    return _observation(
        check=check,
        decision="AUTHORITY_MATCH" if matched else "AUTHORITY_MISMATCH",
        evidence_refs=[
            f"legacy-source://{PROFILE_RUNTIME_LEGACY_REF}",
            f"asset://{asset.get('codigo_activo')}",
            f"execution://{execution.get('execution_id') or execution.get('id') or 'observed'}",
        ],
        currentness_receipt=currentness_receipt,
    )
