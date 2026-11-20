"""PG-00.C3.5: offline attestation *consistency* checks; never validates authority.

No network, credentials, DB writes or release approval. Authenticated evidence
must be fetched and validated by an independently admitted component.
"""
import hashlib
import re

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
REQUIRED = {"proposal_id", "source_repo", "source_path", "source_commit_sha",
            "source_file_sha256", "release_catalog_sha256", "release_status_requested",
            "source_catalog_version", "chg_id", "migration_path", "policy_version"}
REPO = "paulozterra/lf-programming-sandbox"
PATH = "standards/catalog.json"


def inspect_attestation(proposal, *, trusted_source_commit, trusted_source_bytes):
    """An informational, fail-closed comparison. NEVER an approval or permit."""
    reasons = ["EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED"]
    if not isinstance(proposal, dict):
        return {"verdict": "BLOCKED", "authority": "NONE",
                "reason_codes": ["INVALID_PROPOSAL_SHAPE", *reasons]}
    if set(proposal) != REQUIRED:
        reasons.append("INVALID_PROPOSAL_FIELDS")
    if proposal.get("source_repo") != REPO or proposal.get("source_path") != PATH:
        reasons.append("INVALID_SOURCE_LOCATOR")
    if not isinstance(trusted_source_commit, str) or not HEX40.fullmatch(trusted_source_commit):
        reasons.append("INVALID_TRUSTED_COMMIT")
    if proposal.get("source_commit_sha") != trusted_source_commit:
        reasons.append("SOURCE_COMMIT_MISMATCH")
    if not isinstance(trusted_source_bytes, bytes):
        reasons.append("INVALID_TRUSTED_BYTES")
    elif proposal.get("source_file_sha256") != hashlib.sha256(trusted_source_bytes).hexdigest():
        reasons.append("SOURCE_DIGEST_MISMATCH")
    for key in ("source_file_sha256", "release_catalog_sha256"):
        value = proposal.get(key)
        if not isinstance(value, str) or not HEX64.fullmatch(value):
            reasons.append("INVALID_DIGEST_FORMAT")
    if proposal.get("release_status_requested") not in ("APROBADO", "VALIDAR_CON_LEGAL"):
        reasons.append("INVALID_RELEASE_STATUS")
    for key in ("proposal_id", "chg_id", "migration_path", "policy_version",
                "source_catalog_version"):
        if not isinstance(proposal.get(key), str) or not proposal[key].strip():
            reasons.append("INVALID_REQUIRED_REFERENCE")
    return {"verdict": "BLOCKED", "authority": "NONE",
            "reason_codes": sorted(set(reasons))}
