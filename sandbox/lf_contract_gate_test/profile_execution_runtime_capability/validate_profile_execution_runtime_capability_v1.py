import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "profile_execution_runtime_capability_v1.json"


def validate(payload: dict) -> list[str]:
    errors: list[str] = []
    if payload.get("schema_version") != "LF_PROFILE_EXECUTION_RUNTIME_CAPABILITY_V1":
        errors.append("SCHEMA_VERSION")
    if payload.get("capability_code") != "PROFILE_EXECUTION_RUNTIME":
        errors.append("CAPABILITY_CODE")
    if payload.get("status") != "CANDIDATE_READ_ONLY":
        errors.append("STATUS")
    if payload.get("administrative_owner") != "LF_GOVERNANCE":
        errors.append("OWNER")

    impl = payload.get("implementation") or {}
    if impl.get("operation_code") != "EJECUCION_PERFIL_LF":
        errors.append("IMPLEMENTATION_OPERATION")
    if impl.get("begin_rpc") != "public.lf_profile_execution_begin_v1":
        errors.append("BEGIN_RPC")
    if impl.get("queue") != "private.lf_profile_runtime_queue_v1":
        errors.append("QUEUE")
    if impl.get("existing_runtime_only") is not True:
        errors.append("EXISTING_RUNTIME_ONLY")

    entry = payload.get("entry_contract") or {}
    if entry.get("required") is not True:
        errors.append("ENTRY_REQUIRED")
    if entry.get("guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        errors.append("GUARD_CODE")
    if entry.get("dispatch_rpc") != "public.fn_lf_orchestrator_dispatch_receipt_v1":
        errors.append("DISPATCH_RPC")
    if entry.get("guard_rpc") != "public.fn_lf_capability_orchestrator_entry_guard_v1":
        errors.append("GUARD_RPC")
    if entry.get("binding_entrypoint") != "public.fn_lf_capability_bind_from_orchestrator_v1":
        errors.append("BINDING_ENTRYPOINT")
    if entry.get("direct_or_unorchestrated_call_policy") != "BLOCK":
        errors.append("DIRECT_CALL_POLICY")

    invariants = payload.get("invariants") or {}
    for key in (
        "new_runtime_engine",
        "new_operation",
        "new_queue",
        "new_profile_registry",
        "new_receipt_store",
        "new_evidence_ledger",
        "runtime_activation_by_registration",
        "production_activation_by_registration",
    ):
        if invariants.get(key) is not False:
            errors.append(f"INVARIANT_{key.upper()}")
    if invariants.get("profile_execution_operation_must_equal") != "EJECUCION_PERFIL_LF":
        errors.append("OPERATION_INVARIANT")
    for key in ("router_must_allow_downstream", "currentness_required", "orchestrator_receipt_required"):
        if invariants.get(key) is not True:
            errors.append(f"INVARIANT_{key.upper()}")

    materialization = payload.get("materialization") or {}
    for key in (
        "registry_projection_in_this_solution",
        "current_pointer_in_this_solution",
        "supabase_apply_in_this_solution",
        "runtime_cutover_in_this_solution",
    ):
        if materialization.get(key) is not False:
            errors.append(f"MATERIALIZATION_{key.upper()}")

    blockers = payload.get("known_blockers_before_cutover")
    if not isinstance(blockers, list) or len(blockers) < 3 or any(not isinstance(v, str) or not v.strip() for v in blockers):
        errors.append("KNOWN_BLOCKERS")
    return errors


def main() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    errors = validate(payload)
    if errors:
        raise SystemExit("FAIL_PROFILE_EXECUTION_RUNTIME_CAPABILITY_V1:" + ",".join(errors))
    print("PASS_PROFILE_EXECUTION_RUNTIME_CAPABILITY_V1 checks=26")


if __name__ == "__main__":
    main()
