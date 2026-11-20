"""Regression guard: one native continuation carries both semantic choices before Step40."""
from pathlib import Path
import ast
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/lf_profile_native_resume.py"
EDGE = ROOT / "supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts"


class ProfilePre40Transport(unittest.TestCase):
    def test_combined_continuation_does_not_prebind_skill_without_screen(self):
        source = SCRIPT.read_text(encoding="utf-8")
        ast.parse(source)
        start = source.index('source_request = {"action":"profile_native_source_bind_v1"')
        end = source.index('code, source = call_json(EDGE_URL, source_request, headers)', start)
        source_bind = source[start:end]
        self.assertIn('"screen_selection_draft" not in request', source_bind)
        self.assertIn('source_request["skill_semantic_decision"', source_bind)
        begin = source.index('payload["screen_selection_draft"] = draft', end)
        finish = source.index('code, result = call_json(EDGE_URL, payload, headers)', begin)
        continuation = source[begin:finish]
        self.assertIn('payload[decision_field] = request.get(', continuation)
        self.assertIn('"SKILL_SELECTION_CONTINUATION"', continuation)

    def test_edge_orders_combined_screen_skill_bridge(self):
        source = EDGE.read_text(encoding="utf-8")
        start = source.index('const coordinatedPre40 = hasScreenDraft && hasSkillDecision;')
        screen = source.index('rpc(config, fetchFn, "lf_profile_screen_selector_semantic_submit_v1"', start)
        skill = source.index('rpc(config, fetchFn, "lf_profile_skill_selection_run_bind_v1"', screen)
        bridge = source.index('rpc(config, fetchFn, "lf_profile_native_bridge_prepare_v1"', skill)
        self.assertLess(screen, skill)
        self.assertLess(skill, bridge)
        self.assertIn('if (hasScreenDraft && !coordinatedPre40)', source[bridge:])


if __name__ == "__main__":
    unittest.main()
