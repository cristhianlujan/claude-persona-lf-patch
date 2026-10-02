from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "skills/creating-integral-user-stories/manifest.yaml"

WORKER_STEPS = {
    "SCREEN_DECOMPOSITION": ("SCREEN_DECOMPOSER", {"PROFILE", "AGENT"}),
    "STORY_CORE": ("STORY_CORE_AUTHOR", {"PROFILE", "AGENT"}),
    "FIELD_CONTRACTS": ("FIELD_CONTRACT_AUTHOR_AUDITOR", {"PROFILE", "AGENT"}),
    "OBSERVATIONS_ERRORS": ("CROSS_CUTTING_ENRICHER", {"PROFILE", "AGENT"}),
    "SECURITY_PRIVACY": ("CROSS_CUTTING_ENRICHER", {"PROFILE", "AGENT"}),
    "AUDIT_TRACEABILITY": ("CROSS_CUTTING_ENRICHER", {"PROFILE", "AGENT"}),
    "TOKENS_MESSAGES": ("CROSS_CUTTING_ENRICHER", {"PROFILE", "AGENT"}),
    "ANALYTICS_OBSERVABILITY": ("CROSS_CUTTING_ENRICHER", {"PROFILE", "AGENT"}),
    "TEST_COVERAGE": ("STORY_TEST_DERIVER", {"PROFILE", "AGENT"}),
}

NON_WORKER_STEPS = {
    "SOURCE_INTEGRITY",
    "SKILL_PACKAGE",
    "GITHUB_INTEGRITY",
    "INTEGRATION_CLOSE",
}

ALLOWED_KINDS = {"PROFILE", "AGENT", "SCRIPT", "SERVICE", "CAPABILITY"}


def main() -> None:
    manifest = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    workflow = manifest["workflow"]
    contract = workflow["worker_resolution_contract"]

    assert contract["schema_version"] == "STORY_WORKER_ROLE_CONTRACT_V1"
    assert contract["resolution_mode"] == "ORCHESTRATOR_RESOLVED"
    assert contract["binding_authority"] == "ORCHESTRATOR"
    assert contract["worker_identity_in_manifest"] == "FORBIDDEN"
    assert contract["capability_execution_contract"] == "CAPABILITY_EXECUTION_CONTRACT_V1"
    assert contract["unresolved_worker_policy"] == "BLOCK"
    assert set(contract["allowed_worker_kinds"]) == ALLOWED_KINDS

    pre = workflow["pre_decomposition_gate"]
    assert pre["judge"] == "J00_SCREEN_INGESTION"
    assert pre["worker_role"] == "SCREEN_INGESTOR"
    assert set(pre["allowed_worker_kinds"]) == ALLOWED_KINDS

    steps = {step["step_id"]: step for step in workflow["steps"]}
    assert set(WORKER_STEPS).issubset(steps)
    assert NON_WORKER_STEPS.issubset(steps)

    for step_id, (worker_role, allowed_kinds) in WORKER_STEPS.items():
        step = steps[step_id]
        assert step["worker_role"] == worker_role
        assert set(step["allowed_worker_kinds"]) == allowed_kinds
        assert not worker_role.startswith("PERFIL_")
        assert "worker_ref" not in step
        assert "worker_profile" not in step
        assert set(step["allowed_worker_kinds"]).issubset(ALLOWED_KINDS)

    for step_id in NON_WORKER_STEPS:
        step = steps[step_id]
        assert "worker_role" not in step
        assert "allowed_worker_kinds" not in step

    assert manifest["limits"]["no_runtime_enable"] is True
    assert manifest["limits"]["no_production"] is True
    assert manifest["current_state"]["runtime_enabled"] is False
    assert manifest["current_state"]["production_authorized"] is False

    print("PASS_STORY_WORKER_ROLE_MANIFEST_V1 checks=40")


if __name__ == "__main__":
    main()
