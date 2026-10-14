"""Source-only adapter for Profile Updater authority evidence.

Only trusted infrastructure may provide these reader callbacks. The adapter
uses existing capability registry/current/version and evidence-ledger contracts;
no standalone selector, schema or model execution is introduced.
"""
from __future__ import annotations

from typing import Any, Callable
import re

_SHA = re.compile(r"^[a-f0-9]{64}$")


def make_trusted_profile_readback(
    read_capability_snapshot: Callable[[str], dict[str, Any] | None],
    read_assessment_receipt: Callable[[str, str], dict[str, Any] | None],
) -> Callable[[str, str, str], dict[str, Any]]:
    """Build the planner's injected readback from independently trusted readers.

    Caller must bind callbacks to Supabase read-only query implementations.
    Never bind them to user request JSON or model-generated text.
    """
    if not callable(read_capability_snapshot) or not callable(read_assessment_receipt):
        raise ValueError("TRUSTED_READBACK_READER_INVALID")

    def fail(code: str) -> dict[str, Any]:
        return {"status": "UNRESOLVED", "reason": code,
                "method_catalog_released": False,
                "assessment_evidence_verified": False,
                "qualified_method_ids": []}

    def readback(profile_slug: str, registry_sha256: str, assessment_sha256: str) -> dict[str, Any]:
        if not isinstance(profile_slug, str) or not profile_slug.strip():
            return fail("PROFILE_REF_INVALID")
        if not (isinstance(registry_sha256, str) and _SHA.fullmatch(registry_sha256)
                and isinstance(assessment_sha256, str) and _SHA.fullmatch(assessment_sha256)):
            return fail("SOURCE_SHA_INVALID")
        try:
            cap = read_capability_snapshot("METHOD_PACK_REGISTRY")
            receipt = read_assessment_receipt(profile_slug, assessment_sha256)
        except Exception:
            return fail("TRUSTED_SOURCE_UNAVAILABLE")
        if not isinstance(cap, dict):
            return fail("METHOD_REGISTRY_NOT_REGISTERED")
        if (cap.get("capability_code") != "METHOD_PACK_REGISTRY"
                or cap.get("registry_status") != "ACTIVE"
                or cap.get("release_state") != "RELEASED"
                or not isinstance(cap.get("version"), str)
                or not cap["version"].strip()
                or cap.get("current_version") != cap["version"]
                or not isinstance(cap.get("manifest_sha256"), str)
                or not _SHA.fullmatch(cap["manifest_sha256"])
                or cap.get("current_manifest_sha256") != cap["manifest_sha256"]):
            return fail("METHOD_REGISTRY_VERSION_NOT_CURRENT_RELEASED")
        manifest = cap.get("manifest")
        if not isinstance(manifest, dict) or manifest.get("catalog_payload_sha256") != registry_sha256:
            return fail("CATALOG_PAYLOAD_SHA_MISMATCH")
        portfolio = manifest.get("qualified_method_portfolio")
        if not isinstance(portfolio, list):
            return fail("METHOD_QUALIFICATION_UNRESOLVED")
        qualified: list[str] = []
        for method in portfolio:
            if not isinstance(method, dict):
                return fail("METHOD_QUALIFICATION_INVALID")
            mid = method.get("method_id")
            if (not isinstance(mid, str) or not mid
                    or not isinstance(method.get("exact_version"), str)
                    or not method["exact_version"]
                    or method.get("qualification_state") != "QUALIFIED"
                    or not isinstance(method.get("benchmark_receipt_ref"), str)
                    or not method["benchmark_receipt_ref"]):
                return fail("METHOD_QUALIFICATION_INVALID")
            if mid in qualified:
                return fail("METHOD_QUALIFICATION_DUPLICATE")
            qualified.append(mid)
        if not isinstance(receipt, dict):
            return fail("ASSESSMENT_RECEIPT_MISSING")
        if (receipt.get("subject_type") != "PROFILE_ASSESSMENT"
                or receipt.get("subject_ref") != profile_slug
                or receipt.get("subject_sha256") != assessment_sha256
                or receipt.get("verification_state") != "VERIFIED"
                or receipt.get("resolver_id") != "LF_SUPABASE_READBACK_V1"
                or receipt.get("resolver_active") is not True
                or receipt.get("resolver_trust_level") != "TRUSTED_PROVIDER_BOUND"
                or not isinstance(receipt.get("receipt_id"), str)
                or not receipt["receipt_id"]):
            return fail("ASSESSMENT_RECEIPT_INVALID_OR_UNTRUSTED")
        return {
            "status": "VERIFIED_CURRENT",
            "registry_sha256": registry_sha256,
            "assessment_sha256": assessment_sha256,
            "registry_version": cap["version"],
            "authority_ref": "supabase://lf_capability_current/METHOD_PACK_REGISTRY/" + cap["version"],
            "assessment_receipt_ref": receipt["receipt_id"],
            "qualified_method_ids": sorted(qualified),
            "method_catalog_released": True,
            "assessment_evidence_verified": True,
        }

    return readback
