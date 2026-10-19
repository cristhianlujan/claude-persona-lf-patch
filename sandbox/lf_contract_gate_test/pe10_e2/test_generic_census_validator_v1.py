"""Positive and negative controls for generic PE10 reverse discovery floor."""
import copy
import importlib.util
from pathlib import Path
import unittest

module_path = Path(__file__).with_name("generic_census_validator_v1.py")
spec = importlib.util.spec_from_file_location("generic_census_validator_v1", module_path)
assert spec is not None and spec.loader is not None
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def edge(consumer: str, called: str, comparison: str, *,
         context: str = "CONFIRMED_CODE", count: int = 1) -> dict:
    return {
        "consumer_identity": consumer,
        "called_schema": "alpha",
        "called_name": called,
        "candidate_count": count,
        "callee_candidates": [
            {"oid": str(9000 + i), "schema": "alpha", "name": called, "signature_args": ""}
            for i in range(count)
        ],
        "historical_comparison": comparison,
        "resolution_status": (
            "STATIC_CALL_TARGET_UNRESOLVED" if count == 0
            else "STATIC_CALL_CANDIDATE_RESOLVED" if count == 1
            else "AMBIGUOUS_STATIC_CALLEE_IDENTITY"
        ),
        "lexical_context_check": context,
        "observation_scope": "CURRENT_BODY_NOT_HISTORICAL_EXECUTION",
        "static_confirmed": context == "CONFIRMED_CODE" and count == 1,
        "runtime_execution_proven": False,
    }


