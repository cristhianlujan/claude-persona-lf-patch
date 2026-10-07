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


def expect_needs_more(case_id, item_code, *, operability=False):
    state = closed_state()
    state["material_items"] = [
        {"code": item_code, "status": "EVIDENCE_REQUIREMENT"}
    ]
    if operability:
        state["operability_applicable"] = True
        state["operability_status"] = "GAP"
    result = decide_terminal(state)
    assert result["status"] == "NEEDS_MORE_EVIDENCE", (case_id, result)
    return result


def test_rc078_overlap_composition_unproven():
    expect_needs_more("RC-078", "FAILING_PATH_EXPECTED_HEAD_WIRING")


def test_rc030_lossless_handoff_runtime_mapping_unproven():
    expect_needs_more("RC-030", "RUNTIME_HANDOFF_MAPPING_READBACK")


def test_rc008_rollback_residue_and_operability_open():
    result = expect_needs_more(
        "RC-008",
        "FULL_MUTATION_EFFECT_INVENTORY",
        operability=True,
    )
    assert any(
        reason.startswith("OPERABILITY_MAINTENANCE_OWNERSHIP_OPEN:")
        for reason in result["reasons"]
    )


def test_rc053_binding_currentness_readback_unproven():
    expect_needs_more("RC-053", "ALL_CURRENT_POINTERS_READBACK")


def test_rc012_semantic_gate_wiring_unproven():
    expect_needs_more("RC-012", "ALL_COMPLETE_PATHS_SEMANTIC_GATE_WIRING")


def test_positive_fully_closed_repair_spec():
    result = decide_terminal(closed_state())
    assert result == {"status": "SYSTEMIC_REPAIR_SPEC", "reasons": []}


def test_no_repair_requires_positive_evidence():
    state = closed_state()
    state["repair_required"] = False
    state["no_repair_positive_evidence"] = False
    result = decide_terminal(state)
    assert result["status"] == "NEEDS_MORE_EVIDENCE"

    state["no_repair_positive_evidence"] = True
    result = decide_terminal(state)
    assert result["status"] == "NO_REPAIR_REQUIRED"


def test_blocking_code_precedes_other_terminal_states():
    state = closed_state()
    state["blocking_codes"] = ["CURRENTNESS_CONTRADICTION"]
    result = decide_terminal(state)
    assert result["status"] == "BLOCK_PIPELINE"


if __name__ == "__main__":
    tests = [
        test_rc078_overlap_composition_unproven,
        test_rc030_lossless_handoff_runtime_mapping_unproven,
        test_rc008_rollback_residue_and_operability_open,
        test_rc053_binding_currentness_readback_unproven,
        test_rc012_semantic_gate_wiring_unproven,
        test_positive_fully_closed_repair_spec,
        test_no_repair_requires_positive_evidence,
        test_blocking_code_precedes_other_terminal_states,
    ]
    for test in tests:
        test()
    print(f"{len(tests)}/{len(tests)} PASS")
