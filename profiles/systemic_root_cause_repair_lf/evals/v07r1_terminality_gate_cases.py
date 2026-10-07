from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "validators"))

from terminality_gate_v1 import decide_terminal


def closed_state():
    return {
        "repair_required": True,
        "blocking_codes": [],
        "material_items": [],
        "uncontained_second_order_paths": [],
        "operability_applicable": False,
        "operability_status": "NOT_APPLICABLE_WITH_PROOF",
        "root_cause_established": True,
        "first_bad_boundary_established": True,
        "topology_evidence_bound": True,
        "blast_radius_evidence_bound": True,
        "repair_coherent": True,
        "rollback_executable": True,
        "acceptance_executable": True,
    }


def expect_needs_more(case_id, item_code, *, status="EVIDENCE_REQUIREMENT", operability=False):
    state = closed_state()
    state["material_items"] = [{"code": item_code, "status": status}]
    if operability:
        state["operability_applicable"] = True
        state["operability_status"] = "GAP"
    result = decide_terminal(state)
    assert result["status"] == "NEEDS_MORE_EVIDENCE", (case_id, result)
    return result


def test_rc078():
    expect_needs_more("RC-078", "FAILING_PATH_EXPECTED_HEAD_WIRING")


def test_rc030():
    expect_needs_more("RC-030", "RUNTIME_HANDOFF_MAPPING_READBACK")


def test_rc008():
    result = expect_needs_more("RC-008", "FULL_MUTATION_EFFECT_INVENTORY", operability=True)
    assert any(x.startswith("OPERABILITY_MAINTENANCE_OWNERSHIP_OPEN:") for x in result["reasons"])


def test_rc053():
    expect_needs_more("RC-053", "ALL_CURRENT_POINTERS_READBACK", status="UNKNOWN")


def test_rc012():
    expect_needs_more("RC-012", "ALL_COMPLETE_PATHS_SEMANTIC_GATE_WIRING", status="GAP")


def test_fully_closed():
    assert decide_terminal(closed_state()) == {"status": "SYSTEMIC_REPAIR_SPEC", "reasons": []}


def test_no_repair_positive_evidence():
    state = closed_state()
    state["repair_required"] = False
    state["no_repair_positive_evidence"] = False
    assert decide_terminal(state)["status"] == "NEEDS_MORE_EVIDENCE"
    state["no_repair_positive_evidence"] = True
    assert decide_terminal(state)["status"] == "NO_REPAIR_REQUIRED"


def test_pipeline_blocking_precedence():
    state = closed_state()
    state["pipeline_blocking_codes"] = ["CURRENTNESS_CONTRADICTION"]
    assert decide_terminal(state)["status"] == "BLOCK_PIPELINE"


def test_ordinary_blocking_code_is_nonready_not_pipeline_block():
    state = closed_state()
    state["blocking_codes"] = ["MATERIAL_EVIDENCE_MISSING"]
    result = decide_terminal(state)
    assert result["status"] == "NEEDS_MORE_EVIDENCE"
    assert "MATERIAL_BLOCKING_CODE:MATERIAL_EVIDENCE_MISSING" in result["reasons"]


def test_runtime_projection_contains_method_revision():
    skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
    binding = (ROOT / "contracts" / "runtime_binding.json").read_text(encoding="utf-8")
    capsule = skill.index("## Runtime method capsule")
    activation = skill.index("## Activation")
    assert capsule < activation
    assert '"Runtime method capsule"' in binding
    assert "V0.7R1" in skill


if __name__ == "__main__":
    tests = [test_rc078, test_rc030, test_rc008, test_rc053, test_rc012, test_fully_closed, test_no_repair_positive_evidence, test_pipeline_blocking_precedence, test_ordinary_blocking_code_is_nonready_not_pipeline_block, test_runtime_projection_contains_method_revision]
    for fn in tests:
        fn()
    print(f"PASS_SRCR_V07R1_TERMINALITY_GATE={len(tests)}/{len(tests)}")
