"""Permission, tenant and idempotency coverage. J06 support."""
import sys

from lf_common import argv_path, emit, load

MUTATION_VERBS = ("CREATE", "UPDATE", "DELETE", "APPROVE", "REJECT", "SUBMIT")


def main():
    pack = load(argv_path(1))
    sec = pack.get("security_privacy", {})
    failed = []
    if not sec.get("required_permissions"):
        failed.append("stories_without_required_permission=1")
    if not sec.get("tenant_key"):
        failed.append("tenant_key_missing=1")
    if sec.get("cross_tenant_policy") not in ("DENY", "EXPLICIT_ALLOW_WITH_AUDIT"):
        failed.append("cross_tenant_access_allowed=1")
    action = str(pack.get("core", {}).get("trigger", "")).upper()
    is_mutation = any(v in action for v in MUTATION_VERBS)
    if is_mutation and not sec.get("server_side_enforcement"):
        failed.append("mutations_without_server_side_authorization=1")
    if is_mutation and sec.get("idempotency_required") is None:
        failed.append("mutation_without_idempotency_decision=1")
    if sec.get("signed_url_policy") and not sec.get("signed_url_ttl_seconds"):
        failed.append("signed_url_without_ttl=1")
    if sec.get("critical_action") and sec.get("mfa_required") is None:
        failed.append("critical_action_without_mfa_decision=1")
    evidence = {
        "is_mutation": is_mutation,
        "required_permissions": sec.get("required_permissions", []),
        "cross_tenant_policy": sec.get("cross_tenant_policy"),
        "rls_required": sec.get("rls_required"),
    }
    return emit("J06_SECURITY_PRIVACY", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
