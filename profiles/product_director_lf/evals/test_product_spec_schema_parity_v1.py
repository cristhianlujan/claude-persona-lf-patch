#!/usr/bin/env python3
"""Product Spec schema/validator parity on a synthetic source-bound fixture.

Pure structural local checks; no model/provider execution or admission claim.
"""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
VALIDATOR=ROOT/"profiles/product_director_lf/validators/validate_product_director_output.py"
SCHEMA=ROOT/"profiles/product_director_lf/schemas/product_direction_spec.schema.json"
spec=importlib.util.spec_from_file_location("product_contract_validator",VALIDATOR)
worker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


def fixture():
    ref="authority://fictional-test-001"
    decision="Bounded test decision, not production authority"
    score_keys=worker.SCORE_KEYS
    return {
        "worker":"product_director_lf",
        "output_type":"PRODUCT_DIRECTION_SPEC",
        "self_verdict":"PASS",
        "deliverable_created":{
            "product_decision":{
                "decision_id":"test-decision-001","selected_decision":decision,
                "rationale":"Synthetic source-bounded tradeoff",
                "source_refs":[{"source_ref":ref,"authority":"AUTHORITATIVE",
                                "current":True,"supports":"synthetic test permission only"}],
                "rejected_alternatives":[],"tradeoffs":[],
                "preserved_constraints":[],"semantic_qualifiers":[]
            },
            "included_scope":[],"excluded_scope":[],
            "priority":{},"dependencies":[],"risks":[],
            "profiles_to_activate":[],"blockers":[],
            "next_step":{},"final_verdict":"PASS",
            "evidence_used":[],"open_assumptions":[],"success_metric_or_proxy":{},
            "acceptance_criteria":[{"criterion_id":"criterion-001",
                                    "condition":"synthetic condition established",
                                    "observable_check":"synthetic test differs when decision changed"}],
            "handoff_to_next":{"target":"test_worker","input_contract":"SYNTHETIC_ONLY",
                               "qualifiers_to_preserve":[]},
            "authority_status":"SUPPORTED","material_claims":[],
            "decision_lineage":{
                "objective":"Synthetic test, not actual authority",
                "selected_decision":decision,
                "evidence_refs":[ref],"preserved_constraints":["SYNTHETIC_ONLY"],
                "acceptance_refs":["criterion-001"],
                "handoff_effect":"test worker gets identical bounded decision",
            }
        },
        "handoff_to_next":{"target":"test_worker"},
        "traceability":{},
        "score":{
            **{key:5 for key in score_keys},
            "total":25,
            "evidence_by_criterion":{key:[ref] for key in score_keys}
        }
    }


class CanonicalSpecParity(unittest.TestCase):
    def test_declared_schema_fixture_passes_both_checks(self):
        obj=fixture()
        self.assertTrue(worker.validate(obj)["valid"],worker.validate(obj))
        schema=json.loads(SCHEMA.read_text(encoding="utf8"))
        from profile_output_shape_preflight_v1 import validate_shape
        self.assertEqual(validate_shape(schema,obj)["status"],"PASS")

    def test_top_level_traceability_is_required_by_contract(self):
        obj=fixture();del obj["traceability"]
        errors=worker.validate(obj)["errors"]
        self.assertTrue(any("REQUIRED_MISSING:traceability" in x["message"] for x in errors), errors)

    def test_nested_legacy_required_field_still_enforced(self):
        obj=fixture();del obj["deliverable_created"]["priority"]
        errors=worker.validate(obj)["errors"]
        self.assertTrue(any("REQUIRED_MISSING:priority" in x["message"] for x in errors),errors)

    def test_benchmark_envelope_not_permitted_as_spec(self):
        obj=fixture();obj["stage"]=3
        errors=worker.validate(obj)["errors"]
        self.assertTrue(any(x["code"]=="SCHEMA_ADDITIONAL_PROPERTY" for x in errors),errors)

    def test_unsupported_authority_cannot_pass(self):
        obj=fixture();obj["deliverable_created"]["authority_status"]="UNSUPPORTED"
        errors=worker.validate(obj)["errors"]
        self.assertTrue(any(x["code"]=="AUTHORITY_STATUS" for x in errors),errors)

    def test_blocked_mode_retains_own_contract(self):
        obj={"worker":"product_director_lf","output_type":"BLOCKED_PRODUCT_RISK",
             "self_verdict":"BLOCKED_PRODUCT_RISK",
             "deliverable_created":{"blockers":["synthetic missing material authority"]}}
        self.assertTrue(worker.validate(obj)["valid"],worker.validate(obj))


if __name__=="__main__":
    unittest.main(verbosity=2)
