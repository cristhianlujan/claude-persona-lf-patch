from profile_task_runtime_binding_v1 import resolve_task_runtime_binding


HEAD = "a" * 40
AUTH_DIGEST = "f" * 64


def source(path: str, char: str) -> dict:
    return {"path": path, "sha256": char * 64, "source_revision": HEAD}


def worker_binding(profile_code: str) -> dict:
    return {
        "worker_ref": profile_code,
        "worker_kind": "PROFILE",
        "binding_authority_ref": "supabase://public/lf_activos+ACT-0001+CURRENTNESS_AUTHORITY",
        "binding_revision": "rev-1",
        "binding_digest": "b" * 64,
        "source_revision": HEAD,
    }


def profile(profile_code: str, slug: str, role: str) -> dict:
    return {
        "profile_code": profile_code,
        "profile_slug": slug,
        "worker_roles": [role],
        "route_status": "READY_TO_EXECUTE",
        "downstream_execution_allowed": True,
        "currentness_state": "CURRENT",
        "source_revision": HEAD,
    }


def j02_task() -> dict:
    root = "skills/creating-integral-user-stories"
    refs = [
        source(f"{root}/perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md", "1"),
        source(f"{root}/agents/screen-decomposer.md", "2"),
        source(f"{root}/schemas/screen-decomposition.schema.json", "3"),
        source(f"{root}/scripts/validate_screen_decomposition_visual.py", "4"),
        source(f"{root}/judges/screen-decomposition.yaml", "5"),
        source(f"{root}/references/screen-decomposition-protocol.md", "6"),
    ]
    return {
        "source_mode": "EMBEDDED_SKILL_PROFILE",
        "source_root": root,
        "source_refs": refs,
        "runtime_schema": {
            "ref": f"{root}/schemas/screen-decomposition.schema.json",
            "sha256": "3" * 64,
            "selection_mode": "EXACT_REF",
        },
        "deterministic_validator": {
            "ref": f"{root}/scripts/validate_screen_decomposition_visual.py",
            "sha256": "4" * 64,
            "invocation": "CLI",
        },
        "judge_binding": {
            "judge_code": "J02_SCREEN_DECOMPOSITION",
            "ref": f"{root}/judges/screen-decomposition.yaml",
            "sha256": "5" * 64,
            "worker_must_not_execute_own_judge": True,
        },
        "model_context": {
            "source_refs": [
                f"{root}/perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md",
                f"{root}/agents/screen-decomposer.md",
                f"{root}/references/screen-decomposition-protocol.md",
            ],
            "max_chars": 32000,
        },
        "authority_refs": [
            {"ref": "artifact://skill/creating-integral-user-stories/ART_MANIFEST", "revision": "5", "digest": AUTH_DIGEST},
            {"ref": "supabase://public/lf_activos/PERFIL-SCREEN-DECOMPOSER-LF", "revision": "candidate", "digest": "e" * 64},
        ],
    }


def cross_task(step_id: str, judge_code: str, validator_name: str, suffix: str) -> dict:
    root = "skills/creating-integral-user-stories"
    schema_ref = f"{root}/schemas/story-pack.schema.json"
    validator_ref = f"{root}/scripts/{validator_name}"
    judge_ref = f"{root}/judges/{suffix}.yaml"
    refs = [
        source(f"{root}/perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md", "1"),
        source(f"{root}/agents/cross-cutting-enricher.md", "2"),
        source(schema_ref, "3"),
        source(validator_ref, "4"),
        source(judge_ref, "5"),
    ]
    return {
        "source_mode": "EMBEDDED_SKILL_PROFILE",
        "source_root": root,
        "source_refs": refs,
        "runtime_schema": {"ref": schema_ref, "sha256": "3" * 64, "selection_mode": "EXACT_REF"},
        "deterministic_validator": {"ref": validator_ref, "sha256": "4" * 64, "invocation": "CLI"},
        "judge_binding": {
            "judge_code": judge_code,
            "ref": judge_ref,
            "sha256": "5" * 64,
            "worker_must_not_execute_own_judge": True,
        },
        "model_context": {
            "source_refs": [
                f"{root}/perfiles/PERFIL_CROSS_CUTTING_ENRICHER_LF.md",
                f"{root}/agents/cross-cutting-enricher.md",
            ],
            "max_chars": 24000,
        },
        "authority_refs": [
            {"ref": "artifact://skill/creating-integral-user-stories/ART_MANIFEST", "revision": "5", "digest": AUTH_DIGEST}
        ],
    }


def clone(v):
    if isinstance(v, dict):
        return {k: clone(x) for k, x in v.items()}
    if isinstance(v, list):
        return [clone(x) for x in v]
    return v


