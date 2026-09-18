from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CALLER = (ROOT / "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts").read_text(encoding="utf-8")
RUNTIME = (ROOT / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8")

checks = {
    "caller_requires_structured_bound_revision": "revisionSha(evidencePayload.bound_revision)" in CALLER,
    "caller_normalizes_transport_to_sha40": "bound_revision: boundSha" in CALLER,
    "runtime_consumes_sha40_string": 'typeof evidence.bound_revision === "string"' in RUNTIME,
    "runtime_derives_server_trust": 'server_trust_context_source: "run-creacion-perfil-lf"' in RUNTIME,
    "runtime_strips_caller_trust_fields": "stripCallerTrust(evidence)" in RUNTIME,
    "no_new_operation_or_table": "create table" not in CALLER.lower() and "create or replace function" not in CALLER.lower(),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL_PROFILE_CREATOR_BOUND_REVISION_TRANSPORT:" + ",".join(failed))
print(f"PASS_PROFILE_CREATOR_BOUND_REVISION_TRANSPORT={sum(checks.values())}/{len(checks)}")
