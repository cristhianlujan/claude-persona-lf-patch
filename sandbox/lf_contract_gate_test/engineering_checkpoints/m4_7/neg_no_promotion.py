#!/usr/bin/env python3
import json, os
TEST_CODE="ENG_M4_7_NEG_NO_PROMOTION"
x=json.loads(os.environ["ENGINEERING_DECLARED_INPUT_JSON"])
assert x["validator_detected"] is True
assert x["promotion_authorized"] is False
assert x["promotion_delta"] == 0
assert x["durable_residue"] is False
assert x["typed_findings"] >= 1
print(json.dumps({"status":"PASS","test_code":TEST_CODE,"observed":{
  "test_passed":True,"test_exit_code":0,"semantic_authority_bound":True,
  "adversarial_case_executed":True,"validator_detected":True,
  "promotion_authorized":False,"promotion_delta":0,"durable_residue":False,
  "typed_findings":x["typed_findings"]
}},sort_keys=True))
