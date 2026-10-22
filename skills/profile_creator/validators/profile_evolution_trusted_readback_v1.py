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
    read_method_receipt: Callable[[str, str, str], dict[str, Any] | None],
) -> Callable[[str, str, str], dict[str, Any]]:
    """Build the planner's injected readback from independently trusted readers.

    Caller must bind callbacks to Supabase read-only query implementations.
    Never bind them to user request JSON or model-generated text.
    """
    if not all(callable(x) for x in (read_capability_snapshot, read_assessment_receipt, read_method_receipt)):
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
            try:
                method_receipt = read_method_receipt(mid, method["exact_version"],
                                                     method["benchmark_receipt_ref"])
            except Exception:
                return fail("METHOD_RECEIPT_READBACK_FAILED")
            if (not isinstance(method_receipt, dict)
                or method_receipt.get("subject_type") != "METHOD_QUALIFICATION"
                or method_receipt.get("subject_ref") != mid + "@" + method["exact_version"]
                or method_receipt.get("provider_ref") != method["benchmark_receipt_ref"]
                or method_receipt.get("verification_state") != "VERIFIED"
                or method_receipt.get("resolver_active") is not True
                or method_receipt.get("resolver_trust_level") != "TRUSTED_PROVIDER_BOUND"
                or method_receipt.get("resolver_id") not in
                   {"LF_SUPABASE_READBACK_V1", "LF_GITHUB_SOURCE_READBACK_V1"}
                or not isinstance(method_receipt.get("receipt_id"), str)
                or not method_receipt["receipt_id"]):
                return fail("METHOD_QUALIFICATION_RECEIPT_UNVERIFIED")
            qualified.append(mid)
        if not isinstance(receipt, dict):
            return fail("ASSESSMENT_RECEIPT_MISSING")
        if (receipt.get("subject_type") != "PROFILE_ASSESSMENT"
                or receipt.get("subject_ref") != profile_slug
                or receipt.get("subject_sha256") != assessment_sha256
                or not isinstance(receipt.get("source_head_sha"), str)
                or not re.fullmatch(r"[0-9a-f]{40}", receipt["source_head_sha"])
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
            "assessment_source_head_sha": receipt["source_head_sha"],
            "qualified_method_ids": sorted(qualified),
            "method_catalog_released": True,
            "assessment_evidence_verified": True,
        }

    return readback


# Queries use bind parameters provided by the trusted DB client.
# These are read-only projections of existing Supabase authorities.
METHOD_CURRENT_SQL = """
SELECT r.capability_code, r.status AS registry_status,
       v.version, v.release_state, v.manifest_sha256,
       c.version AS current_version,
       c.manifest_sha256 AS current_manifest_sha256, v.manifest
FROM public.lf_capability_registry r
JOIN public.lf_capability_version_registry v
  ON v.capability_code = r.capability_code
JOIN public.lf_capability_current c
  ON c.capability_code = v.capability_code AND c.version = v.version
WHERE r.capability_code = %s
"""

PROFILE_ASSESSMENT_RECEIPT_SQL = """
SELECT l.receipt_id::text AS receipt_id,
       l.subject_type, l.subject_ref, l.subject_sha256, l.source_head_sha,
       l.verification_state, l.resolver_id,
       rr.active AS resolver_active,
       rr.trust_level AS resolver_trust_level
FROM private.lf_evidence_ledger_v1 l
JOIN private.lf_evidence_resolver_registry_v1 rr
  ON rr.resolver_id = l.resolver_id
WHERE l.subject_type = 'PROFILE_ASSESSMENT'
  AND l.subject_ref = %s
  AND l.subject_sha256 = %s
  AND l.verification_state = 'VERIFIED'
ORDER BY l.verified_at DESC
LIMIT 1
"""


METHOD_QUALIFICATION_RECEIPT_SQL = """
SELECT l.receipt_id::text AS receipt_id, l.subject_type,
       l.subject_ref, l.provider_ref, l.verification_state,
       l.resolver_id, rr.active AS resolver_active,
       rr.trust_level AS resolver_trust_level
FROM private.lf_evidence_ledger_v1 l
JOIN private.lf_evidence_resolver_registry_v1 rr
  ON rr.resolver_id = l.resolver_id
WHERE l.subject_type = 'METHOD_QUALIFICATION'
  AND l.subject_ref = %s AND l.provider_ref = %s
  AND l.verification_state = 'VERIFIED'
ORDER BY l.verified_at DESC
LIMIT 1
"""


def make_postgres_trusted_readback(
    fetch_rows: Callable[[str, tuple[str, ...]], list[dict[str, Any]]],
) -> Callable[[str, str, str], dict[str, Any]]:
    """Wire to an already authorized read-only Supabase SQL transport.

    The transport executes parameterized SELECTs and must not expose writable
    SQL; it owns authentication, identity and audit. No credentials here.
    """
    if not callable(fetch_rows):
        raise ValueError("READ_ONLY_DB_TRANSPORT_INVALID")

    def one(query: str, params: tuple[str, ...]) -> dict[str, Any] | None:
        rows = fetch_rows(query, params)
        if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
            return None
        return rows[0]

    return make_trusted_profile_readback(
        lambda code: one(METHOD_CURRENT_SQL, (code,)),
        lambda slug, digest: one(PROFILE_ASSESSMENT_RECEIPT_SQL, (slug, digest)),
        lambda mid, version, benchmark: one(METHOD_QUALIFICATION_RECEIPT_SQL, (mid + "@" + version, benchmark)),
    )
