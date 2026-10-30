"""C3.6-A isolated consistency planner: NEVER grants permission or writes a DB."""
import hashlib
import json
import re

REQUIRED = {"proposal_id", "source_repo", "source_path", "source_commit_sha", "source_file_sha256", "release_catalog_sha256", "release_status_requested", "source_catalog_version", "chg_id", "migration_path", "policy_version"}
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
MIGRATION = re.compile(r"^supabase/migrations/[0-9]{14}_[a-z0-9_]+[.]sql$")
CHG = re.compile(r"^CHG-[A-Za-z0-9_-]+$")


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def parse_json(raw):
    return json.loads(raw, object_pairs_hook=unique_pairs,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError("NONFINITE_JSON")))


def inspect_plan(proposal, *, source_bytes, release_bytes, trusted_commit, fixture_registry):
    """Fixture registry is untrusted test input, NEVER an authenticated provider."""
    errors = {"EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED"}
    def reject(condition, reason):
        if condition:
            errors.add(reason)
    if not isinstance(proposal, dict):
        return {"verdict": "BLOCKED", "authority": "NONE",
                "reason_codes": sorted(errors | {"INVALID_PROPOSAL_SHAPE"})}
    reject(set(proposal) != REQUIRED, "INVALID_PROPOSAL_FIELDS")
    reject(proposal.get("source_repo") != "paulozterra/lf-programming-sandbox" or
           proposal.get("source_path") != "standards/catalog.json", "SOURCE_LOCATOR_MISMATCH")
    reject(not isinstance(trusted_commit, str) or not SHA40.fullmatch(trusted_commit),
           "INVALID_TRUSTED_COMMIT")
    reject(proposal.get("source_commit_sha") != trusted_commit, "COMMIT_MISMATCH")
    for field in ("source_file_sha256", "release_catalog_sha256"):
        digest = proposal.get(field)
        reject(not isinstance(digest, str) or not SHA64.fullmatch(digest), "INVALID_DIGEST_FORMAT")
    source = release = None
    for label, raw, digest_key in (
        ("SOURCE", source_bytes, "source_file_sha256"),
        ("RELEASE", release_bytes, "release_catalog_sha256"),
    ):
        if not isinstance(raw, bytes):
            errors.add("INVALID_" + label + "_BYTES")
            continue
        reject(proposal.get(digest_key) != hashlib.sha256(raw).hexdigest(),
               label + "_DIGEST_MISMATCH")
        try:
            parsed = parse_json(raw)
        except (ValueError, UnicodeError):
            errors.add("INVALID_" + label + "_JSON")
            parsed = None
        if label == "SOURCE":
            source = parsed
        else:
            release = parsed
    if isinstance(source, dict) and isinstance(release, dict):
        reject(source.get("status") != "BORRADOR_EN_REPO_DE_CALIFICACION",
               "INVALID_SOURCE_STATUS")
        reject(release.get("status") not in {"APROBADO", "VALIDAR_CON_LEGAL"},
               "INVALID_RELEASE_STATUS")
        reject(proposal.get("release_status_requested") != release.get("status"),
               "RELEASE_STATUS_MISMATCH")
        reject(proposal.get("source_catalog_version") != source.get("catalog_version"),
               "VERSION_MISMATCH")
        drift = (source.keys() ^ release.keys()) | {
            key for key in source.keys() & release.keys() if source[key] != release[key]
        }
        reject(drift != {"status"}, "RELEASE_CONTENT_DRIFT")
    else:
        errors.add("INVALID_CATALOG_SHAPE")
    proposal_id = proposal.get("proposal_id")
    chg = proposal.get("chg_id")
    path = proposal.get("migration_path")
    reject(not isinstance(proposal_id, str) or not proposal_id.strip(), "INVALID_PROPOSAL_ID")
    reject(not isinstance(chg, str) or not CHG.fullmatch(chg), "INVALID_CHG")
    reject(not isinstance(path, str) or not MIGRATION.fullmatch(path), "INVALID_MIGRATION_PATH")
    policy = proposal.get("policy_version")
    reject(not isinstance(policy, str) or not policy.strip(), "INVALID_POLICY_REFERENCE")
    if not isinstance(fixture_registry, dict):
        errors.add("INVALID_FIXTURE_REGISTRY")
    else:
        entry = fixture_registry.get(proposal_id) if isinstance(proposal_id, str) else None
        if not isinstance(entry, dict):
            errors.add("PROPOSAL_NOT_IN_FIXTURE_REGISTRY")
        else:
            for field in ("source_commit_sha", "source_file_sha256",
                          "release_catalog_sha256", "chg_id", "migration_path",
                          "policy_version"):
                reject(entry.get(field) != proposal.get(field), "FIXTURE_BINDING_MISMATCH")
            reject(entry.get("consumed") is not False, "FIXTURE_REPLAY_OR_UNKNOWN")
    return {"verdict": "BLOCKED", "authority": "NONE", "reason_codes": sorted(errors)}
