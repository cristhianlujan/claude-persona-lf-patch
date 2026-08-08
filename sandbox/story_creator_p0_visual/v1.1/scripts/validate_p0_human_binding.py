#!/usr/bin/env python3
"""Validate and live-verify the GitHub binding for a governed P0 human review."""
from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parent.parent
CHALLENGE_SCHEMA = ROOT / "schemas" / "human-review-challenge.schema.json"
BINDING_SCHEMA = ROOT / "schemas" / "human-review-auth-binding.schema.json"
PACKET_SCHEMA = ROOT / "schemas" / "human-review-packet.schema.json"
REAL_CHALLENGE = ROOT / "evals" / "p0-real-screen-review-challenge-20260808.json"
REAL_PACKET = ROOT / "evals" / "p0-real-screen-review-packet-20260808.json"
REAL_SCREEN_RECEIPT = ROOT / "evals" / "p0-real-screen-smoke-receipt-20260808.json"
REAL_BRIEF = ROOT / "evals" / "p0-review-brief-v1.json"


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def canonical_sha(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def text_sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def schema_errors(schema_path: Path, payload: Any) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise RuntimeError("jsonschema_not_available") from exc
    validator = jsonschema.Draft7Validator(load(schema_path), format_checker=jsonschema.FormatChecker())
    return sorted(f"{'/'.join(map(str, e.absolute_path)) or '$'}:{e.message}" for e in validator.iter_errors(payload))


def expected_comment_body(challenge: dict[str, Any], decision: str) -> str:
    return (
        "P0_REVIEW_V1 "
        f"review_id={challenge['review_id']} "
        f"decision={decision} "
        f"visual_sha256={challenge['visual_output_sha256']} "
        f"challenge_sha256={canonical_sha(challenge)} "
        f"nonce={challenge['nonce']} "
        f"resource=issue:{challenge['review_resource_number']} "
        f"role={challenge['reviewer_role']} "
        f"scope={challenge['reviewer_scope']} "
        f"training_ack={challenge['training_ack_code']} "
        f"training_sha256={challenge['training_brief_sha256']}"
    )


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def fetch_comment(api_url: str) -> dict[str, Any]:
    req = urllib.request.Request(api_url, headers={"Accept": "application/vnd.github+json", "User-Agent": "lf-p0-human-binding/1"})
    with urllib.request.urlopen(req, timeout=15) as response:
        if response.status != 200:
            raise RuntimeError(f"github_http_status:{response.status}")
        return json.loads(response.read().decode("utf-8"))


def verify(
    challenge: dict[str, Any],
    decision: str,
    comment: dict[str, Any],
    *,
    now: datetime | None = None,
) -> dict[str, Any]:
    challenge_errors = schema_errors(CHALLENGE_SCHEMA, challenge)
    body = comment.get("body") if isinstance(comment.get("body"), str) else ""
    user = comment.get("user") if isinstance(comment.get("user"), dict) else {}
    expected_body = expected_comment_body(challenge, decision) if not challenge_errors else ""
    current = now or datetime.now(timezone.utc)
    try:
        unexpired = parse_time(challenge.get("issued_at", "")) <= current <= parse_time(challenge.get("expires_at", ""))
    except (TypeError, ValueError):
        unexpired = False
    expected_api_prefix = "https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch/issues/comments/"
    checks = {
        "challenge_schema_invalid": len(challenge_errors),
        "decision_not_allowed": 0 if decision in challenge.get("allowed_decisions", []) else 1,
        "challenge_expired_or_not_yet_valid": 0 if unexpired else 1,
        "reviewer_login_mismatch": 0 if user.get("login") == challenge.get("expected_reviewer_login") else 1,
        "reviewer_external_id_missing": 0 if isinstance(user.get("id"), int) and user.get("id") > 0 else 1,
        "author_association_not_trusted": 0 if comment.get("author_association") in {"OWNER", "MEMBER", "COLLABORATOR"} else 1,
        "comment_body_mismatch": 0 if body == expected_body else 1,
        "comment_resource_mismatch": 0 if comment.get("issue_url") == f"https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch/issues/{challenge.get('review_resource_number')}" else 1,
        "comment_api_url_invalid": 0 if isinstance(comment.get("url"), str) and comment["url"].startswith(expected_api_prefix) else 1,
        "comment_html_url_invalid": 0 if isinstance(comment.get("html_url"), str) and comment["html_url"].startswith("https://github.com/cristhianlujan/claude-persona-lf-patch/") else 1,
        "comment_id_missing": 0 if isinstance(comment.get("id"), int) and comment.get("id") > 0 else 1,
    }
    failed = sorted(key for key, value in checks.items() if value)
    return {
        "result": "LIVE_BINDING_VERIFIED" if not failed else "BLOCKED",
        "blocking_assertions": failed,
        "checks": checks,
        "challenge_sha256": canonical_sha(challenge) if not challenge_errors else None,
        "attested_body_sha256": text_sha(body),
        "comment_id": comment.get("id"),
        "reviewer_login": user.get("login"),
    }


def build_binding(challenge: dict[str, Any], comment: dict[str, Any], verified: dict[str, Any], *, resource_number: int, verified_at: str) -> dict[str, Any]:
    if verified.get("result") != "LIVE_BINDING_VERIFIED":
        raise ValueError("cannot_build_binding_from_unverified_comment")
    if resource_number != challenge.get("review_resource_number"):
        raise ValueError("binding_resource_number_mismatch_challenge")
    user = comment["user"]
    payload = {
        "schema_version": "p0-human-auth-binding/v1",
        "provider": "GITHUB",
        "repository": "cristhianlujan/claude-persona-lf-patch",
        "resource_type": "ISSUE_COMMENT",
        "resource_number": resource_number,
        "comment_id": comment["id"],
        "comment_html_url": comment["html_url"],
        "comment_api_url": comment["url"],
        "reviewer_login": user["login"],
        "reviewer_external_id": user["id"],
        "author_association": comment["author_association"],
        "challenge_sha256": verified["challenge_sha256"],
        "challenge_nonce": challenge["nonce"],
        "attested_body_sha256": verified["attested_body_sha256"],
        "verified_at": verified_at,
        "verification_method": "GITHUB_API_TLS_READBACK",
        "live_verified": True,
    }
    errors = schema_errors(BINDING_SCHEMA, payload)
    if errors:
        raise ValueError("binding_schema_invalid:" + "|".join(errors))
    return payload


def verify_binding_receipt(
    challenge: dict[str, Any],
    decision: str,
    binding: dict[str, Any],
    *,
    fetcher: Callable[[str], dict[str, Any]] = fetch_comment,
    now: datetime | None = None,
) -> dict[str, Any]:
    binding_errors = schema_errors(BINDING_SCHEMA, binding)
    if binding_errors:
        return {"result": "BLOCKED", "blocking_assertions": ["binding_schema_invalid"], "schema_errors": binding_errors}
    try:
        comment = fetcher(binding["comment_api_url"])
    except Exception as exc:
        return {"result": "BLOCKED", "blocking_assertions": ["github_live_readback_failed"], "error": str(exc)}
    live = verify(challenge, decision, comment, now=now)
    user = comment.get("user") if isinstance(comment.get("user"), dict) else {}
    issue_url = comment.get("issue_url") if isinstance(comment.get("issue_url"), str) else ""
    receipt_checks = {
        "binding_challenge_hash_mismatch": 0 if binding.get("challenge_sha256") == live.get("challenge_sha256") else 1,
        "binding_nonce_mismatch": 0 if binding.get("challenge_nonce") == challenge.get("nonce") else 1,
        "binding_body_hash_mismatch": 0 if binding.get("attested_body_sha256") == live.get("attested_body_sha256") else 1,
        "binding_comment_id_mismatch": 0 if binding.get("comment_id") == comment.get("id") else 1,
        "binding_reviewer_login_mismatch": 0 if binding.get("reviewer_login") == user.get("login") else 1,
        "binding_reviewer_external_id_mismatch": 0 if binding.get("reviewer_external_id") == user.get("id") else 1,
        "binding_author_association_mismatch": 0 if binding.get("author_association") == comment.get("author_association") else 1,
        "binding_comment_html_url_mismatch": 0 if binding.get("comment_html_url") == comment.get("html_url") else 1,
        "binding_resource_number_mismatch": 0 if issue_url.endswith(f"/issues/{binding.get('resource_number')}") else 1,
    }
    failed = list(live.get("blocking_assertions") or []) + sorted(key for key, value in receipt_checks.items() if value)
    return {
        "result": "LIVE_BINDING_VERIFIED" if not failed else "BLOCKED",
        "blocking_assertions": sorted(set(failed)),
        "live_checks": live.get("checks", {}),
        "receipt_checks": receipt_checks,
        "comment_id": comment.get("id"),
        "reviewer_login": user.get("login"),
    }


def synthetic_comment(challenge: dict[str, Any], decision: str) -> dict[str, Any]:
    return {
        "id": 987654321,
        "url": "https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch/issues/comments/987654321",
        "html_url": "https://github.com/cristhianlujan/claude-persona-lf-patch/issues/999#issuecomment-987654321",
        "issue_url": "https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch/issues/999",
        "body": expected_comment_body(challenge, decision),
        "user": {"login": challenge["expected_reviewer_login"], "id": 259964988},
        "author_association": "OWNER",
    }


def self_test() -> int:
    challenge = {
        "schema_version": "p0-human-review-challenge/v1", "review_id": "REV-TEST-1", "target_screen_code": "SCR-LOGIN",
        "visual_output_sha256": "d" * 64, "source_raw_sha256": "a" * 64, "expected_reviewer_provider": "GITHUB",
        "expected_reviewer_login": "cristhianlujan", "reviewer_role": "P0_VISUAL_ADJUDICATOR", "reviewer_scope": "LF-SANDBOX",
        "review_resource_type": "ISSUE", "review_resource_number": 999, "review_resource_url": "https://github.com/cristhianlujan/claude-persona-lf-patch/issues/999",
        "training_ack_code": "P0-REVIEW-BRIEF-v1", "training_brief_ref": "p0://review-brief/P0-REVIEW-BRIEF-v1", "training_brief_sha256": "b" * 64,
        "allowed_decisions": ["CONFIRM_OBSERVATION", "REQUEST_NEW_CAPTURE"],
        "nonce": "nonce_TEST_1234567890", "issued_at": "2026-08-08T00:00:00Z", "expires_at": "2026-08-09T00:00:00Z",
    }
    now = datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc)
    good = synthetic_comment(challenge, "CONFIRM_OBSERVATION")
    positive = verify(challenge, "CONFIRM_OBSERVATION", good, now=now)
    binding = build_binding(challenge, good, positive, resource_number=999, verified_at="2026-08-08T12:00:00Z")
    bound_positive = verify_binding_receipt(challenge, "CONFIRM_OBSERVATION", binding, fetcher=lambda _: good, now=now)
    attacks: list[tuple[str, dict[str, Any], str]] = []
    x = json.loads(json.dumps(good)); x["user"]["login"] = "attacker"; attacks.append(("wrong_identity", x, "reviewer_login_mismatch"))
    x = json.loads(json.dumps(good)); x["body"] = x["body"].replace("d" * 64, "e" * 64); attacks.append(("wrong_visual_hash", x, "comment_body_mismatch"))
    x = json.loads(json.dumps(good)); x["body"] = x["body"].replace(challenge["nonce"], "nonce_ATTACK_123456789"); attacks.append(("wrong_nonce", x, "comment_body_mismatch"))
    x = json.loads(json.dumps(good)); x["author_association"] = "NONE"; attacks.append(("untrusted_association", x, "author_association_not_trusted"))
    x = json.loads(json.dumps(good)); x["url"] = "https://evil.invalid/comment/987654321"; attacks.append(("wrong_api_origin", x, "comment_api_url_invalid"))
    results = []
    for name, comment, expected in attacks:
        outcome = verify(challenge, "CONFIRM_OBSERVATION", comment, now=now)
        results.append({"name": name, "passed": outcome["result"] == "BLOCKED" and expected in outcome["blocking_assertions"]})
    expired = verify(challenge, "CONFIRM_OBSERVATION", good, now=datetime(2026, 8, 10, tzinfo=timezone.utc))
    results.append({"name": "expired_challenge", "passed": expired["result"] == "BLOCKED" and "challenge_expired_or_not_yet_valid" in expired["blocking_assertions"]})
    forged_binding = dict(binding); forged_binding["comment_id"] += 1
    forged = verify_binding_receipt(challenge, "CONFIRM_OBSERVATION", forged_binding, fetcher=lambda _: good, now=now)
    results.append({"name": "forged_binding_receipt", "passed": forged["result"] == "BLOCKED" and "binding_comment_id_mismatch" in forged["blocking_assertions"]})
    real_challenge = load(REAL_CHALLENGE)
    real_packet = load(REAL_PACKET)
    real_receipt = load(REAL_SCREEN_RECEIPT)
    real_artifact_checks = {
        "challenge_schema": not schema_errors(CHALLENGE_SCHEMA, real_challenge),
        "packet_schema": not schema_errors(PACKET_SCHEMA, real_packet),
        "review_id_match": real_challenge.get("review_id") == real_packet.get("review_id"),
        "visual_hash_match": real_challenge.get("visual_output_sha256") == real_packet.get("visual_output_sha256") == real_receipt.get("visual_reader", {}).get("canonical_visual_output_sha256"),
        "source_hash_match": real_challenge.get("source_raw_sha256") == real_receipt.get("admission", {}).get("raw_bytes_sha256"),
        "challenge_window_ordered": parse_time(real_challenge["issued_at"]) < parse_time(real_challenge["expires_at"]),
        "reviewer_identity_expected": real_challenge.get("expected_reviewer_login") == "cristhianlujan",
        "review_brief_hash_match": real_challenge.get("training_brief_sha256") == hashlib.sha256(REAL_BRIEF.read_bytes()).hexdigest(),
        "review_brief_code_match": real_challenge.get("training_ack_code") == load(REAL_BRIEF).get("brief_code"),
    }
    passed = positive["result"] == "LIVE_BINDING_VERIFIED" and bound_positive["result"] == "LIVE_BINDING_VERIFIED" and all(row["passed"] for row in results) and all(real_artifact_checks.values())
    print(json.dumps({"positive_live_binding": positive["result"] == "LIVE_BINDING_VERIFIED", "positive_receipt_revalidation": bound_positive["result"] == "LIVE_BINDING_VERIFIED", "negative_cases_passed": sum(row["passed"] for row in results), "negative_cases_total": len(results), "negative_results": results, "real_review_artifact_checks": real_artifact_checks, "real_review_artifacts_contract_ready": all(real_artifact_checks.values()), "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--challenge", type=Path)
    parser.add_argument("--decision")
    parser.add_argument("--comment-api-url")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.challenge or not args.decision or not args.comment_api_url:
        parser.error("--challenge, --decision and --comment-api-url are required")
    challenge = load(args.challenge)
    try:
        comment = fetch_comment(args.comment_api_url)
        result = verify(challenge, args.decision, comment)
    except Exception as exc:
        print(json.dumps({"result": "BLOCKED", "blocking_assertions": ["github_live_readback_failed"], "error": str(exc)}, sort_keys=True))
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "LIVE_BINDING_VERIFIED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
