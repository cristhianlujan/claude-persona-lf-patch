#!/usr/bin/env python3
import copy
from pathlib import Path
import yaml
from validate_policy_operation_runtime_package import validate

ROOT = Path(__file__).resolve().parent
BASE = yaml.safe_load((ROOT / "policy_operation_runtime_package.yaml").read_text(encoding="utf-8"))

def case(name, mutate, expected_fragment=None):
    x = copy.deepcopy(BASE); mutate(x); errors = validate(x)
    if expected_fragment is None:
        assert not errors, (name, errors)
    else:
        assert any(expected_fragment in e for e in errors), (name, expected_fragment, errors)
    print("PASS", name)

def main():
    case("base", lambda x: None)
    case("invent_policy_asset", lambda x: x["shared"].__setitem__("asset_type","POLICY"), "ASSET_TYPE_MUST_BE_REGLA")
    case("durable_router_active", lambda x: x["shared"].__setitem__("router_status_for_durable_candidate","ACTIVE"), "DURABLE_ROUTER_STATUS_MISMATCH")
    case("missing_ekb_guard", lambda x: x["shared"]["hard_guards"].remove("EKB_BEFORE_WRITE"), "HARD_GUARDS_MISSING:EKB_BEFORE_WRITE")
    case("create_requires_existing", lambda x: x["operations"]["CREACION_POLITICA_LF"].__setitem__("requires_existing_target",True), "CREACION_POLITICA_LF_REQUIRES_EXISTING_TARGET_MISMATCH")
    case("update_requires_missing", lambda x: x["operations"]["ACTUALIZACION_POLITICA_LF"].__setitem__("requires_missing_target",True), "ACTUALIZACION_POLITICA_LF_REQUIRES_MISSING_TARGET_MISMATCH")
    case("step_order_gap", lambda x: x["operations"]["CREACION_POLITICA_LF"]["steps"][2].__setitem__("order",35), "CREACION_POLITICA_LF_STEP_ORDER_MISMATCH")
    case("empty_evidence", lambda x: x["operations"]["ACTUALIZACION_POLITICA_LF"]["steps"][1].__setitem__("required_evidence_keys",[]), "ACTUALIZACION_POLITICA_LF_materialize_successor_EVIDENCE_EMPTY")
    case("judge_allows_automatic_promotion", lambda x: x["judge_contract"]["fail_if"].remove("automatic_promotion_attempted"), "JUDGE_FAIL_RULE_MISSING:automatic_promotion_attempted")
    case("hide_natural_inference_gap", lambda x: x["router_canary"]["natural_language_without_action_hint"].__setitem__("expected_status","READY_TO_EXECUTE"), "NATURAL_INFERENCE_GAP_NOT_FAIL_CLOSED")
    print("POLICY_OPERATION_RUNTIME_REGRESSIONS_PASS=10/10")

if __name__ == "__main__": main()
