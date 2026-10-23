from skill_worker_resolver_v1 import resolve_worker


BASE_STEP = {
    "step_id": "SCREEN_DECOMPOSITION",
    "worker_role": "SCREEN_DECOMPOSER",
    "allowed_worker_kinds": ["PROFILE", "AGENT"],
}

BASE_SNAPSHOT = {
    "binding_authority_ref": "supabase://public/lf_activos+ACT-0001+CURRENTNESS_AUTHORITY",
    "binding_revision": "rev-001",
    "source_revision": "a" * 40,
    "candidates": [
        {
            "worker_ref": "PERFIL-SCREEN-DECOMPOSER-LF",
            "worker_kind": "PROFILE",
            "worker_roles": ["SCREEN_DECOMPOSER"],
            "route_status": "READY_TO_EXECUTE",
            "downstream_execution_allowed": True,
            "currentness_state": "CURRENT",
            "source_ref": "supabase://public/lf_activos/PERFIL-SCREEN-DECOMPOSER-LF",
            "source_revision": "a" * 40,
        }
    ],
}


def clone(value):
    if isinstance(value, dict):
        return {k: clone(v) for k, v in value.items()}
    if isinstance(value, list):
        return [clone(v) for v in value]
    return value


def main() -> None:
    checks = 0

    positive = resolve_worker(clone(BASE_STEP), clone(BASE_SNAPSHOT))
    assert positive["status"] == "RESOLVED"
    assert positive["decision"] == "WORKER_RESOLVED"
    assert positive["binding_seed"]["worker_ref"] == "PERFIL-SCREEN-DECOMPOSER-LF"
    assert positive["binding_seed"]["worker_kind"] == "PROFILE"
    assert len(positive["binding_seed"]["binding_digest"]) == 64
    checks += 5

    repeated = resolve_worker(clone(BASE_STEP), clone(BASE_SNAPSHOT))
    assert repeated["resolution_digest"] == positive["resolution_digest"]
    assert repeated["binding_seed"]["binding_digest"] == positive["binding_seed"]["binding_digest"]
    checks += 2

    hardcoded = clone(BASE_STEP)
    hardcoded["worker_ref"] = "PERFIL-SCREEN-DECOMPOSER-LF"
    result = resolve_worker(hardcoded, clone(BASE_SNAPSHOT))
    assert result["decision"] == "BLOCK_CONCRETE_WORKER_IDENTITY_IN_MANIFEST"
    checks += 1

    stale = clone(BASE_SNAPSHOT)
    stale["candidates"][0]["currentness_state"] = "STALE"
    result = resolve_worker(clone(BASE_STEP), stale)
    assert result["decision"] == "BLOCK_WORKER_UNRESOLVED"
    assert "CURRENTNESS_NOT_CURRENT" in result["details"]["rejected"][0]["reasons"]
    checks += 2

    route_blocked = clone(BASE_SNAPSHOT)
    route_blocked["candidates"][0]["route_status"] = "BLOCKED"
    result = resolve_worker(clone(BASE_STEP), route_blocked)
    assert result["decision"] == "BLOCK_WORKER_UNRESOLVED"
    assert "ROUTER_NOT_READY" in result["details"]["rejected"][0]["reasons"]
    checks += 2

    wrong_kind = clone(BASE_SNAPSHOT)
    wrong_kind["candidates"][0]["worker_kind"] = "SERVICE"
    result = resolve_worker(clone(BASE_STEP), wrong_kind)
    assert result["decision"] == "BLOCK_WORKER_UNRESOLVED"
    assert "WORKER_KIND_NOT_ALLOWED" in result["details"]["rejected"][0]["reasons"]
    checks += 2

    mismatch = clone(BASE_SNAPSHOT)
    mismatch["candidates"][0]["source_revision"] = "b" * 40
    result = resolve_worker(clone(BASE_STEP), mismatch)
    assert result["decision"] == "BLOCK_WORKER_UNRESOLVED"
    assert "SOURCE_REVISION_MISMATCH" in result["details"]["rejected"][0]["reasons"]
    checks += 2

    ambiguous = clone(BASE_SNAPSHOT)
    second = clone(ambiguous["candidates"][0])
    second["worker_ref"] = "AGENT-SCREEN-DECOMPOSER-LF"
    second["worker_kind"] = "AGENT"
    second["source_ref"] = "repo://skills/creating-integral-user-stories/agents/screen-decomposer.md"
    ambiguous["candidates"].append(second)
    result = resolve_worker(clone(BASE_STEP), ambiguous)
    assert result["decision"] == "BLOCK_WORKER_AMBIGUOUS"
    assert result["details"]["eligible_worker_refs"] == [
        "AGENT-SCREEN-DECOMPOSER-LF",
        "PERFIL-SCREEN-DECOMPOSER-LF",
    ]
    checks += 2

    duplicate = clone(BASE_SNAPSHOT)
    duplicate["candidates"].append(clone(duplicate["candidates"][0]))
    result = resolve_worker(clone(BASE_STEP), duplicate)
    assert result["decision"] == "BLOCK_WORKER_AUTHORITY_DUPLICATE"
    checks += 1

    missing_role = clone(BASE_STEP)
    del missing_role["worker_role"]
    result = resolve_worker(missing_role, clone(BASE_SNAPSHOT))
    assert result["decision"] == "BLOCK_WORKER_ROLE_MISSING"
    checks += 1

    capability_step = {
        "step_id": "EXAMPLE_CAPABILITY_STEP",
        "worker_role": "EXAMPLE_CAPABILITY_ROLE",
        "allowed_worker_kinds": ["CAPABILITY"],
    }
    capability_snapshot = {
        "binding_authority_ref": "supabase://public/lf_capability_current",
        "binding_revision": "cap-rev-1",
        "source_revision": "c" * 40,
        "candidates": [
            {
                "worker_ref": "CAPABILITY://EXAMPLE",
                "worker_kind": "CAPABILITY",
                "worker_roles": ["EXAMPLE_CAPABILITY_ROLE"],
                "route_status": "READY_TO_EXECUTE",
                "downstream_execution_allowed": True,
                "currentness_state": "CURRENT",
                "source_ref": "supabase://public/lf_capability_current/EXAMPLE",
                "source_revision": "c" * 40,
                "capability_code": "EXAMPLE_CAPABILITY",
                "capability_execution_contract": "CAPABILITY_EXECUTION_CONTRACT_V1",
            }
        ],
    }
    result = resolve_worker(capability_step, capability_snapshot)
    assert result["decision"] == "WORKER_RESOLVED"
    assert result["binding_seed"]["capability_code"] == "EXAMPLE_CAPABILITY"
    checks += 2

    capability_missing_contract = clone(capability_snapshot)
    del capability_missing_contract["candidates"][0]["capability_execution_contract"]
    result = resolve_worker(capability_step, capability_missing_contract)
    assert result["decision"] == "BLOCK_CAPABILITY_CONTRACT_MISSING"
    checks += 1

    assert checks == 23
    print("PASS_SKILL_WORKER_RESOLVER_V1 checks=23")


if __name__ == "__main__":
    main()
