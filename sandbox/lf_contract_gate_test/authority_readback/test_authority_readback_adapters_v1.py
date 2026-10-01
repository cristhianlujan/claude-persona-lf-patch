#!/usr/bin/env python3
from __future__ import annotations
from copy import deepcopy

from authority_readback_v1 import observation_digest
from authority_readback_adapters_v1 import (
    control_system_qualification_observation,
    profile_update_readonly_observation,
    profile_runtime_refresh_readonly_observation,
)

SHA="a"*40

def check_row(code, authority="AUTH", rev=SHA):
    return {
        "check_id":"c1",
        "adapter_code":code,
        "subject_ref":"subject://1",
        "authority_ref":authority,
        "expected_source_revision":rev,
        "currentness_required":False,
    }

def assert_valid_observation(row, expected_decision):
    assert row["schema_version"]=="LF_AUTHORITY_ADAPTER_OBSERVATION_V1"
    assert row["decision"]==expected_decision
    assert row["read_only"] is True
    assert row["mutation_performed"] is False
    assert "next_gate" not in row
    assert "post_merge_next_gate" not in row
    assert row["receipt_digest"]==observation_digest(row)

checks=0

c=check_row("CONTROL_SYSTEM_QUALIFICATION_READBACK","PASE_CONTROL_QUALIFICATION_V1")
identity={"candidate_id":"C1","repository":"org/repo","base_sha":"1"*40,"head_sha":"2"*40}
raw={
  "status":"QUALIFIED","candidate_id":"C1","repository":"org/repo","base_sha":"1"*40,"head_sha":"2"*40,
  "qualification_authority":"PASE_CONTROL_QUALIFICATION_V1","qualification_id":"Q1","source_execution_id":"E1"
}
row=control_system_qualification_observation(check=c,raw_readback=raw,expected_identity=identity)
assert_valid_observation(row,"AUTHORITY_MATCH"); checks+=1

bad=deepcopy(raw); bad["head_sha"]="3"*40
row=control_system_qualification_observation(check=c,raw_readback=bad,expected_identity=identity)
assert_valid_observation(row,"AUTHORITY_MISMATCH"); checks+=1

missing=deepcopy(raw); missing["status"]="MISSING"; missing["qualification_authority"]=None
row=control_system_qualification_observation(check=c,raw_readback=missing,expected_identity=identity)
assert_valid_observation(row,"AUTHORITY_MISMATCH"); checks+=1

c=check_row("PROFILE_UPDATE_AUTHORITY_READBACK","public.lf_activos + public.lf_operation_execution")
expected={
 "profile_code":"PROFILE_A","repository":"org/repo","merge_sha":"4"*40,"pr_number":77,
 "entrypoint_sha":"5"*40,"manifest_sha":"6"*40,"profile_pack_id":"PACK_A"
}
execution={"execution_id":"E2","operation_code":"ACTUALIZACION_PERFIL_LF","target_type":"PERFIL","target_code":"PROFILE_A","target_repo":"org/repo"}
asset={
 "codigo_activo":"PROFILE_A","tipo_activo":"PERFIL","archived_at":None,
 "metadata":{"last_governed_merge_sha":"4"*40,"last_governed_pr":"77","entrypoint_sha":"5"*40,"manifest_sha":"6"*40,"profile_pack_id":"PACK_A"},
 "raw_payload":{}
}
row=profile_update_readonly_observation(check=c,execution=execution,asset=asset,expected_identity=expected)
assert_valid_observation(row,"AUTHORITY_MATCH"); checks+=1

bad_asset=deepcopy(asset); bad_asset["metadata"]["manifest_sha"]="7"*40
row=profile_update_readonly_observation(check=c,execution=execution,asset=bad_asset,expected_identity=expected)
assert_valid_observation(row,"AUTHORITY_MISMATCH"); checks+=1

row=profile_update_readonly_observation(check=c,execution=None,asset=asset,expected_identity=expected)
assert_valid_observation(row,"AUTHORITY_MISMATCH"); checks+=1

c=check_row("PROFILE_RUNTIME_REFRESH_AUTHORITY_READBACK","public.lf_activos + public.lf_operation_execution")
expected_rt={
 "profile_code":"PROFILE_A","expected_main_sha":"8"*40,
 "runtime_release_ref":"/opt/lf-profile-runtime-api/releases/"+"8"*40
}
execution_rt={
 "execution_id":"E3","operation_code":"REFRESCO_RUNTIME_PERFIL_LF","target_type":"PERFIL","target_code":"PROFILE_A",
 "manifest":{"expected_main_sha":"8"*40}
}
asset_rt={
 "codigo_activo":"PROFILE_A","tipo_activo":"PERFIL","archived_at":None,
 "metadata":{"runtime_source_sha":"8"*40,"runtime_release_ref":"/opt/lf-profile-runtime-api/releases/"+"8"*40}
}
row=profile_runtime_refresh_readonly_observation(check=c,execution=execution_rt,asset=asset_rt,expected_identity=expected_rt)
assert_valid_observation(row,"AUTHORITY_MATCH"); checks+=1

bad_rt=deepcopy(asset_rt); bad_rt["metadata"]["runtime_source_sha"]="9"*40
row=profile_runtime_refresh_readonly_observation(check=c,execution=execution_rt,asset=bad_rt,expected_identity=expected_rt)
assert_valid_observation(row,"AUTHORITY_MISMATCH"); checks+=1

row=profile_runtime_refresh_readonly_observation(check=c,execution=execution_rt,asset=None,expected_identity=expected_rt)
assert_valid_observation(row,"AUTHORITY_MISMATCH"); checks+=1

for fn_row in (
    control_system_qualification_observation(check=check_row("CONTROL_SYSTEM_QUALIFICATION_READBACK"),raw_readback=raw,expected_identity=identity),
    profile_update_readonly_observation(check=check_row("PROFILE_UPDATE_AUTHORITY_READBACK"),execution=execution,asset=asset,expected_identity=expected),
    profile_runtime_refresh_readonly_observation(check=check_row("PROFILE_RUNTIME_REFRESH_AUTHORITY_READBACK"),execution=execution_rt,asset=asset_rt,expected_identity=expected_rt),
):
    assert fn_row["mutation_performed"] is False
    assert not any(k in fn_row for k in ("next_gate","post_merge_next_gate","promotion","rebind_result"))
checks+=1

print(f"PASS_AUTHORITY_READBACK_ADAPTERS_V1 checks={checks}")
