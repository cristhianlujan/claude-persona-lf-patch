"""Validate permission, tenant, storage, MFA and idempotency decisions for J06."""
from __future__ import annotations

from lf_common import (
    add_common_input, emit, failure, load_json, main_guard, parser,
    require_object, result_object,
)

JUDGE = "J06_SECURITY_PRIVACY"
MUTATION_TERMS = ("CREATE", "UPDATE", "DELETE", "APPROVE", "REJECT", "SUBMIT", "SAVE", "EDIT")


def run() -> int:
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")
    sec = pack.get("security_privacy")
    if not isinstance(sec, dict):
        sec = {}

    text = " ".join([
        str(pack.get("core", {}).get("trigger", "")),
        " ".join(pack.get("core", {}).get("main_flow", []) if isinstance(pack.get("core", {}).get("main_flow"), list) else []),
    ]).upper()
    is_mutation = any(term in text for term in MUTATION_TERMS)
    sensitive_download = any(
        term in text for term in ("DOWNLOAD", "DESCARG", "EXPORT")
    ) and any(
        isinstance(field, dict)
        and field.get("pii_classification") in {"PII_DIRECT", "PII_SENSITIVE", "PII_FINANCIAL"}
        for field in pack.get("fields", [])
    )

    failures = {}
    if not sec.get("required_permissions"):
        failures["stories_without_required_permission"] = "Declare at least one source-backed permission."
    if not sec.get("tenant_key"):
        failures["tenant_key_missing"] = "Define the server-side tenant key."
    if sec.get("cross_tenant_policy") not in {"DENY", "EXPLICIT_ALLOW_WITH_AUDIT"}:
        failures["cross_tenant_access_allowed"] = "Use DENY or EXPLICIT_ALLOW_WITH_AUDIT."
    if sec.get("server_side_enforcement") is not True:
        failures["missing_server_side_enforcement"] = "Enforcement must be explicit and server-side."
    if is_mutation and sec.get("idempotency_required") is None:
        failures["mutation_without_idempotency_decision"] = "Record an explicit idempotency decision."
    if is_mutation and not sec.get("required_permissions"):
        failures["mutations_without_server_side_authorization"] = "Bind mutation to a permission."
    if sec.get("mfa_required") is None:
        failures["critical_action_without_mfa_decision"] = "Record explicit MFA/step-up decision."
    if sensitive_download and sec.get("storage_policy") != "PRIVATE":
        failures["sensitive_download_without_private_storage"] = "Use private storage."
    if sensitive_download and (
        not sec.get("signed_url_policy") or not sec.get("signed_url_ttl_seconds")
    ):
        failures["signed_url_without_ttl"] = "Define signed URL policy and positive TTL."

    failed = [f"{key}=1" for key in sorted(failures)]
    repairs = [failure(key, "security_privacy", instruction) for key, instruction in failures.items()]
    evidence = {
        "is_mutation": is_mutation,
        "sensitive_download": sensitive_download,
        "required_permissions": sec.get("required_permissions", []),
        "tenant_key": sec.get("tenant_key"),
        "cross_tenant_policy": sec.get("cross_tenant_policy"),
        "server_side_enforcement": sec.get("server_side_enforcement"),
        "mfa_required": sec.get("mfa_required"),
        "idempotency_required": sec.get("idempotency_required"),
        "storage_policy": sec.get("storage_policy"),
        "input_path": str(args.input),
    }
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"],
        repairs, retry_count=args.retry_count,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
