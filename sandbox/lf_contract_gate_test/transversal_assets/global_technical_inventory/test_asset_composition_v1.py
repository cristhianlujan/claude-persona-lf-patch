#!/usr/bin/env python3
import copy
import json
from pathlib import Path

from validate_asset_composition_v1 import CompositionError, validate_and_project

ROOT = Path(__file__).parent
PAYLOAD = json.loads((ROOT / "story_creator_j02_asset_composition_v1.json").read_text())


def obj(ref, *, source_of_truth, definition_sha256=None, source_version=None):
    row = {"object_ref": ref, "active": True, "source_of_truth": source_of_truth}
    if definition_sha256 is not None:
        row["definition_sha256"] = definition_sha256
    if source_version is not None:
        row["source_version"] = source_version
    return row


INVENTORY = {
    "objects": [
        obj("asset://SKILL-CREATING-INTEGRAL-USER-STORIES", source_of_truth=True),
        obj(
            "artifact://skill/creating-integral-user-stories/ART_MANIFEST",
            source_of_truth=True,
            definition_sha256=PAYLOAD["authority"]["source_sha256"],
            source_version=PAYLOAD["authority"]["source_version"],
        ),
        obj("artifact://skill/creating-integral-user-stories/ART_AGENT_SCREEN_DECOMPOSER", source_of_truth=True),
        obj("artifact://skill/creating-integral-user-stories/PERFIL_SCREEN_DECOMPOSER_LF", source_of_truth=True),
        obj("artifact://skill/creating-integral-user-stories/JUDGES_SCREEN_DECOMPOSITION_YAML", source_of_truth=True),
        obj("artifact://skill/creating-integral-user-stories/ART_SCHEMA_SCREEN_DECOMP", source_of_truth=True),
        obj("artifact://skill/creating-integral-user-stories/ART_REF_SCREEN_DECOMPOSITION", source_of_truth=True),
        obj("artifact://skill/creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION", source_of_truth=True),
        obj("repo://skills/creating-integral-user-stories/scripts/validate_screen_decomposition_v08.py", source_of_truth=False),
        obj("repo://skills/creating-integral-user-stories/scripts/validate_screen_decomposition_visual.py", source_of_truth=False),
        obj("repo://skills/creating-integral-user-stories/evals/fixtures/j02_external_positive.json", source_of_truth=False),
        obj("repo://skills/creating-integral-user-stories/evals/fixtures/j02_source_omission.json", source_of_truth=False),
    ]
}


def expect_error(payload, code, inventory=INVENTORY):
    try:
        validate_and_project(payload, inventory)
    except CompositionError as exc:
        assert str(exc) == code, (str(exc), code)
        return
    raise AssertionError(f"expected {code}")


def replace_inventory_row(inventory, ref, **changes):
    changed = copy.deepcopy(inventory)
    row = next(item for item in changed["objects"] if item["object_ref"] == ref)
    row.update(changes)
    return changed


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
    bad["authority"]["source_sha256"] = "0" * 64
    expect_error(bad, "AUTHORITY_SOURCE_SHA256_MISMATCH")

    bad = copy.deepcopy(PAYLOAD)
    bad["authority"]["source_version"] = "999"
    expect_error(bad, "AUTHORITY_SOURCE_VERSION_MISMATCH")

    authority_ref = PAYLOAD["authority"]["source_ref"]
    not_authority = replace_inventory_row(INVENTORY, authority_ref, source_of_truth=False)
    expect_error(PAYLOAD, "AUTHORITY_SOURCE_NOT_SOURCE_OF_TRUTH", not_authority)

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

    canonical_ref = PAYLOAD["components"][0]["members"][0]["member_ref"]
    fake_canonical = replace_inventory_row(INVENTORY, canonical_ref, source_of_truth=False)
    expect_error(PAYLOAD, "CANONICAL_ARTIFACT_NOT_SOURCE_OF_TRUTH", fake_canonical)

    candidate_ref = PAYLOAD["components"][0]["members"][6]["member_ref"]
    fake_candidate = replace_inventory_row(INVENTORY, candidate_ref, source_of_truth=True)
    expect_error(PAYLOAD, "CANDIDATE_OBJECT_SOURCE_OF_TRUTH_FORBIDDEN", fake_candidate)

    print("PASS_ASSET_COMPOSITION_V1=14/14")


if __name__ == "__main__":
    main()
