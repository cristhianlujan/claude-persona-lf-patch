from profile_decision_package import (
    DecisionInstruction,
    build_profile_decision_package,
    validate_generator_receipt,
    validate_profile_review_receipt,
)

BASE_SHA = "a" * 64
NEW_SHA = "b" * 64

instructions = [
    DecisionInstruction("I01", "CHANGE", "content.table", "Increase row spacing."),
    DecisionInstruction("I02", "KEEP", "content.filters", "Preserve filter behavior."),
    DecisionInstruction("I03", "DO_NOT_CHANGE", "shell.sidebar", "Preserve sidebar exactly."),
    DecisionInstruction("I04", "DO_NOT_CHANGE", "shell.topbar", "Preserve topbar exactly."),
    DecisionInstruction("I05", "RESTRICTION", "content.table", "Do not add new columns."),
    DecisionInstruction("I06", "CHANGE", "content.empty_state", "Clarify empty-state copy."),
    DecisionInstruction("I07", "KEEP", "content.pagination", "Keep pagination semantics."),
    DecisionInstruction("I08", "BLOCK", "content.inline_edit", "Do not introduce inline editing."),
]

package = build_profile_decision_package(
    screen_code="B2B-CARGA-001",
    base_artifact_sha256=BASE_SHA,
    input_governance_run_id=217,
    instructions=instructions,
)
assert package["schema"] == "lf-profile-decision-package/v1"
assert len(package["instructions"]) == 8

valid_generator = {
    "consumed_package_sha256": package["package_sha256"],
    "applied_instruction_ids": [item.instruction_id for item in instructions],
    "outside_delta_changed": False,
    "new_artifact_sha256": NEW_SHA,
}
assert validate_generator_receipt(package=package, generator_receipt=valid_generator) == []

omitted = dict(valid_generator)
omitted["applied_instruction_ids"] = omitted["applied_instruction_ids"][:-1]
assert any(x.startswith("INSTRUCTIONS_OMITTED:") for x in validate_generator_receipt(package=package, generator_receipt=omitted))

invented = dict(valid_generator)
invented["applied_instruction_ids"] = invented["applied_instruction_ids"] + ["I99"]
assert any(x.startswith("INSTRUCTIONS_INVENTED:") for x in validate_generator_receipt(package=package, generator_receipt=invented))

outside = dict(valid_generator)
outside["outside_delta_changed"] = True
assert "OUTSIDE_DELTA_CHANGED" in validate_generator_receipt(package=package, generator_receipt=outside)

same_sha = dict(valid_generator)
same_sha["new_artifact_sha256"] = BASE_SHA
assert "NEW_ARTIFACT_SHA_REQUIRED" in validate_generator_receipt(package=package, generator_receipt=same_sha)

wrong_package = dict(valid_generator)
wrong_package["consumed_package_sha256"] = "c" * 64
assert "PACKAGE_SHA_NOT_CONSUMED_EXACTLY" in validate_generator_receipt(package=package, generator_receipt=wrong_package)

quality_negative = {
    "artifact_sha256": NEW_SHA,
    "visual_bytes_observed": False,
    "verdict": "PASS",
    "downstream_authorized": False,
}
errors = validate_profile_review_receipt(
    expected_artifact_sha256=NEW_SHA,
    receipt=quality_negative,
    require_visual_bytes=True,
)
assert "VISUAL_BYTES_NOT_OBSERVED" in errors
assert "PASS_WITHOUT_DOWNSTREAM_AUTHORIZATION" in errors

quality_valid = {
    "artifact_sha256": NEW_SHA,
    "visual_bytes_observed": True,
    "verdict": "PASS",
    "downstream_authorized": True,
}
assert validate_profile_review_receipt(
    expected_artifact_sha256=NEW_SHA,
    receipt=quality_valid,
    require_visual_bytes=True,
) == []

print("PROFILE_DRIVEN_SCREEN_GENERATION_TESTS_PASS 10/10")
