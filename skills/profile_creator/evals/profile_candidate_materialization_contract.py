#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "contracts/profile_candidate_materialization_v1.sql").read_text(encoding="utf-8")
CONTRACT = json.loads((ROOT / "contracts/profile_candidate_materialization_v1.json").read_text(encoding="utf-8"))


def require(token: str) -> None:
    assert token in SQL, token


def forbid(token: str) -> None:
    assert token not in SQL, token


assert CONTRACT["status"] == "SOURCE_ONLY_NOT_DEPLOYED"
assert CONTRACT["owner_strategy"] == "S22"
assert CONTRACT["owner_operation"] == "CREACION_PERFIL_LF"
assert CONTRACT["architecture"]["new_operation"] is False
assert CONTRACT["architecture"]["new_table"] is False
assert CONTRACT["activation_guard"]["live_apply"] is False
assert CONTRACT["activation_guard"]["migration_identity_reserved"] is False
assert CONTRACT["activation_guard"]["governance_mutation_route_ready"] is False
assert CONTRACT["required_sequence"] == [
    "github_write",
    "github_readback",
    "candidate_materialize",
    "asset_readback",
    "contract_judge",
    "close",
]

for token in [
    "operation_code<>'CREACION_PERFIL_LF'",
    "target_type<>'PERFIL'",
    "v_exec.status<>'IN_PROGRESS'",
    "step_id='github_readback'",
    "status='ACTIVE_ENFORCEMENT'",
    "sha_match_status','')<>'PASS'",
    "v_repo<>v_exec.target_repo",
    "LF_PROFILE_CANDIDATE_ENTRYPOINT_NOT_READBACK",
    "LF_PROFILE_CANDIDATE_ALREADY_REGISTERED",
    "'CANDIDATO','READ_ONLY','PROFILE_REGISTRY','NO_HABILITADO','BLOQUEADO'",
    "'registry_source','SUPABASE'",
    "'runtime_enabled',false",
    "'automatic_impact_enabled',false",
    "'github_role','TECHNICAL_IMPLEMENTATION_ARTIFACT'",
    "'github_is_authority',false",
    "created_by_execution_id,updated_by_execution_id",
]:
    require(token)

for token in [
    "RUNTIME_OPERATIVO",
    "PERMITIDO_CONTROLADO",
    "APROBADO_PRODUCCION",
    "insert into public.lf_operation_steps",
    "insert into public.lf_operation_judges",
    "insert into public.lf_operation_step_judge_bindings",
    "insert into public.lf_operation_step_contracts",
]:
    forbid(token)

assert len(CONTRACT["negative_cases"]) >= 8
assert CONTRACT["candidate_materialize"]["insert_tuple"] == {
    "estado_original": "CANDIDATE_READ_ONLY",
    "estado_documental": "CANDIDATO",
    "estado_operativo": "READ_ONLY",
    "nivel_control": "PROFILE_REGISTRY",
    "runtime_estado": "NO_HABILITADO",
    "impacto_automatico": "BLOQUEADO",
    "url_scheme": "supabase://public/lf_activos/<codigo_activo>",
    "registry_source": "SUPABASE",
    "runtime_enabled": False,
    "automatic_impact_enabled": False,
}
assert CONTRACT["canary"]["rollback_insert_test"] == "PASS_NO_RESIDUE"

print("PASS_PROFILE_CANDIDATE_MATERIALIZATION_CONTRACT")
