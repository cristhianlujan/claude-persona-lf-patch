import unittest
from planner_reconciliation_v1 import reconcile_planner_result

PLANNER_SCHEMA = "LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1"
D = {"discovery_state": "CANDIDATES_FOUND", "discovery_exhausted": False}
E = {"unresolved_reasons": ["SOURCE_NOT_IDENTIFIED"], "candidates": []}
STOP = {"schema_version": PLANNER_SCHEMA, "state": "STOP",
        "code": "STOP_NO_DECISION_CHANGING_EVIDENCE",
        "automation_options_exhausted": True, "effects_executed": False}
C = {"candidate_ref": "synthetic://receipt/1", "source_ref": "synthetic://source/1",
     "covers_reasons": ["SOURCE_NOT_IDENTIFIED"],
     "acquisition_cost_rank": 1, "available": True, "material": True}
CONT = {"schema_version": PLANNER_SCHEMA, "state": "CONTINUE",
        "code": "NEXT_MINIMAL_EVIDENCE_SELECTED", "effects_executed": False,
        "next_evidence": C}


class PlannerReconciliationTests(unittest.TestCase):
    def test_local_planner_stop_returns_to_discovery(self):
        self.assertEqual(reconcile_planner_result(D, E, STOP)["transition"],
                         "RETURN_TO_SOURCE_DISCOVERY")

    def test_discovery_exhausted_boolean_is_not_trusted(self):
        self.assertEqual(reconcile_planner_result({**D, "discovery_exhausted": True}, E, STOP)["transition"],
                         "RETURN_TO_SOURCE_DISCOVERY")

    def test_forged_global_state_cannot_be_used_as_proof(self):
        result = reconcile_planner_result({"discovery_state": "DISCOVERY_EXHAUSTED"}, E, STOP)
        self.assertEqual(result["transition"], "BLOCK")
        self.assertEqual(result["code"], "CANONICAL_EXHAUSTION_RECEIPT_REQUIRED")

    def test_discovery_access_denied_blocks(self):
        self.assertEqual(reconcile_planner_result({"discovery_state": "ACCESS_DENIED"}, E, STOP)["transition"],
                         "BLOCK")

    def test_valid_planner_choice_is_not_execution(self):
        result = reconcile_planner_result(D, {**E, "candidates": [C]}, CONT)
        self.assertEqual(result["transition"], "NEXT_EVIDENCE_READBACK_REQUIRED")
        self.assertFalse(result["effects_executed"])
        self.assertFalse(result["data_access_granted"])

    def test_injected_planner_choice_blocks(self):
        self.assertEqual(reconcile_planner_result(D, E, CONT)["code"],
                         "PLANNER_SELECTED_UNADMITTED_CANDIDATE")

    def test_duplicate_input_candidate_blocks(self):
        self.assertEqual(reconcile_planner_result(D, {**E,"candidates":[C,C]}, CONT)["transition"],
                         "BLOCK")

    def test_forged_executed_effects_blocks(self):
        self.assertEqual(reconcile_planner_result(D,{**E,"candidates":[C]},
                          {**CONT,"effects_executed":True})["transition"], "BLOCK")

    def test_invalid_planner_shape_blocks(self):
        self.assertEqual(reconcile_planner_result(D,E,{"state":"STOP"})["transition"],"BLOCK")

    def test_resolved_reason_requires_independent_assessment(self):
        result = reconcile_planner_result(D,E,{"schema_version":PLANNER_SCHEMA,
           "state":"STOP","code":"STOP_DECISION_RESOLVED","effects_executed":False})
        self.assertEqual(result["transition"],"INDEPENDENT_DECISION_ASSESSMENT_REQUIRED")

    def test_dependency_drift_is_not_exhaustion(self):
        result = reconcile_planner_result(D,E,{"schema_version":PLANNER_SCHEMA,
           "state":"STOP","code":"DEPENDENCY_CURRENTNESS_DRIFT","effects_executed":False})
        self.assertEqual(result["transition"],"BLOCK")

    def test_no_transition_grants_authority(self):
        for result in (
            reconcile_planner_result(D,E,STOP),
            reconcile_planner_result(D,{"candidates":[C],"unresolved_reasons":["X"]},CONT),
            reconcile_planner_result({"discovery_state":"DISCOVERY_EXHAUSTED"},E,STOP),
        ):
            self.assertFalse(result["data_access_granted"])
            self.assertFalse(result["global_discovery_exhausted"])


if __name__ == "__main__":
    unittest.main()
