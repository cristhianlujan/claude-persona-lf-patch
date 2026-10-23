from pathlib import Path

from build_story_j02_task_runtime_source_pack_v1 import build


ROOT = Path(__file__).resolve().parents[2]
SOURCE_REV = "a" * 40
AUTH = {
    "profile_asset": {"ref": "supabase://public/lf_activos/PERFIL-SCREEN-DECOMPOSER-LF", "revision": "1", "digest": "1" * 64},
    "story_manifest_artifact": {"ref": "artifact://skill/creating-integral-user-stories/ART_MANIFEST", "revision": "5", "digest": "2" * 64},
    "j02_judge_registry": {"ref": "supabase://public/lf_operation_judges/BUILD_INTEGRAL_STORY_CREATOR_LF/J02_SCREEN_DECOMPOSITION", "revision": "v0.8", "digest": "3" * 64},
    "currentness_receipt": {"ref": "currentness://story-j02/test", "revision": SOURCE_REV, "digest": "4" * 64},
}


def main() -> None:
    result = build(ROOT, SOURCE_REV, AUTH)
    checks = 0

    assert result["schema_version"] == "LF_PROFILE_TASK_AUTHORITY_SNAPSHOT_V1"
    assert result["source_revision"] == SOURCE_REV
    assert result["step_contract"] == {
        "step_id": "SCREEN_DECOMPOSITION",
        "worker_role": "SCREEN_DECOMPOSER",
        "judge_code": "J02_SCREEN_DECOMPOSITION",
    }
    assert result["profile_identity"]["profile_code"] == "PERFIL-SCREEN-DECOMPOSER-LF"
    assert result["profile_identity"]["profile_slug"] == "screen_decomposer_lf"
    checks += 5

    task = result["task_authority"]
    assert task["source_mode"] == "EMBEDDED_SKILL_PROFILE"
    assert task["source_root"] == "skills/creating-integral-user-stories"
    assert len(task["source_refs"]) == 6
    assert len({item["path"] for item in task["source_refs"]}) == 6
    assert all(len(item["sha256"]) == 64 for item in task["source_refs"])
    assert all(item["source_revision"] == SOURCE_REV for item in task["source_refs"])
    checks += 6

    assert task["runtime_schema"]["selection_mode"] == "EXACT_REF"
    assert task["runtime_schema"]["ref"].endswith("schemas/screen-decomposition.schema.json")
    assert len(task["runtime_schema"]["sha256"]) == 64
    assert task["deterministic_validator"]["ref"].endswith("scripts/validate_screen_decomposition_visual.py")
    assert task["deterministic_validator"]["invocation"] == "CLI"
    assert len(task["deterministic_validator"]["sha256"]) == 64
    checks += 6

    judge = task["judge_binding"]
    assert judge["judge_code"] == "J02_SCREEN_DECOMPOSITION"
    assert judge["ref"].endswith("judges/screen-decomposition.yaml")
    assert judge["worker_must_not_execute_own_judge"] is True
    assert len(judge["sha256"]) == 64
    checks += 4

    context = task["model_context"]
    assert context["observed_chars"] > 0
    assert context["observed_chars"] <= context["max_chars"]
    assert len(context["source_refs"]) == 3
    checks += 3

    authorities = task["authority_refs"]
    assert len(authorities) == 4
    assert len({item["ref"] for item in authorities}) == 4
    assert all(len(item["digest"]) == 64 for item in authorities)
    checks += 3

    bad = dict(AUTH)
    bad.pop("currentness_receipt")
    try:
        build(ROOT, SOURCE_REV, bad)
    except ValueError as exc:
        assert str(exc) == "AUTHORITY_CURRENTNESS_RECEIPT_MISSING"
    else:
        raise AssertionError("missing authority did not block")
    checks += 1

    try:
        build(ROOT, "not-a-sha", AUTH)
    except ValueError as exc:
        assert str(exc) == "SOURCE_REVISION_INVALID"
    else:
        raise AssertionError("invalid source revision did not block")
    checks += 1

    assert checks == 29
    print("PASS_STORY_J02_TASK_RUNTIME_SOURCE_PACK_V1 checks=29")


if __name__ == "__main__":
    main()
