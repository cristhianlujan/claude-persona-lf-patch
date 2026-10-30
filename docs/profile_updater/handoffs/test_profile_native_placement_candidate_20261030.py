"""Isolated adversarial checks for the EXISTING Profile Updater checkpoints.

Fixtures are synthetic. Passing this suite does not authenticate real GitHub
source readbacks, update the official guard, or authorize a profile write.
"""
import unittest
from PROFILE_NATIVE_STEP_PLACEMENT_VALIDATOR_CANDIDATE_20261030 import (
    validate_change_scope_placement as plan,
    verify_candidate_placement_readback as readback,
)

BASE, CANDIDATE = "a" * 40, "b" * 40


def graph(slug="repair_lf", sha=BASE, ids=("research", "decision", "quality")):
    steps = []
    for i, sid in enumerate(ids):
        steps.append({"step_id": sid, "order": (i + 1) * 10,
            "source_anchor": "SKILL.md#" + sid,
            "predecessor": ids[i - 1] if i else None,
            "successor": ids[i + 1] if i + 1 < len(ids) else None,
            "call_ref": "native://" + sid,
            "enforcement_ref": "native://enforce/" + sid})
    return {"profile_slug": slug, "source_head_sha": sha,
        "source_ref": "github://repo@" + sha + "/SKILL.md", "steps": steps}


def adoption(action="INSERT", target="n1_n2", before="research", after="decision"):
    return {"method_id": "M-QUALIFIED", "action": action, "target_step_id": target,
        "predecessor": before, "successor": after,
        "reason_ref": "case://genuine", "planned_enforcement_ref": "native://enforce/n1_n2"}


def proposal(g=None, a=None, slug="repair_lf"):
    return plan(profile_slug=slug, source_head_sha=BASE,
        selected_method_ids=["M-QUALIFIED"], adoptions=[a or adoption()],
        trusted_base_graph=g or graph())


def confirm(g=None, a=None, slug="repair_lf"):
    return readback(profile_slug=slug, base_head_sha=BASE,
        candidate_head_sha=CANDIDATE, adoptions=[a or adoption()],
        trusted_base_graph=graph(slug=slug),
        trusted_candidate_graph=g or graph(slug=slug, sha=CANDIDATE,
            ids=("research", "n1_n2", "decision", "quality")))


class NativePlacementCases(unittest.TestCase):
    def test_insert_into_original_graph(self):
        self.assertEqual(proposal(), [])

    def test_different_profile_different_position(self):
        ux = graph(slug="ux_lf", ids=("onboard", "simulate", "review"))
        plan_ux = adoption(target="new_ux_check", before="simulate", after="review")
        self.assertEqual(proposal(ux, plan_ux, "ux_lf"), [])

    def test_other_profile_step_cannot_be_reused(self):
        ux = graph(slug="ux_lf", ids=("onboard", "simulate", "review"))
        self.assertIn("PLACEMENT_PREDECESSOR_NOT_FOUND", proposal(ux, adoption(), "ux_lf"))

    def test_cross_profile_readback_blocked(self):
        self.assertIn("PROFILE_GRAPH_SOURCE_BINDING_MISMATCH", proposal(graph(slug="wrong")))

    def test_stale_source_head_blocked(self):
        self.assertIn("PROFILE_GRAPH_SOURCE_BINDING_MISMATCH", proposal(graph(sha="c" * 40)))

    def test_duplicate_step_id_blocked(self):
        g = graph()
        g["steps"][1]["step_id"] = g["steps"][0]["step_id"]
        self.assertIn("PROFILE_STEP_ID_OR_ORDER_DUPLICATE", proposal(g))

    def test_wrong_adjacency_blocked(self):
        self.assertIn("PLACEMENT_INSERT_NOT_ADJACENT",
            proposal(a=adoption(before="research", after="quality")))

    def test_modify_existing_step(self):
        self.assertEqual(proposal(a=adoption(action="MODIFY",
            target="decision", before="research", after="quality")), [])

    def test_insert_without_enforcement_blocked(self):
        a = adoption()
        a["planned_enforcement_ref"] = ""
        self.assertIn("PLACEMENT_INSERT_ENFORCEMENT_UNSPECIFIED", proposal(a=a))

    def test_unqualified_unselected_method_blocked(self):
        a = adoption()
        a["method_id"] = "UNSELECTED"
        self.assertIn("PLACEMENT_METHOD_NOT_SELECTED", proposal(a=a))

    def test_inconsistent_graph_blocked(self):
        g = graph()
        g["steps"][1]["predecessor"] = "unrelated"
        self.assertIn("PROFILE_STEP_GRAPH_LINK_INCONSISTENT", proposal(g))

    def test_no_change_without_adoption(self):
        self.assertEqual(plan(profile_slug="repair_lf", source_head_sha=BASE,
            selected_method_ids=[], adoptions=[], trusted_base_graph=graph()), [])

    def test_insert_realized_with_relinked_neighbors(self):
        self.assertEqual(confirm(), [])

    def test_missing_call_blocked_after_write(self):
        g = graph(sha=CANDIDATE, ids=("research", "n1_n2", "decision", "quality"))
        g["steps"][1]["call_ref"] = ""
        self.assertIn("PLACEMENT_ENFORCEMENT_NOT_REALIZED", confirm(g))

    def test_unrelated_step_mutation_blocked(self):
        g = graph(sha=CANDIDATE, ids=("research", "n1_n2", "decision", "quality"))
        g["steps"][-1]["source_anchor"] = "SKILL.md#unexpected"
        self.assertIn("PLACEMENT_UNRELATED_STEP_CHANGED", confirm(g))

    def test_neighbor_enforcement_mutation_rejected(self):
        g = graph(sha=CANDIDATE, ids=("research", "n1_n2", "decision", "quality"))
        g["steps"][0]["enforcement_ref"] = "native://unrelated"
        self.assertIn("PLACEMENT_UNEXPECTED_NEIGHBOR_MUTATION", confirm(g))

    def test_candidate_head_cannot_equal_base(self):
        self.assertIn("PLACEMENT_CANDIDATE_HEAD_INVALID",
            readback(profile_slug="repair_lf", base_head_sha=BASE,
                candidate_head_sha=BASE, adoptions=[],
                trusted_base_graph=graph(), trusted_candidate_graph=graph()))

    def test_candidate_from_another_profile_blocked(self):
        self.assertIn("PROFILE_GRAPH_SOURCE_BINDING_MISMATCH",
            confirm(graph(slug="wrong", sha=CANDIDATE)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
