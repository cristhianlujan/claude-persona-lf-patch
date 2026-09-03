from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "contracts/update_revision_continuity_contract.json"
CALLER = ROOT.parents[1] / "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts"
RUNTIME = ROOT.parents[1] / "supabase/functions/run-creacion-perfil-lf/index.ts"

contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
caller = CALLER.read_text(encoding="utf-8")
runtime = RUNTIME.read_text(encoding="utf-8")
clean = contract["deterministic_decision"]["clean_path"]
stale = contract["deterministic_decision"]["stale_path"]
forbidden = contract["deterministic_decision"]["forbidden"]
blocking = set(contract["blocking_codes"])
required_blocking = {"PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED","PROFILE_UPDATE_BASELINE_REVISION_INVALID","PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED","PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED","PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED","PROFILE_UPDATE_STALE_REREAD_REQUIRED","PROFILE_UPDATE_STALE_REBIND_REQUIRED","PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH","PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"}
checks = {
 "update_scope": contract.get("operation_code") == "ACTUALIZACION_PERFIL_LF",
 "prewrite_reused": contract.get("step_id") == "pre_write_execution_binding_gate",
 "no_new_architecture": all(contract.get("architecture", {}).get(k) is False for k in ["new_layer","new_table","new_step"]),
 "existing_jsonb_reused": contract.get("architecture", {}).get("reuse_execution_steps_jsonb") is True,
 "persisted_baseline_source": contract.get("trusted_inputs", {}).get("baseline", {}).get("source") == "lf_operation_execution_steps.baseline_read.evidence_payload",
 "baseline_not_caller_authority": contract.get("trusted_inputs", {}).get("baseline", {}).get("caller_declaration_is_authority") is False,
 "github_current_source": contract.get("trusted_inputs", {}).get("current", {}).get("source") == "GITHUB_PUBLIC_API_EXACT_REF_V1",
 "current_not_caller_authority": contract.get("trusted_inputs", {}).get("current", {}).get("caller_declaration_is_authority") is False,
 "clean_requires_three_way_continuity": len(clean) == 3 and any("baseline_revision == trusted_current_revision.revision_sha" in x for x in clean) and any("bound_revision.revision_sha == trusted_current_revision.revision_sha" in x for x in clean),
 "stale_requires_reread_rebind": all(any(token in x for x in stale) for token in ["reread_performed == true","rebind_performed == true","rebound_from_revision == baseline_revision"]),
 "free_text_forbidden": any("free_text_write_plan" in x for x in forbidden),
 "semantic_override_forbidden": any("semantic_pass_overrides_revision_mismatch" in x for x in forbidden),
 "blocking_complete": blocking == required_blocking,
 "snapshot_extension_source_bound": contract.get("required_runtime_snapshot_extension", {}).get("derived_from_persisted_step") == "baseline_read",
 "snapshot_override_forbidden": contract.get("required_runtime_snapshot_extension", {}).get("must_not_accept_request_payload_override") is True,
 "runtime_reads_persisted_payload": "select=step_order,step_id,status,evidence_ref,evidence_payload,observed_at" in runtime,
 "runtime_derives_baseline_observation": "function baselineObservation" in runtime and 'step_id === "baseline_read"' in runtime and "baseline_revision: baselineRevision" in runtime,
 "runtime_exposes_baseline_observation": 'baseline_observation: op === "ACTUALIZACION_PERFIL_LF" ? baselineObservation(recorded) : null' in runtime,
 "caller_has_independent_current_resolver": "resolveTrustedCurrentRevision" in caller and "GITHUB_PUBLIC_API_EXACT_REF_V1" in caller,
 "caller_ignores_declared_current": "declared_current_revision_ignored" in caller,
 "caller_structured_bound_revision": "boundRevisionSha" in caller and "PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED" in caller,
 "update_runtime_still_fail_closed": "UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED" in runtime,
 "contract_does_not_authorize_runtime": contract.get("activation", {}).get("update_recorder_enabled") is False and contract.get("activation", {}).get("runtime_deployment_authorized") is False,
}
failed=[name for name,ok in checks.items() if not ok]
if failed: raise SystemExit("FAIL_UPDATE_REVISION_CONTINUITY_CONTRACT:"+",".join(failed))
print(f"PASS_UPDATE_REVISION_CONTINUITY_CONTRACT={sum(checks.values())}/{len(checks)}")
print("RUNTIME_BASELINE_OBSERVATION_MATERIALIZED=true")
print("UPDATE_WRITE_ENABLED=false")
