#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
contract = json.loads((ROOT / "motor_boundary_contract.json").read_text(encoding="utf-8"))
case = json.loads((ROOT / "cases" / "AUD-018" / "input.json").read_text(encoding="utf-8"))

expected_unit = ["DETECTADO", "ANALIZADO", "CARD_CREADA", "EN_REVISION", "PRUEBA_SANDBOX"]
expected_integration = ["APROBADO", "IMPACTADO", "VERIFICADO", "CERRADO"]

assert contract["project"] == "MOTOR_DE_APRENDIZAJE"
assert contract["target_asset"] == "ACT-0046"
assert contract["operational_authority"] == "SUPABASE"
assert contract["router"] == "ACT-0001"
assert contract["operational_source"] == "public.v_lf_fuente_operativa"
assert contract["unit_scope"]["stages"] == expected_unit
assert contract["integration_scope"]["stages"] == expected_integration
assert contract["pr_policy"]["base"] == "FRESH_MAIN"
assert contract["pr_policy"]["stacking"] is False
assert contract["pr_policy"]["shared_deep_ci_required_before_merge"] is True
assert contract["pr_policy"]["shared_deep_ci_required_to_continue_unit_iteration"] is False
assert contract["visual_support"]["authority"] is False
assert contract["visual_support"]["requires_supabase_binding"] is True

assert case["project"] == contract["project"]
assert case["target_asset"] == contract["target_asset"]
assert case["source"]["authority"] == "SUPABASE"
assert case["source"]["object"] == "transversal.error_knowledge"
assert case["source"]["code"] == "AUD-018"
assert case["constraints"]["read_only"] is True
assert case["constraints"]["automatic_impact"] is False
assert case["constraints"]["production"] is False
assert case["constraints"]["do_not_use_s26_s28_s30_implementation"] is True

print("MOTOR_INDEPENDENT_BOUNDARY_PASS")
print(f"unit_completion={contract['unit_scope']['completion']}")
print(f"integration_replay={contract['integration_scope']['replay_requirement']}")
