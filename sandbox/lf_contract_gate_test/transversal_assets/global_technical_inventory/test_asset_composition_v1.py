#!/usr/bin/env python3
import copy
import json
from pathlib import Path

from validate_asset_composition_v1 import CompositionError, validate_and_project

ROOT = Path(__file__).parent
PAYLOAD = json.loads((ROOT / "story_creator_j02_asset_composition_v1.json").read_text())

INVENTORY = {
    "objects": [
        "asset://SKILL-CREATING-INTEGRAL-USER-STORIES",
        "artifact://skill/creating-integral-user-stories/ART_MANIFEST",
        "artifact://skill/creating-integral-user-stories/ART_AGENT_SCREEN_DECOMPOSER",
        "artifact://skill/creating-integral-user-stories/PERFIL_SCREEN_DECOMPOSER_LF",
        "artifact://skill/creating-integral-user-stories/JUDGES_SCREEN_DECOMPOSITION_YAML",
        "artifact://skill/creating-integral-user-stories/ART_SCHEMA_SCREEN_DECOMP",
        "artifact://skill/creating-integral-user-stories/ART_REF_SCREEN_DECOMPOSITION",
        "artifact://skill/creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION",
        "repo://skills/creating-integral-user-stories/scripts/validate_screen_decomposition_v08.py",
        "repo://skills/creating-integral-user-stories/scripts/validate_screen_decomposition_visual.py",
        "repo://skills/creating-integral-user-stories/evals/fixtures/j02_external_positive.json",
        "repo://skills/creating-integral-user-stories/evals/fixtures/j02_source_omission.json"
    ]
}


def expect_error(payload, code, inventory=INVENTORY):
    try:
        validate_and_project(payload, inventory)
    except CompositionError as exc:
        assert str(exc) == code, (str(exc), code)
        return
    raise AssertionError(f"expected {code}")


def main():
    result = validate_and_project(PAYLOAD, INVENTORY)
    assert len(result["objects"]) == 1
    assert result["objects"][0]["object_ref"] == "component://SKILL-CREATING-INTEGRAL-USER-STORIES/J02_SCREEN_DECOMPOSITION"
    assert len(result["dependencies"]) == 11
    assert sum(1 for e in result["dependencies"] if e["relation_type"] == "HAS_COMPONENT") == 1
    assert sum(1 for e in result["dependencies"] if e["relation_type"] == "COMPOSED_OF") == 10

    bad = copy.deepcopy(PAYLOAD)
    bad["asset_ref"] = "asset://MISSING"
    expect_error(bad, "ASSET_REF_NOT_IN_INVENTORY")

    bad = copy.deepcopy(PAYLOAD)
    bad["authority"]["source_sha256"] = "bad"
    expect_error(bad, "AUTHORITY_SHA256_INVALID")

    bad = copy.deepcopy(PAYLOAD)
    bad["scope"]["component_codes"] = ["OTHER"]
    expect_error(bad, "COMPONENT_SET_SCOPE_MISMATCH")

    bad = copy.deepcopy(PAYLOAD)
    bad["components"].append(copy.deepcopy(bad["components"][0]))
    expect_error(bad, "COMPONENT_CODE_DUPLICATE")

    bad = copy.deepcopy(PAYLOAD)
    bad["components"][0]["members"][0]["member_ref"] = "artifact://skill/creating-integral-user-stories/MISSING"
    expect_error(bad, "MEMBER_REF_NOT_IN_INVENTORY")

    bad = copy.deepcopy(PAYLOAD)
    bad["components"][0]["members"].append(copy.deepcopy(bad["components"][0]["members"][0]))
    expect_error(bad, "MEMBER_REF_DUPLICATE")

    bad = copy.deepcopy(PAYLOAD)
    bad["components"][0]["members"][0]["membership_class"] = "CANDIDATE_OBJECT"
    expect_error(bad, "CANDIDATE_OBJECT_MUST_NOT_USE_CANONICAL_ARTIFACT_REF")

    bad = copy.deepcopy(PAYLOAD)
    bad["components"][0]["members"][6]["membership_class"] = "CANONICAL_ARTIFACT"
    expect_error(bad, "CANONICAL_ARTIFACT_REF_INVALID")

    print("PASS_ASSET_COMPOSITION_V1=9/9")


if __name__ == "__main__":
    main()