class TestEvidenceFloor(unittest.TestCase):
    def setUp(self) -> None:
        self.rows = [
            edge("alpha.fn_rec_a()", "fn_core", "HISTORICAL_EDGE_DECLARED"),
            edge("alpha.fn_rec_a()", "fn_core_new", "CURRENT_EDGE_NOT_IN_P0"),
            edge("other.fn_external()", "fn_core_new", "CURRENT_CONSUMER_OUTSIDE_P0"),
        ]

    def synthesis(self, rows=None):
        use = self.rows if rows is None else rows
        digest, normalized = validator.canonical_manifest(use)
        return {
            "edge_manifest_sha256": digest,
            "preserved_edge_keys": [
                r["key"] for r in normalized
                if r["historical_comparison"] != "HISTORICAL_EDGE_DECLARED"
            ],
            "explicit_unresolved_keys": [],
            "claims_runtime_execution": False,
        }

    def test_positive_preserves_complete_changed_and_external_edges(self):
        result = validator.validate_synthesis(self.rows, self.synthesis())
        self.assertEqual(result["status"], "PASS_STATIC_MANIFEST_CONSERVATION_ONLY")
        self.assertEqual(result["edges"], 3)
        self.assertFalse(result["runtime_proven"])
        self.assertEqual(result["partition"]["CURRENT_CONSUMER_OUTSIDE_P0"], 1)

    def test_comment_strings_dollar_quotes_and_prefix_not_calls(self):
        scan = validator.exact_static_call_candidate
        self.assertTrue(scan("v:=alpha.fn_core(p_value);", "fn_core"))
        self.assertTrue(scan("v:=fn_core (p_value);", "fn_core"))
        self.assertFalse(scan("v:=fn_core_next(p_value);", "fn_core"))
        self.assertFalse(scan("-- fn_core(foo)\nv:=42;", "fn_core"))
        self.assertFalse(scan("/* fn_core(foo) /* fn_core(abc) */ */ v:=42;", "fn_core"))
        self.assertFalse(scan("x := 'fn_core(foo)';", "fn_core"))
        self.assertFalse(scan("x := $$fn_core(foo)$$;", "fn_core"))
        self.assertFalse(scan("x := $body$fn_core(foo)$body$;", "fn_core"))

    def test_reject_synthesis_drop_of_external_consumer(self):
        synthesis = self.synthesis()
        synthesis["preserved_edge_keys"].pop()
        with self.assertRaisesRegex(ValueError, "lost in synthesis"):
            validator.validate_synthesis(self.rows, synthesis)

    def test_reject_count_and_resolution_drift(self):
        broken = copy.deepcopy(self.rows)
        broken[1]["candidate_count"] = 2
        with self.assertRaisesRegex(ValueError, "cardinality"):
            validator.canonical_manifest(broken)

    def test_reject_comment_only_as_verified_call(self):
        broken = copy.deepcopy(self.rows)
        broken[1]["lexical_context_check"] = "COMMENT_ONLY"
        with self.assertRaisesRegex(ValueError, "unproved static edge"):
            validator.canonical_manifest(broken)

    def test_reject_unresolved_overload_as_unique_edge(self):
        broken = copy.deepcopy(self.rows)
        broken[1]["candidate_count"] = 2
        broken[1]["callee_candidates"].append({"oid": "9501", "schema": "alpha", "name": "fn_core_new", "signature_args": "v int"})
        with self.assertRaisesRegex(ValueError, "false resolution state"):
            validator.canonical_manifest(broken)

    def test_reject_static_as_runtime_attestation(self):
        broken = copy.deepcopy(self.rows)
        broken[1]["runtime_execution_proven"] = True
        with self.assertRaisesRegex(ValueError, "cannot prove runtime"):
            validator.canonical_manifest(broken)

    def test_reject_p0_current_epoch_conflation(self):
        broken = copy.deepcopy(self.rows)
        broken[1]["observation_scope"] = "HISTORICAL_P0_EXECUTION_PROVEN"
        with self.assertRaisesRegex(ValueError, "source epoch"):
            validator.canonical_manifest(broken)

    def test_reject_forged_digest(self):
        wrong = self.synthesis()
        wrong["edge_manifest_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "does not bind"):
            validator.validate_synthesis(self.rows, wrong)

    def test_unresolved_key_must_exist_in_raw_manifest(self):
        wrong = self.synthesis()
        wrong["explicit_unresolved_keys"] = ["fabricated.unknown|?.fn_core"]
        with self.assertRaisesRegex(ValueError, "not tied to a real edge"):
            validator.validate_synthesis(self.rows, wrong)

    def test_unqualified_overloaded_resolution_remains_ambiguous(self):
        r = edge("beta.fn_user()", "fn_helper", "CURRENT_CONSUMER_OUTSIDE_P0",
                 context="UNREVIEWED", count=2)
        r["static_confirmed"] = False
        digest, rows = validator.canonical_manifest([r])
        self.assertEqual(rows[0]["resolution_status"], "AMBIGUOUS_STATIC_CALLEE_IDENTITY")
        self.assertEqual(len(digest), 64)

    def test_reject_fabricated_preserved_edge(self):
        wrong = self.synthesis()
        wrong["preserved_edge_keys"].append("fabricated.unknown|?.fn_fiction")
        with self.assertRaisesRegex(ValueError, "preserved key not tied"):
            validator.validate_synthesis(self.rows, wrong)

    def test_reject_unresolved_without_explanation(self):
        wrong = self.synthesis()
        moved = wrong["preserved_edge_keys"].pop()
        wrong["explicit_unresolved_keys"] = [moved]
        with self.assertRaisesRegex(ValueError, "exact reason coverage"):
            validator.validate_synthesis(self.rows, wrong)

    def test_reject_edge_both_preserved_and_unresolved(self):
        wrong = self.synthesis()
        moved = wrong["preserved_edge_keys"][0]
        wrong["explicit_unresolved_keys"] = [moved]
        wrong["unresolved_reasons"] = {moved: "Call provenance is not demonstrable"}
        with self.assertRaisesRegex(ValueError, "both preserved and unresolved"):
            validator.validate_synthesis(self.rows, wrong)

    def test_unresolved_with_reason_does_not_claim_pass(self):
        result = self.synthesis()
        moved = result["preserved_edge_keys"].pop()
        result["explicit_unresolved_keys"] = [moved]
        result["unresolved_reasons"] = {moved: "Static token may occur in dynamic SQL"}
        observed = validator.validate_synthesis(self.rows, result)
        self.assertEqual(observed["status"], "UNRESOLVED_STATIC_MANIFEST_CONSERVATION")
        self.assertEqual(observed["unresolved_edges"], 1)

    def test_reject_short_unresolved_reason(self):
        result = self.synthesis()
        moved = result["preserved_edge_keys"].pop()
        result["explicit_unresolved_keys"] = [moved]
        result["unresolved_reasons"] = {moved: "unknown"}
        with self.assertRaisesRegex(ValueError, "substantive reason"):
            validator.validate_synthesis(self.rows, result)

    def test_null_schema_qualifier_is_explicitly_unknown(self):
        r = edge("beta.fn_any()", "fn_target", "CURRENT_CONSUMER_OUTSIDE_P0",
                 context="UNREVIEWED", count=1)
        r["called_schema"] = None
        r["static_confirmed"] = False
        _, rows = validator.canonical_manifest([r])
        self.assertEqual(rows[0]["key"], "beta.fn_any()|?.fn_target")

    def test_missing_or_null_callee_identity_fails(self):
        r = edge("beta.fn_any()", "fn_target", "CURRENT_EDGE_NOT_IN_P0")
        r["called_name"] = None
        with self.assertRaisesRegex(ValueError, "invalid exact callee"):
            validator.canonical_manifest([r])

    def test_missing_object_remains_unknown(self):
        r = edge("beta.fn_user()", "fn_missing", "CURRENT_EDGE_NOT_IN_P0",
                 context="UNREVIEWED", count=0)
        r["static_confirmed"] = False
        _, rows = validator.canonical_manifest([r])
        self.assertEqual(rows[0]["resolution_status"], "STATIC_CALL_TARGET_UNRESOLVED")


if __name__ == "__main__":
    unittest.main()
