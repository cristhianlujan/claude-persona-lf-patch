"""Validate the nine J06 security and privacy assertions."""
from __future__ import annotations

from lf_common import (
    add_common_input,
    emit,
    failure,
    load_json,
    main_guard,
    parser,
    require_object,
    result_object,
    utc_now,
)

JUDGE = "J06_SECURITY_PRIVACY"
MUTATION_TERMS = ("CREATE", "UPDATE", "DELETE", "APPROVE", "REJECT", "SUBMIT", "SAVE", "EDIT")
PII = {"PII_INDIRECT", "PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}


def evaluate(pack: dict) -> tuple[list[str], list[dict], dict]:
    sec_raw = pack.get("security_privacy")
    sec = sec_raw if isinstance(sec_raw, dict) else {}
    core = pack.get("core") if isinstance(pack.get("core"), dict) else {}
    flow = core.get("main_flow") if isinstance(core.get("main_flow"), list) else []
    text = " ".join([str(core.get("trigger", "")), *map(str, flow)]).upper()
    is_mutation = any(term in text for term in MUTATION_TERMS)
    sensitive_fields = [
        item for item in pack.get("fields", [])
        if isinstance(item, dict) and item.get("pii_classification") in PII
    ]
    sensitive_download = any(term in text for term in ("DOWNLOAD", "DESCARG", "EXPORT")) and bool(sensitive_fields)
    critical_action = is_mutation or sensitive_download

    checks = {
        "stories_without_required_permission": [] if sec.get("required_permissions") else ["security_privacy"],
        "mutations_without_server_authorization": [] if (
            not is_mutation
            or (bool(sec.get("required_permissions")) and sec.get("server_side_enforcement") is True)
        ) else ["security_privacy"],
        "cross_tenant_access": [] if sec.get("cross_tenant_policy") in {
            "DENY", "EXPLICIT_ALLOW_WITH_AUDIT"
        } else ["security_privacy"],
        "tenant_key_missing": [] if sec.get("tenant_key") else ["security_privacy"],
        "sensitive_download_storage": [] if (
            not sensitive_download or sec.get("storage_policy") == "PRIVATE"
        ) else ["security_privacy"],
        "signed_url_ttl": [] if (
            not sensitive_download
            or (
                bool(sec.get("signed_url_policy"))
                and isinstance(sec.get("signed_url_ttl_seconds"), int)
                and not isinstance(sec.get("signed_url_ttl_seconds"), bool)
                and sec.get("signed_url_ttl_seconds") > 0
            )
        ) else ["security_privacy"],
        "critical_action_mfa": [] if (
            not critical_action or isinstance(sec.get("mfa_required"), bool)
        ) else ["security_privacy"],
        "mutation_idempotency": [] if (
            not is_mutation or isinstance(sec.get("idempotency_required"), bool)
        ) else ["security_privacy"],
        "pii_exposure": sorted(
            item.get("field_code", "<missing>") for item in sensitive_fields
            if item.get("visibility_mode") != "HIDDEN" and not item.get("masking_rule")
        ),
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "security_privacy" if key != "pii_exposure" else "fields", f"Repair findings: {values}")
        for key, values in checks.items() if values
    ]
    evidence = {
        "permission_count": len(sec.get("required_permissions", [])) if isinstance(sec.get("required_permissions"), list) else 0,
        "mutation_count": 1 if is_mutation else 0,
        "tenant_rule_count": 1 if sec.get("tenant_key") and sec.get("cross_tenant_policy") else 0,
        "sensitive_download_count": 1 if sensitive_download else 0,
        "pii_field_count": len(sensitive_fields),
        "checks": checks,
    }
    return sorted(failed), repairs, evidence


def run() -> int:
    started_at = utc_now()
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--judge-version")
    cli.add_argument("--executor-identity")
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")
    failed, repairs, evidence = evaluate(pack)
    evidence["input_path"] = str(args.input)
    return emit(result_object(
        JUDGE,
        failed,
        evidence,
        args.evidence_ref or [f"file:{args.input}"],
        repairs,
        retry_count=args.retry_count,
        judge_version=args.judge_version,
        executor_identity=args.executor_identity,
        started_at=started_at,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
