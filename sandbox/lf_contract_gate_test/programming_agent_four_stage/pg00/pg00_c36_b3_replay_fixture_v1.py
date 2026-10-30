"""C3.6-B3 immutable offline replay simulation; never authoritative or persistent.

A fixture models already-consumed identities. No transactions, locks, database,
authenticated approval, Train receipt, or release publication exist here.
"""
import re

SEMVER = re.compile(r"^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def check_candidate(proposal, *, ledger_fixture):
    errors = {"AUTHENTICATED_LEDGER_AND_TRAIN_REQUIRED"}
    if not isinstance(proposal, dict) or not isinstance(ledger_fixture, dict):
        return {"verdict": "BLOCKED", "authority": "NONE",
                "reason_codes": sorted(errors | {"INVALID_FIXTURE_SHAPE"})}
    proposal_id = proposal.get("proposal_id")
    version = proposal.get("catalog_version")
    digest = proposal.get("release_catalog_sha256")
    if not isinstance(proposal_id, str) or not proposal_id.strip():
        errors.add("INVALID_PROPOSAL_ID")
    if not isinstance(version, str) or SEMVER.fullmatch(version) is None:
        errors.add("INVALID_CATALOG_VERSION")
    if not isinstance(digest, str) or HEX64.fullmatch(digest) is None:
        errors.add("INVALID_RELEASE_DIGEST")
    consumed = ledger_fixture.get("consumed_proposal_ids")
    releases = ledger_fixture.get("published_releases")
    if not isinstance(consumed, list) or not all(isinstance(x, str) for x in consumed):
        errors.add("INVALID_CONSUMPTION_FIXTURE")
        consumed = []
    if not isinstance(releases, list) or not all(
        isinstance(row, dict) and
        isinstance(row.get("catalog_version"), str) and
        isinstance(row.get("release_catalog_sha256"), str)
        for row in releases
    ):
        errors.add("INVALID_RELEASE_FIXTURE")
        releases = []
    if isinstance(proposal_id, str) and proposal_id in consumed:
        errors.add("PROPOSAL_ALREADY_CONSUMED")
    if isinstance(version, str):
        if any(row["catalog_version"] == version for row in releases):
            errors.add("CATALOG_VERSION_ALREADY_USED")
        parsed = SEMVER.fullmatch(version)
        previous = []
        for row in releases:
            match = SEMVER.fullmatch(row["catalog_version"])
            if match is None:
                errors.add("INVALID_PUBLISHED_VERSION_FIXTURE")
            else:
                previous.append(tuple(map(int, match.groups())))
        if parsed and previous and tuple(map(int, parsed.groups())) <= max(previous):
            errors.add("CATALOG_VERSION_NOT_MONOTONIC")
    if isinstance(digest, str) and any(
        row["release_catalog_sha256"] == digest for row in releases
    ):
        errors.add("RELEASE_DIGEST_ALREADY_USED")
    return {"verdict": "BLOCKED", "authority": "NONE",
            "reason_codes": sorted(errors)}
