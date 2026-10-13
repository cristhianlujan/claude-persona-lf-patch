"""Source-only input mapping smoke: no mathematics, no runtime authorization."""
from __future__ import annotations

from profile_math_payload_binding_v1 import prepare_math_arguments


def _registry():
    return {"execution_permission": False, "methods": [{
        "method_id": "MATH_FIXTURE",
        "method_family": "MATHEMATICAL",
        "selection_lane": "SHADOW_ONLY",
        "availability_state": "EXPERIMENTAL_NOT_ADMITTED",
        "auto_select": False,
        "execution_permission": False,
        "candidate_implementation": {
            "source_path": "fixture.py",
            "exported_function": "fixture",
            "invocation_authorized": False,
            "production_binding": False,
            "argument_contract": {
                "positional": ["items"],
                "optional": {"limit": 5},
                "externally_bound": [],
            },
        },
    }]}


def run():
    reg = _registry()
    assert reg["execution_permission"] is False
    ready = prepare_math_arguments("MATH_FIXTURE", {"items": ["a", "b"]}, reg)
    assert ready["status"] == "READY_ARGUMENTS_ONLY"
    assert ready["args"] == [["a", "b"]]
    assert ready["kwargs"] == {"limit": 5}
    assert ready["handler_invoked"] is False
    assert ready["execution_authorized"] is False
    assert ready["cutover_eligible"] is False
    assert prepare_math_arguments("MATH_FIXTURE", {}, reg)["status"] == "BLOCK"
    assert prepare_math_arguments("MATH_FIXTURE", {"items": [], "unexpected": 1}, reg)["status"] == "BLOCK"
    assert prepare_math_arguments("UNKNOWN", {"items": []}, reg)["status"] == "BLOCK"
    reg["methods"][0]["execution_permission"] = True
    assert prepare_math_arguments("MATH_FIXTURE", {"items": []}, reg)["status"] == "BLOCK"
    print("PASS_PROFILE_MATH_PAYLOAD_TRAIN_SMOKE: positive=1 negative=4 auto_execution=0")


if __name__ == "__main__":
    run()
