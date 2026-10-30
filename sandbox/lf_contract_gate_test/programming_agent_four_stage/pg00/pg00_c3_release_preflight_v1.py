"""PG-00.C3 offline release preflight — validation only, never release authority.

Only checks a candidate against pinned source bytes and explicit evidence fields.
A passing result is NOT a Train receipt, signature, approval, or DB write permission.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

SHA40 = re.compile(r"^[a-f0-9]{40}$")
SHA64 = re.compile(r"^[a-f0-9]{64}$")
SEMVER = re.compile(r"^[0-9]+[.][0-9]+[.][0-9]+$")
APPROVED = {"APROBADO", "VALIDAR_CON_LEGAL"}
SOURCE_REPO = "paulozterra/lf-programming-sandbox"
SOURCE_PATH = "standards/catalog.json"


def inspect(candidate: dict, source: bytes, *, expected_commit: str) -> dict:
    """Return informative fail-closed checks; no input can yield publication authority."""
    if not isinstance(candidate, dict):
        return {"verdict": "BLOCKED", "reason_codes": ["INVALID_CANDIDATE_SHAPE"],
                "authority": "NONE"}
    errors = []
    def reject(condition, reason):
        if condition:
            errors.append(reason)

    try:
        doc = json.loads(source)
    except (ValueError, UnicodeDecodeError):
        return {"verdict": "BLOCKED", "reason_codes": ["INVALID_SOURCE_JSON"],
                "authority": "NONE"}

    reject(not isinstance(doc, dict), "INVALID_SOURCE_JSON")
    if not isinstance(doc, dict):
        return {"verdict": "BLOCKED", "reason_codes": sorted(set(errors)),
                "authority": "NONE"}
    reject(doc.get("schema_version") != "LF_STANDARDS_CATALOG_V1", "SCHEMA_MISMATCH")
    reject(not SEMVER.fullmatch(str(doc.get("catalog_version", ""))), "INVALID_CATALOG_VERSION")
    reject(doc.get("status") != "BORRADOR_EN_REPO_DE_CALIFICACION",
           "UNEXPECTED_SOURCE_STATUS")
    reject(candidate.get("source_repo") != SOURCE_REPO, "SOURCE_REPO_MISMATCH")
    reject(candidate.get("source_path") != SOURCE_PATH, "SOURCE_PATH_MISMATCH")
    reject(not SHA40.fullmatch(str(expected_commit)), "INVALID_TRUSTED_COMMIT")
    reject(candidate.get("source_commit_sha") != expected_commit, "SOURCE_COMMIT_MISMATCH")
    reject(candidate.get("source_file_sha256") != hashlib.sha256(source).hexdigest(),
           "SOURCE_BYTES_DIGEST_MISMATCH")
    reject(candidate.get("catalog_version") != doc.get("catalog_version"),
           "CATALOG_VERSION_MISMATCH")
    rules = doc.get("rules")
    reject(not isinstance(rules, list) or not rules, "SOURCE_RULES_INVALID")
    if isinstance(rules, list):
        reject(any(not isinstance(rule, dict) or rule.get("status") not in APPROVED
                   for rule in rules), "SOURCE_RULE_STATUS_NOT_RELEASE_READY")
    # The actual C3 table rejects the source draft status. A candidate release
    # must be separately authorized and transformed, never silently relabelled.
    release = candidate.get("release_catalog")
    reject(not isinstance(release, dict), "RELEASE_PAYLOAD_MISSING")
    if isinstance(release, dict):
        reject(release.get("status") not in APPROVED, "RELEASE_STATUS_NOT_APPROVED")
        reject(release.get("catalog_version") != doc.get("catalog_version"),
               "RELEASE_VERSION_MISMATCH")
        reject(release.get("schema_version") != doc.get("schema_version"),
               "RELEASE_SCHEMA_MISMATCH")
        reject(release.get("rules") != rules, "RELEASE_RULES_CHANGED")
        for field in ("domains", "waiver_settings", "decisions"):
            reject(release.get(field) != doc.get(field), "RELEASE_CONTENT_DRIFT")
        changes = {k for k in set(doc) | set(release) if doc.get(k) != release.get(k)}
        reject(changes != {"status"}, "UNAUTHORIZED_RELEASE_TRANSFORMATION")
    # No external approval, signature, exact-HEAD review, or Train provenance is
    # verifiable from these self-declared inputs. Do not assert otherwise.
    errors.append("AUTHENTICATED_APPROVAL_AND_TRAIN_RECEIPT_REQUIRED")
    return {"verdict": "BLOCKED",
            "reason_codes": sorted(set(errors)),
            "authority": "NONE",
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "catalog_version": doc.get("catalog_version")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--trusted-commit", required=True,
                        help="SHA from trusted GitHub retrieval, never from candidate JSON")
    args = parser.parse_args()
    try:
        candidate = json.loads(args.candidate.read_text(encoding="utf-8"))
    except (ValueError, UnicodeDecodeError):
        candidate = None
    result = inspect(candidate, args.source.read_bytes(),
                     expected_commit=args.trusted_commit)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["verdict"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
