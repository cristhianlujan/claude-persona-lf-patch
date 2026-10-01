#!/usr/bin/env python3
from __future__ import annotations
import copy
from runtime_deploy_verification_v1 import (
    evaluate_runtime_deploy_verification,
    observation_digest,
    receipt_digest,
    scope_digest,
)

SHA = "a" * 40
H1 = "1" * 64
H2 = "2" * 64


def mk_request():
    return {
        "capability_code": "RUNTIME_DEPLOY_VERIFICATION",
        "orchestrator_execution_id": "orch-1",
        "consumer_execution_id": "post-1",
        "plan_digest": "plan-1",
        "dispatch_receipt_id": "dispatch-1",
        "request_digest": "req-1",
        "source_revision": SHA,
        "entry_guard_readback": {"decision": "ORCHESTRATOR_ENTRY_ACCEPTED"},
    }


def mk_scope():
    s = {
        "schema_version": "LF_RUNTIME_DEPLOY_VERIFICATION_SCOPE_V1",
        "plan_digest": "plan-1",
        "source_revision": SHA,
        "target": {"target_type": "PERFIL", "target_code": "PROFILE_X"},
        "deployment": {
            "effect_operation_code": "REFRESCO_RUNTIME_PERFIL_LF",
            "deployment_execution_id": "deploy-1",
            "expected_source_sha": SHA,
            "expected_release_ref": "/opt/lf-profile-runtime-api/releases/" + SHA,
            "required_files": [
                {"path": "services/profile_runtime_api/app.py", "sha256": H1},
                {"path": "sandbox/lf_contract_gate_test/profile_x.py", "sha256": H2},
            ],
        },
        "expected_preserved_state": {
            "runtime_estado": "CANDIDATE_READ_ONLY",
            "estado_operativo": "READ_ONLY",
            "impacto_automatico": "BLOQUEADO",
        },
    }
    s["scope_digest"] = scope_digest(s)
    return s


def mk_deploy_receipt():
    r = {
        "schema_version": "LF_RUNTIME_DEPLOY_EFFECT_RECEIPT_V1",
        "effect_operation_code": "REFRESCO_RUNTIME_PERFIL_LF",
        "deployment_execution_id": "deploy-1",
        "target_code": "PROFILE_X",
        "source_sha": SHA,
        "release_ref": "/opt/lf-profile-runtime-api/releases/" + SHA,
        "effect_applied": True,
        "install_exit_zero": True,
    }
    r["receipt_digest"] = receipt_digest(r)
    return r


def seal(row):
    row["receipt_digest"] = observation_digest(row)
    return row


def mk_manifest():
    return seal({
        "schema_version": "LF_RUNTIME_DEPLOY_MANIFEST_OBSERVATION_V1",
        "read_only": True,
        "mutation_performed": False,
        "files": [
            {"path": "services/profile_runtime_api/app.py", "sha256": H1},
            {"path": "sandbox/lf_contract_gate_test/profile_x.py", "sha256": H2},
        ],
    })


def mk_health():
    return seal({
        "schema_version": "LF_RUNTIME_DEPLOY_HEALTH_OBSERVATION_V1",
        "read_only": True,
        "mutation_performed": False,
        "service_active": True,
        "health_ok": True,
        "runtime_endpoint_source_sha": SHA,
    })


def mk_state():
    return seal({
        "schema_version": "LF_RUNTIME_DEPLOY_STATE_OBSERVATION_V1",
        "read_only": True,
        "mutation_performed": False,
        "current_state": {
            "runtime_estado": "CANDIDATE_READ_ONLY",
            "estado_operativo": "READ_ONLY",
            "impacto_automatico": "BLOQUEADO",
        },
        "automatic_promotion_observed": False,
    })


def run(req=None, scope=None, deploy=None, manifest=None, health=None, state=None):
    return evaluate_runtime_deploy_verification(
        request=req or mk_request(),
        scope=scope or mk_scope(),
        deployment_receipt=deploy or mk_deploy_receipt(),
        manifest_observation=manifest or mk_manifest(),
        health_observation=health or mk_health(),
        state_observation=state or mk_state(),
    )

checks = 0
r=run(); assert r["ready"] and r["decision"]=="VERIFICATION_VERIFIED"; checks+=1
x=mk_request(); x["entry_guard_readback"]={"decision":"BLOCKED"}; assert not run(req=x)["ready"]; checks+=1
x=mk_scope(); x["scope_digest"]="0"*64; assert not run(scope=x)["ready"]; checks+=1
x=mk_scope(); x["deployment"]["required_files"].append(copy.deepcopy(x["deployment"]["required_files"][0])); x["scope_digest"]=scope_digest(x); assert not run(scope=x)["ready"]; checks+=1
x=mk_scope(); x["deployment"]["required_files"][0]["path"]="../bad"; x["scope_digest"]=scope_digest(x); assert not run(scope=x)["ready"]; checks+=1
x=mk_deploy_receipt(); x["effect_operation_code"]="OTHER"; x["receipt_digest"]=receipt_digest(x); assert not run(deploy=x)["ready"]; checks+=1
x=mk_deploy_receipt(); x["target_code"]="OTHER"; x["receipt_digest"]=receipt_digest(x); assert not run(deploy=x)["ready"]; checks+=1
x=mk_deploy_receipt(); x["source_sha"]="b"*40; x["receipt_digest"]=receipt_digest(x); assert not run(deploy=x)["ready"]; checks+=1
x=mk_deploy_receipt(); x["install_exit_zero"]=False; x["receipt_digest"]=receipt_digest(x); assert not run(deploy=x)["ready"]; checks+=1
x=mk_deploy_receipt(); x["receipt_digest"]="f"*64; assert not run(deploy=x)["ready"]; checks+=1
x=mk_manifest(); x["files"]=x["files"][:1]; x["receipt_digest"]=observation_digest(x); assert not run(manifest=x)["ready"]; checks+=1
x=mk_manifest(); x["files"].append({"path":"extra.txt","sha256":"3"*64}); x["receipt_digest"]=observation_digest(x); assert not run(manifest=x)["ready"]; checks+=1
x=mk_manifest(); x["files"][0]["sha256"]="4"*64; x["receipt_digest"]=observation_digest(x); assert not run(manifest=x)["ready"]; checks+=1
x=mk_manifest(); x["read_only"]=False; x["receipt_digest"]=observation_digest(x); assert not run(manifest=x)["ready"]; checks+=1
x=mk_health(); x["health_ok"]=False; x["receipt_digest"]=observation_digest(x); assert not run(health=x)["ready"]; checks+=1
x=mk_health(); x["runtime_endpoint_source_sha"]="b"*40; x["receipt_digest"]=observation_digest(x); assert not run(health=x)["ready"]; checks+=1
x=mk_state(); x["current_state"]["runtime_estado"]="ACTIVE"; x["receipt_digest"]=observation_digest(x); assert not run(state=x)["ready"]; checks+=1
x=mk_state(); x["promotion"]="BAD"; x["receipt_digest"]=observation_digest(x); assert not run(state=x)["ready"]; checks+=1
x=mk_state(); x["mutation_performed"]=True; x["receipt_digest"]=observation_digest(x); assert not run(state=x)["ready"]; checks+=1
print(f"PASS_RUNTIME_DEPLOY_VERIFICATION_V1 checks={checks}")