def main() -> None:
    checks = 0

    step = {"step_id": "SCREEN_DECOMPOSITION", "worker_role": "SCREEN_DECOMPOSER", "judge_code": "J02_SCREEN_DECOMPOSITION"}
    wb = worker_binding("PERFIL-SCREEN-DECOMPOSER-LF")
    pa = profile("PERFIL-SCREEN-DECOMPOSER-LF", "screen_decomposer_lf", "SCREEN_DECOMPOSER")
    ta = j02_task()
    result = resolve_task_runtime_binding(step, wb, pa, ta)
    assert result["decision"] == "TASK_RUNTIME_BINDING_RESOLVED"
    assert result["binding"]["source_mode"] == "EMBEDDED_SKILL_PROFILE"
    assert result["binding"]["runtime_schema"]["selection_mode"] == "EXACT_REF"
    assert result["binding"]["deterministic_validator"]["invocation"] == "CLI"
    assert len(result["binding_digest"]) == 64
    checks += 5

    repeated = resolve_task_runtime_binding(clone(step), clone(wb), clone(pa), clone(ta))
    assert repeated["binding_digest"] == result["binding_digest"]
    assert repeated["resolution_digest"] == result["resolution_digest"]
    checks += 2

    stale = clone(pa)
    stale["currentness_state"] = "STALE"
    assert resolve_task_runtime_binding(step, wb, stale, ta)["decision"] == "BLOCK_PROFILE_NOT_CURRENT"
    checks += 1

    wrong_role = clone(pa)
    wrong_role["worker_roles"] = ["OTHER"]
    assert resolve_task_runtime_binding(step, wb, wrong_role, ta)["decision"] == "BLOCK_PROFILE_WORKER_ROLE_MISMATCH"
    checks += 1

    drift = clone(ta)
    drift["source_refs"][0]["source_revision"] = "c" * 40
    assert resolve_task_runtime_binding(step, wb, pa, drift)["decision"] == "BLOCK_SOURCE_REVISION_MISMATCH"
    checks += 1

    escaped = clone(ta)
    escaped["source_refs"][0]["path"] = "profiles/other/SKILL.md"
    assert resolve_task_runtime_binding(step, wb, pa, escaped)["decision"] == "BLOCK_SOURCE_PATH_OUTSIDE_ROOT"
    checks += 1

    ambiguous = clone(ta)
    ambiguous["runtime_schema"]["selection_mode"] = "AUTO"
    assert resolve_task_runtime_binding(step, wb, pa, ambiguous)["decision"] == "BLOCK_RUNTIME_SCHEMA_UNRESOLVED"
    checks += 1

    bad_validator = clone(ta)
    bad_validator["deterministic_validator"]["sha256"] = "9" * 64
    assert resolve_task_runtime_binding(step, wb, pa, bad_validator)["decision"] == "BLOCK_DETERMINISTIC_VALIDATOR_SHA_MISMATCH"
    checks += 1

    wrong_judge = clone(ta)
    wrong_judge["judge_binding"]["judge_code"] = "J03_STORY_CORE"
    assert resolve_task_runtime_binding(step, wb, pa, wrong_judge)["decision"] == "BLOCK_JUDGE_BINDING_UNRESOLVED"
    checks += 1

    self_judge = clone(ta)
    self_judge["judge_binding"]["worker_must_not_execute_own_judge"] = False
    assert resolve_task_runtime_binding(step, wb, pa, self_judge)["decision"] == "BLOCK_JUDGE_INDEPENDENCE_NOT_ENFORCED"
    checks += 1

    no_authority = clone(ta)
    no_authority["authority_refs"] = []
    assert resolve_task_runtime_binding(step, wb, pa, no_authority)["decision"] == "BLOCK_BINDING_AUTHORITY_INCOMPLETE"
    checks += 1

    # One canonical Cross Cutting profile can receive distinct task-bound contracts.
    cross_profile = profile("PERFIL-CROSS-CUTTING-ENRICHER-LF", "cross_cutting_enricher_lf", "CROSS_CUTTING_ENRICHER")
    cross_wb = worker_binding("PERFIL-CROSS-CUTTING-ENRICHER-LF")
    j05 = resolve_task_runtime_binding(
        {"step_id": "OBSERVATIONS_ERRORS", "worker_role": "CROSS_CUTTING_ENRICHER", "judge_code": "J05_OBSERVATIONS_ERRORS"},
        cross_wb,
        cross_profile,
        cross_task("OBSERVATIONS_ERRORS", "J05_OBSERVATIONS_ERRORS", "validate_field_coverage.py", "observations-errors"),
    )
    j09 = resolve_task_runtime_binding(
        {"step_id": "ANALYTICS_OBSERVABILITY", "worker_role": "CROSS_CUTTING_ENRICHER", "judge_code": "J09_ANALYTICS_OBSERVABILITY"},
        cross_wb,
        cross_profile,
        cross_task("ANALYTICS_OBSERVABILITY", "J09_ANALYTICS_OBSERVABILITY", "detect_pii_telemetry.py", "analytics-observability"),
    )
    assert j05["decision"] == "TASK_RUNTIME_BINDING_RESOLVED"
    assert j09["decision"] == "TASK_RUNTIME_BINDING_RESOLVED"
    assert j05["binding"]["profile_code"] == j09["binding"]["profile_code"]
    assert j05["binding"]["deterministic_validator"]["ref"] != j09["binding"]["deterministic_validator"]["ref"]
    assert j05["binding"]["judge_binding"]["judge_code"] != j09["binding"]["judge_binding"]["judge_code"]
    assert j05["binding_digest"] != j09["binding_digest"]
    checks += 6

    assert checks == 23
    print("PASS_PROFILE_TASK_RUNTIME_BINDING_V1 checks=23")


if __name__ == "__main__":
    main()
