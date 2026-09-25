#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SQL = (HERE / "ekb_preflight_source_candidate_v1.sql").read_text(encoding="utf-8")
CONTRACT = json.loads((HERE / "LF_EKB_PREFLIGHT_CONTRACT_V1.json").read_text(encoding="utf-8"))


class EKBPreflightSourceContractV1Test(unittest.TestCase):
    def test_source_is_candidate_only_and_non_mutating_until_applied(self) -> None:
        self.assertTrue(SQL.startswith("-- SOURCE CANDIDATE ONLY. DO NOT APPLY FROM THIS PR."))
        self.assertIn("create or replace function public.lf_ekb_preflight_v1", SQL.lower())
        self.assertNotRegex(SQL.lower(), r"\b(insert|update|delete|truncate)\s+(into\s+)?public\.")

    def test_function_is_read_only_invoker_and_service_role_only(self) -> None:
        lower = SQL.lower()
        self.assertIn("language plpgsql\nstable\nsecurity invoker", lower)
        self.assertIn("revoke execute on function public.lf_ekb_preflight_v1", lower)
        self.assertIn("from public, anon, authenticated", lower)
        self.assertIn("grant execute on function public.lf_ekb_preflight_v1", lower)
        self.assertIn("to service_role", lower)

    def test_stable_function_does_not_use_clock_timestamp(self) -> None:
        lower = SQL.lower()
        self.assertNotIn("clock_timestamp()", lower)
        self.assertIn("statement_timestamp()", lower)

    def test_unknown_control_status_is_fail_closed(self) -> None:
        normalized = re.sub(r"\s+", " ", SQL.lower())
        self.assertIn(
            "coalesce(b->>'status','') not in ('pass','pending','review_required','blocked')",
            normalized,
        )

    def test_applicability_is_contextual_not_operation_name_heuristic(self) -> None:
        lower = SQL.lower()
        self.assertIn("lower(btrim(e.lifecycle_phase)) = any(v_phases)", lower)
        self.assertIn("lower(btrim(er.role)) = any(v_roles)", lower)
        self.assertNotIn("operation_code like", lower)
        self.assertNotIn("operation_code ilike", lower)

    def test_active_state_semantics_match_canonical_router(self) -> None:
        normalized = re.sub(r"\s+", " ", SQL.lower())
        expected = "upper(btrim(coalesce(estado,''))) in ('activo','active','abierto','open')"
        self.assertIn(expected, normalized)
        self.assertNotIn("where estado = 'activo'", normalized)
        self.assertNotIn("where e.estado='activo'", normalized)

    def test_high_severity_semantics_cover_router_vocabulary(self) -> None:
        normalized = re.sub(r"\s+", " ", SQL.lower())
        expected = "upper(btrim(coalesce(e.severidad,''))) in ('alta','high','critica','critical','p0')"
        self.assertIn(expected, normalized)
        self.assertNotIn("in ('high','critical','alta','alto')", normalized)

    def test_legacy_rules_are_inherited_by_selected_error_code(self) -> None:
        lower = SQL.lower()
        self.assertIn("r.activa and r.error_codigo = any(v_selected_codes)", lower)

    def test_best_practices_cannot_create_applicability(self) -> None:
        lower = SQL.lower()
        self.assertIn("where b.categoria in", lower)
        self.assertIn("where e.codigo = any(v_selected_codes)", lower)

    def test_detectability_is_not_used_as_execution_evidence(self) -> None:
        lower = SQL.lower()
        coverage_section = lower[lower.index("if p_control_coverage->>'coverage_version'") :]
        self.assertNotIn("detectability", coverage_section)
        self.assertIn("executed", coverage_section)
        self.assertIn("evidence_sha256", coverage_section)

    def test_contract_keeps_resolution_and_execution_separate(self) -> None:
        invariants = " ".join(CONTRACT["control_invariants"])
        self.assertIn("control_ref without execution evidence", invariants)
        self.assertIn("No PASS may be synthesized", invariants)
        self.assertFalse(CONTRACT["applicability"]["fuzzy_matching"])
        self.assertEqual(["ACTIVO", "ACTIVE", "ABIERTO", "OPEN"], CONTRACT["applicability"]["active_state_vocabulary"])
        self.assertEqual(["ALTA", "HIGH", "CRITICA", "CRITICAL", "P0"], CONTRACT["applicability"]["high_severity_vocabulary"])


if __name__ == "__main__":
    unittest.main()
