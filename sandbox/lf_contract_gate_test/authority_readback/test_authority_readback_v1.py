#!/usr/bin/env python3
from __future__ import annotations
import copy
from authority_readback_v1 import (
    canonical_sha256,
    currentness_digest,
    evaluate_authority_readback,
    observation_digest,
    scope_digest,
)

SHA = "a" * 40
PLAN = "plan-digest-1"

def mk_request():
    return {
        "capability_code": "AUTHORITY_READBACK",
        "orchestrator_execution_id": "orch-1",
        "consumer_execution_id": "post-1",
        "plan_digest": PLAN,
        "dispatch_receipt_id": "dispatch-1",
        "request_digest": "req-1",
        "source_revision": SHA,
        "entry_guard_readback": {"decision": "ORCHESTRATOR_ENTRY_ACCEPTED"},
    }

def mk_scope():
    x = {
        "schema_version": "LF_AUTHORITY_READBACK_SCOPE_V1",
        "plan_digest": PLAN,
        "source_revision": SHA,
        "target": {"target_type": "PERFIL", "target_code": "PROFILE_X"},
        "checks": [
            {
                "check_id": "source",
                "adapter_code": "PROFILE_GITHUB_SOURCE_READBACK",
                "subject_ref": "github://repo/path",
                "authority_ref": "GITHUB_MAIN",
                "expected_source_revision": SHA,
                "currentness_required": True,
            },
            {
                "check_id": "control",
                "adapter_code": "SUPABASE_CONTROL_PLANE_READBACK",
                "subject_ref": "supabase://control/profile_x",
                "authority_ref": "SUPABASE_CONTROL_PLANE",
                "expected_source_revision": SHA,
                "currentness_required": False,
            },
        ],
    }
    x["scope_digest"] = scope_digest(x)
    return x

def mk_currentness():
    r = {
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": "CURRENT",
        "ready": True,
        "evidence_revision": SHA,
        "bound_revision": SHA,
        "current_revision": SHA,
    }
    r["receipt_sha256"] = currentness_digest(r)
    return r

def mk_obs():
    rows = [
        {
            "schema_version": "LF_AUTHORITY_ADAPTER_OBSERVATION_V1",
            "check_id": "source",
            "adapter_code": "PROFILE_GITHUB_SOURCE_READBACK",
            "subject_ref": "github://repo/path",
            "authority_ref": "GITHUB_MAIN",
            "source_revision": SHA,
            "decision": "AUTHORITY_MATCH",
            "read_only": True,
            "mutation_performed": False,
            "evidence_refs": ["github://repo/path@" + SHA],
            "currentness_receipt": mk_currentness(),
        },
        {
            "schema_version": "LF_AUTHORITY_ADAPTER_OBSERVATION_V1",
            "check_id": "control",
            "adapter_code": "SUPABASE_CONTROL_PLANE_READBACK",
            "subject_ref": "supabase://control/profile_x",
            "authority_ref": "SUPABASE_CONTROL_PLANE",
            "source_revision": SHA,
            "decision": "AUTHORITY_MATCH",
            "read_only": True,
            "mutation_performed": False,
            "evidence_refs": ["supabase://control/profile_x"],
        },
    ]
    for row in rows:
        row["receipt_digest"] = observation_digest(row)
    return rows

def run(req=None, scope=None, obs=None):
    return evaluate_authority_readback(
        request=req or mk_request(),
        scope=scope or mk_scope(),
        observations=obs if obs is not None else mk_obs(),
    )

checks = 0
r = run(); assert r["ready"] and r["decision"] == "READBACK_VERIFIED"; checks += 1

x=mk_request(); x["entry_guard_readback"]={"decision":"BLOCKED"}; assert not run(req=x)["ready"]; checks+=1
x=mk_scope(); x["scope_digest"]="0"*64; assert not run(scope=x)["ready"]; checks+=1
x=mk_scope(); x["checks"].append(copy.deepcopy(x["checks"][0])); x["scope_digest"]=scope_digest(x); assert not run(scope=x)["ready"]; checks+=1

x=mk_obs()[:1]; assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); y=copy.deepcopy(x[0]); y["check_id"]="extra"; y["receipt_digest"]=observation_digest(y); x.append(y); assert not run(obs=x)["ready"]; checks+=1

x=mk_obs(); x[0]["adapter_code"]="OTHER"; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["read_only"]=False; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["mutation_performed"]=True; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["next_gate"]="BAD"; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["decision"]="AUTHORITY_MISMATCH"; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1

x=mk_obs(); x[0]["currentness_receipt"]["ready"]=False; x[0]["currentness_receipt"]["receipt_sha256"]=currentness_digest(x[0]["currentness_receipt"]); x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["currentness_receipt"]["current_revision"]="b"*40; x[0]["currentness_receipt"]["receipt_sha256"]=currentness_digest(x[0]["currentness_receipt"]); x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["currentness_receipt"]["receipt_sha256"]="f"*64; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["receipt_digest"]="e"*64; assert not run(obs=x)["ready"]; checks+=1
x=mk_obs(); x[0]["source_revision"]="b"*40; x[0]["receipt_digest"]=observation_digest(x[0]); assert not run(obs=x)["ready"]; checks+=1

print(f"PASS_AUTHORITY_READBACK_V1 checks={checks}")
