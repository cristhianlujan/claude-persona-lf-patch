#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "validators" / "validate_adapter_package.py"
spec = importlib.util.spec_from_file_location("validator", VALIDATOR)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

VALID = {
    "state": "BOUND",
    "render_binding": {
        "project_code": "LF",
        "output_target": "PPTX",
        "canonical_refs": ["lf_design.color_tokens:v1", "screen_visual_specs:checkout"],
        "resolved_tokens": {"primary": "token:brand.primary"},
        "screen_frame_policy": {"device": "mobile", "frame": "app"},
        "mockup_template": "mobile_app_standard",
        "qa_checks": ["token provenance", "screen frame integrity"],
        "blockers": []
    },
    "lf_adapter_invocations": [{
        "adapter_code": "ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF",
        "adapter_version": "v0.2-candidate",
        "invocation_id": "inv-000002",
        "activation_reason": "project visual deliverable includes governed LF screens",
        "source_sha256": "a" * 64,
        "capsule_sha256": "b" * 64,
        "verdict": "APPLIED"
    }]
}


def expect_pass(name, doc):
    validator.validate_result(doc)
    print(f"PASS expected-pass {name}")


def expect_fail(name, doc):
    try:
        validator.validate_result(doc)
    except ValueError:
        print(f"PASS expected-fail {name}")
        return
    raise AssertionError(f"case should fail: {name}")


def main():
    expect_pass("bound_valid", VALID)

    x = deepcopy(VALID)
    x["lf_adapter_invocations"] = []
    expect_fail("missing_invocation_receipt", x)

    x = deepcopy(VALID)
    x["render_binding"]["resolved_tokens"] = {}
    expect_fail("inventable_token_gap", x)

    x = deepcopy(VALID)
    x["render_binding"]["screen_frame_policy"] = {}
    expect_fail("missing_frame_policy", x)

    x = deepcopy(VALID)
    x["render_binding"]["canonical_refs"] = []
    expect_fail("missing_authority_refs", x)

    x = deepcopy(VALID)
    x["state"] = "RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY"
    x["render_binding"]["resolved_tokens"] = {}
    x["render_binding"]["screen_frame_policy"] = {}
    x["render_binding"]["blockers"] = ["no governed brand source"]
    x["lf_adapter_invocations"][0]["verdict"] = "BLOCKED"
    expect_pass("missing_brand_authority_return", x)

    x = deepcopy(VALID)
    x["state"] = "BLOCKED_VISUAL_SOURCE_CONFLICT"
    expect_fail("conflict_without_evidence", x)

    x = deepcopy(VALID)
    x["lf_adapter_invocations"][0]["adapter_code"] = "ADAPTER_LF_SHELL_PROFILE"
    expect_fail("wrong_adapter_identity", x)

    print("QUALITY_V2_PASS")


if __name__ == "__main__":
    main()
