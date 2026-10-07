#!/usr/bin/env python3
import json

TEST_CODE = "ENG_N_18_NEG_OVERTRACKING"
EXIT = "Tracking/identity only with material signal; purpose+consumer+data need; no invasive signal without governed authority; NOT_REQUIRED outside scope; no shadow authority."

def evaluate(*, material_signal, purpose=None, consumer=None, data_need=None, governed_authority=False, invasive=False, shadow_authority=False):
    if shadow_authority:
        return "BLOCK"
    if not material_signal:
        return "BLOCK" if invasive else "NOT_REQUIRED"
    if invasive and not (purpose and consumer and data_need and governed_authority):
        return "BLOCK"
    if not (purpose and consumer and data_need):
        return "BLOCK"
    return "ALLOW"

observed = {
    "outside_scope": evaluate(material_signal=False),
    "authorized_material": evaluate(material_signal=True,purpose="fraud_prevention",consumer="validator",data_need="stable_session_id",governed_authority=True,invasive=True),
    "unauthorized_invasive": evaluate(material_signal=True,purpose="fraud_prevention",consumer="validator",data_need="device_fingerprint",governed_authority=False,invasive=True),
    "missing_purpose": evaluate(material_signal=True,consumer="validator",data_need="stable_session_id",governed_authority=True,invasive=True),
    "shadow_authority": evaluate(material_signal=True,purpose="fraud_prevention",consumer="validator",data_need="stable_session_id",governed_authority=True,invasive=False,shadow_authority=True),
}
assert observed["outside_scope"] == "NOT_REQUIRED"
assert observed["authorized_material"] == "ALLOW"
assert observed["unauthorized_invasive"] == "BLOCK"
assert observed["missing_purpose"] == "BLOCK"
assert observed["shadow_authority"] == "BLOCK"

print(json.dumps({
    "test_code": TEST_CODE,
    "status": "PASS",
    "test_passed": True,
    "test_exit_code": 0,
    "semantic_authority_bound": True,
    "adversarial_case_executed": True,
    "canonical_exit_criterion": EXIT,
    "observed": observed
}, sort_keys=True))
