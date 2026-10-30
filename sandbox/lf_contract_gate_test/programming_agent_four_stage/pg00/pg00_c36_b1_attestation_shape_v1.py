"""PG-00.C3.6-B1 isolated attestation envelope schema validator.

This module checks *shape only*. It does not authenticate identity, approve a
catalog, validate a GitHub review, issue a signature or authorize DB writes.
"""
import re

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
REQUIRED = frozenset({
    "schema_version", "proposal_id", "source_repo", "source_path",
    "source_commit_sha", "source_file_sha256", "release_catalog_sha256",
    "release_status_requested", "catalog_version", "chg_id",
    "migration_path", "policy_version",
})
REVIEW_FIELDS = frozenset({"provider", "review_id", "reviewer_id",
                           "reviewed_head_sha", "state"})
ATTESTATION_FIELDS = frozenset({"schema_version", "proposal", "source",
                                "owner_decision", "independent_review"})
REF = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$")
MIGRATION = re.compile(r"^supabase/migrations/[0-9]{14}_[a-z0-9_]+[.]sql$")


def validate_shape(manifest, attestation=None):
    """Always BLOCKED. A shape-valid result is not a verified attestation."""
    errors = {"AUTHENTICATED_AUTHORITY_NOT_VERIFIED"}
    def reject(bad, reason):
        if bad:
            errors.add(reason)
    if not isinstance(manifest, dict):
        return {"verdict": "BLOCKED", "authority": "NONE",
                "reason_codes": sorted(errors | {"INVALID_MANIFEST_SHAPE"})}
    reject(set(manifest) != REQUIRED, "MANIFEST_FIELDS_MISMATCH")
    reject(manifest.get("schema_version") != "LF_C3_RELEASE_PROPOSAL_V1",
           "MANIFEST_SCHEMA_MISMATCH")
    reject(manifest.get("source_repo") != "paulozterra/lf-programming-sandbox" or
           manifest.get("source_path") != "standards/catalog.json",
           "SOURCE_LOCATOR_MISMATCH")
    for field, pattern in (("source_commit_sha", SHA40),
                           ("source_file_sha256", SHA64),
                           ("release_catalog_sha256", SHA64)):
        value = manifest.get(field)
        reject(not isinstance(value, str) or pattern.fullmatch(value) is None,
               "INVALID_" + field.upper())
    for field in ("proposal_id", "catalog_version", "chg_id", "policy_version"):
        value = manifest.get(field)
        reject(not isinstance(value, str) or REF.fullmatch(value) is None,
               "INVALID_" + field.upper())
    path = manifest.get("migration_path")
    reject(not isinstance(path, str) or MIGRATION.fullmatch(path) is None,
           "INVALID_MIGRATION_PATH")
    status = manifest.get("release_status_requested")
    reject(not isinstance(status, str) or
           status not in ("APROBADO", "VALIDAR_CON_LEGAL"),
           "INVALID_RELEASE_STATUS")
    if attestation is not None:
        if not isinstance(attestation, dict):
            errors.add("INVALID_ATTESTATION_SHAPE")
        else:
            reject(set(attestation) != ATTESTATION_FIELDS,
                   "ATTESTATION_FIELDS_MISMATCH")
            reject(attestation.get("schema_version") != "LF_C3_RELEASE_ATTESTATION_V1",
                   "ATTESTATION_SCHEMA_MISMATCH")
            reject(attestation.get("proposal") != manifest.get("proposal_id"),
                   "ATTESTATION_PROPOSAL_MISMATCH")
            # Placeholder identities are NEVER trusted. They exist only for
            # interoperability fixtures; no positive approval path exists.
            for field in ("owner_decision", "independent_review"):
                review = attestation.get(field)
                if not isinstance(review, dict):
                    errors.add("INVALID_" + field.upper())
                    continue
                reject(set(review) != REVIEW_FIELDS,
                       "INVALID_" + field.upper() + "_FIELDS")
                reject(review.get("provider") != "github",
                       "INVALID_" + field.upper() + "_PROVIDER")
                sha = review.get("reviewed_head_sha")
                reject(not isinstance(sha, str) or SHA40.fullmatch(sha) is None,
                       "INVALID_" + field.upper() + "_HEAD")
                for identity in ("review_id", "reviewer_id"):
                    value = review.get(identity)
                    reject(not isinstance(value, str) or REF.fullmatch(value) is None,
                           "INVALID_" + field.upper() + "_IDENTITY")
                reject(review.get("state") != "APPROVED",
                       "INVALID_" + field.upper() + "_STATE")
            owner = attestation.get("owner_decision")
            reviewer = attestation.get("independent_review")
            if isinstance(owner, dict) and isinstance(reviewer, dict):
                reject(owner.get("reviewer_id") == reviewer.get("reviewer_id"),
                       "REVIEWER_SEPARATION_VIOLATED")
    return {"verdict": "BLOCKED", "authority": "NONE",
            "reason_codes": sorted(errors)}
