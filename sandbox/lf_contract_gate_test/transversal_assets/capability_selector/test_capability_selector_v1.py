from pathlib import Path
import importlib.util
import json

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("capability_selector_v1", HERE / "capability_selector_v1.py")
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
select_capabilities = module.select_capabilities


def load(name):
    return json.loads((HERE / name).read_text())


def assert_exact_shape(result):
    assert set(result) == {"selected_capabilities", "reasons", "fallback_state"}


def run():
    checks = 0
    fallback = ["SAFE_FULL_REVIEW"]
    catalog = [
        {"capability_code":"CAP_A","signal_types":["SIG_A"],"availability_state":"CURRENT","rank":2},
        {"capability_code":"CAP_B","signal_types":["SIG_A"],"availability_state":"CURRENT","rank":1},
        {"capability_code":"CAP_C","signal_types":["SIG_B"],"availability_state":"CURRENT","rank":3},
    ]
    policy = {"safe_fallback":fallback,"contradiction_sets":[["SIG_A","SIG_X"]],"require_current_catalog":True}

    clear = select_capabilities([{"signal_type":"SIG_A","state":"ACTIVE","confidence":0.01}], catalog, policy)
    assert_exact_shape(clear)
    assert clear["fallback_state"] == "CLEAR"
    assert clear["selected_capabilities"] == ["CAP_A","CAP_B"]
    assert "permission" not in clear and "admission" not in clear
    checks += 1

    multi = select_capabilities([
        {"signal_type":"SIG_A","state":"ACTIVE","confidence":0.01},
        {"signal_type":"SIG_B","state":"ACTIVE","confidence":0.99},
    ], catalog, policy)
    assert multi["fallback_state"] == "MULTI"
    assert multi["selected_capabilities"] == ["CAP_C","CAP_A","CAP_B"]
    checks += 1

    no_signal = select_capabilities([], catalog, policy)
    assert no_signal["fallback_state"] == "NO_SIGNAL"
    assert no_signal["selected_capabilities"] == fallback
    checks += 1

    contradictory = select_capabilities([
        {"signal_type":"SIG_A","state":"ACTIVE"},
        {"signal_type":"SIG_X","state":"ACTIVE"},
    ], catalog, policy)
    assert contradictory["fallback_state"] == "CONTRADICTORY"
    assert contradictory["selected_capabilities"] == fallback
    checks += 1

    failure = select_capabilities(
        [{"signal_type":"SIG_A","state":"ACTIVE"}],
        [{"capability_code":"CAP_A","signal_types":["SIG_A"],"availability_state":"STALE","rank":999}],
        policy,
    )
    assert failure["fallback_state"] == "CAPABILITY_FAILURE"
    assert failure["selected_capabilities"] == fallback
    checks += 1

    non_ig = load("non_ig_consumer_fixture_v1.json")
    non_ig_result = select_capabilities(non_ig["signals"], non_ig["catalog"], non_ig["policy"])
    assert_exact_shape(non_ig_result)
    assert non_ig_result["fallback_state"] == non_ig["expected"]["fallback_state"]
    assert non_ig_result["selected_capabilities"] == non_ig["expected"]["selected_capabilities"]
    checks += 1

    binding = load("ig_m5_4_selector_binding_v1.json")
    ig = binding["readback_case"]
    ig_result = select_capabilities(ig["signals"], binding["catalog"], binding["policy"])
    assert_exact_shape(ig_result)
    assert ig_result["fallback_state"] == ig["expected"]["fallback_state"]
    assert ig_result["selected_capabilities"] == ig["expected"]["selected_capabilities"]
    checks += 1

    core_text = (HERE / "capability_selector_v1.py").read_text().lower()
    contract_text = (HERE / "capability_selector_contract_v1.json").read_text().lower()
    forbidden = [
        "input_governance", "ig_", "pantalla", "familia", "classify_v",
        "probe_v", "gpt-", "claude-", "gemini-", "m5.4"
    ]
    assert not [token for token in forbidden if token in core_text or token in contract_text]
    checks += 1

    contract = load("capability_selector_contract_v1.json")
    assert contract["semantics"]["admission_authority"] is False
    assert contract["semantics"]["execution_permission_output"] is False
    checks += 1

    print(f"PASS_T_SELECT_CAPABILITY_SELECTOR_V1 checks={checks}")


if __name__ == "__main__":
    run()
