"""One focused read-only smoke check: five source bindings, no admission or execution."""
from __future__ import annotations

import ast
import json
from pathlib import Path

from capability_selector_v3 import compose_capabilities_v3

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REG = json.loads((HERE.parent / "method_pack_registry" / "method_pack_registry_v2.json").read_text())
MATHEMATICAL = {m["method_id"]: m for m in REG["methods"]
                if m.get("method_family") == "MATHEMATICAL"}
CASES = (
    ({"causal_requirement": "HIGH"}, "CAUSAL_GRAPH_ANALYSIS"),
    ({"repeated_pattern": True}, "OCHIAI_SUSPICIOUSNESS"),
    ({"evidence_paths": "MULTIPLE_INDEPENDENT"}, "RECIPROCAL_RANK_FUSION"),
    ({"profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"]}, "DELTA_DEBUGGING"),
    ({"optimization_need": "REQUIRED"}, "MCNEMAR_AND_CONFIDENCE_INTERVALS"),
)

def verified(v):
    return {"value": v, "verification_state": "VERIFIED",
            "evidence_refs": ["fixture://precondition-not-runtime-proof"]}

def run():
    assert len(MATHEMATICAL) == len(CASES) == 5
    assert REG["execution_permission"] is False
    assert REG["math_extension"]["auto_execute"] is False
    assert REG["math_extension"]["executable_from_selector"] is False
    assert REG["math_extension"]["executable_from_method_bridge"] is False
    preconditions = {}
    for method in MATHEMATICAL.values():
        assert (method["selection_lane"] == "SHADOW_ONLY"
                and method["availability_state"] == "EXPERIMENTAL_NOT_ADMITTED"
                and method["execution_permission"] is False
                and method["auto_select"] is False)
        source = method.get("candidate_implementation")
        assert isinstance(source, dict), method["method_id"]
        assert (source["status"] == "SOURCE_AVAILABLE_SHADOW_ONLY"
                and source["callable_scope"] == "EXPLICIT_OFFLINE_EVALUATION_ONLY"
                and source["invocation_authorized"] is False
                and source["production_binding"] is False)
        for field in ("source_path", "test_path"):
            src = Path(source[field])
            assert not src.is_absolute() and ".." not in src.parts
            assert src.parts[:3] == ("skills", "profile_creator", "evals")
            absolute = ROOT / src
            assert absolute.is_file(), (method["method_id"], field, src)
            content = absolute.read_text(encoding="utf-8")
            tree = ast.parse(content, filename=str(src))
            if field == "source_path":
                assert any(isinstance(node, ast.FunctionDef)
                           and node.name == source["exported_function"]
                           for node in tree.body), (method["method_id"], source["exported_function"])
        for check in method["precondition_contract"]:
            preconditions[check["key"]] = verified(check["expected"])
    for context, expected in CASES:
        result = compose_capabilities_v3(
            context, [], {"fallback_capabilities": []}, REG, preconditions)
        math = result["mathematical_method_selection"]
        chosen = math["recommended_trials"]
        assert len(chosen) == 1 and chosen[0]["method_id"] == expected, (context, math)
        assert chosen[0]["candidate_implementation"] == MATHEMATICAL[expected]["candidate_implementation"]
        assert chosen[0]["execution_authorized"] is False
        assert not result["execution_authorized"] and not math["execution_authorized"]
        assert all(x["method_id"] not in MATHEMATICAL for x in result["selected_methods"])
    simple = compose_capabilities_v3(
        {"complexity": "LOW"}, [], {"fallback_capabilities": []}, REG, preconditions)
    assert simple["mathematical_method_selection"]["recommended_trials"] == []
    print("PASS_PROFILE_MATH_SOURCE_BINDINGS 5/5 linked, no_math_simple=1, auto_execution=0")

if __name__ == "__main__":
    run()
