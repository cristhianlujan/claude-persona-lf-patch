import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESOLUTION = json.loads((HERE / "story_onb004_email_requirement_resolution_v1.json").read_text(encoding="utf-8"))
LEGACY_PACKAGE = json.loads((HERE / "fixtures/onb_004_implementation_package_v1_1.json").read_text(encoding="utf-8"))
CLOSURE = json.loads((HERE / "story_m55_candidate_closure_v1.json").read_text(encoding="utf-8"))

errors = []

if RESOLUTION.get("schema_version") != "STORY_ONB004_EMAIL_REQUIREMENT_RESOLUTION_V1":
    errors.append("SCHEMA_VERSION_MISMATCH")
if RESOLUTION.get("screen_code") != "ONB_004" or RESOLUTION.get("pantalla_id") != 57:
    errors.append("SCREEN_IDENTITY_MISMATCH")
if RESOLUTION.get("owner_scope") != "SUPER_ADMIN":
    errors.append("OWNER_SCOPE_MUST_BE_SUPER_ADMIN")

resolution = RESOLUTION.get("resolution", {})
if resolution.get("status") != "RESOLVED_REQUIRED_EMAIL":
    errors.append("EMAIL_NOT_RESOLVED_REQUIRED")
if resolution.get("email_required") is not True:
    errors.append("EMAIL_REQUIRED_NOT_TRUE")
if resolution.get("required_override") is not True:
    errors.append("EMAIL_REQUIRED_OVERRIDE_NOT_TRUE")
if resolution.get("empty_email_blocks_progress") is not True:
    errors.append("EMPTY_EMAIL_MUST_BLOCK")
if resolution.get("message_code") != "MSG-CLIENT-ONB004-EMAIL-REQUIRED":
    errors.append("EMAIL_REQUIRED_MESSAGE_MISMATCH")

current = RESOLUTION.get("current_authority", {})
if current.get("decision_id") != "DEC-CLIENT-ONB004-WEB-V04-001" or current.get("decision_number") != 114:
    errors.append("CURRENT_AUTHORITY_MISMATCH")
if current.get("decision_status") != "VIGENTE":
    errors.append("CURRENT_AUTHORITY_NOT_VIGENTE")
if current.get("field_code") != "CAMPO_EMAIL":
    errors.append("FIELD_CODE_MISMATCH")

superseded = RESOLUTION.get("superseded_authority", {})
if superseded.get("decision_id") != "DEC-CLIENT-ONB004-EMAIL-OPTIONAL-001" or superseded.get("decision_number") != 111:
    errors.append("SUPERSEDED_AUTHORITY_IDENTITY_MISMATCH")
if superseded.get("decision_status") != "SUPERADO" or superseded.get("may_not_drive_current_story") is not True:
    errors.append("SUPERSEDED_AUTHORITY_STILL_DRIVES_CURRENT")

legacy_codes = {item.get("code") for item in LEGACY_PACKAGE.get("blocked_if", [])}
if "ONB004_EMAIL_REQUIREMENT_CONFLICT" not in legacy_codes:
    errors.append("LEGACY_EMAIL_CONFLICT_EXPECTED_FOR_HISTORICAL_EVIDENCE")

resolved = RESOLUTION.get("blocker_resolution", {})
if resolved.get("resolved_code") != "ONB004_EMAIL_REQUIREMENT_CONFLICT":
    errors.append("RESOLVED_BLOCKER_CODE_MISMATCH")
if resolved.get("current_state") != "RESOLVED_REQUIRED_EMAIL":
    errors.append("EMAIL_BLOCKER_NOT_RESOLVED")
if resolved.get("remove_from_current_effective_blockers") is not True:
    errors.append("EMAIL_BLOCKER_NOT_REMOVED_FROM_CURRENT")

closure_resolved = CLOSURE.get("resolved_candidate_item", {})
if closure_resolved.get("code") != "PROGRAMMING_TARGET_SCOPE_UNRESOLVED" or closure_resolved.get("candidate_state") != "RESOLVED_BY_GOVERNED_TARGET_BINDING":
    errors.append("PROGRAMMING_TARGET_NOT_RESOLVED")

current_effective_blockers = set(resolved.get("remaining_effective_blockers", []))
if current_effective_blockers != {"ONB004_LEGAL_ROUTES_PENDING"}:
    errors.append("CURRENT_EFFECTIVE_BLOCKERS_NOT_LEGAL_ONLY")

source = RESOLUTION.get("source_reconciliation", {})
if source.get("event_ref") != "supabase://public.lf_eventos/20274":
    errors.append("SOURCE_RECONCILIATION_EVENT_MISMATCH")
if source.get("repaired_mapping_ids") != [9463, 9464]:
    errors.append("REPAIRED_MAPPING_IDS_MISMATCH")
if source.get("legacy_source_pack_policy") != "IMMUTABLE_HISTORICAL_EVIDENCE_DO_NOT_REWRITE":
    errors.append("LEGACY_SOURCE_PACK_MUST_REMAIN_IMMUTABLE")

if any(RESOLUTION.get("activation_guard", {}).get(key) is not False for key in (
    "runtime_activation_performed",
    "production_activation_performed",
    "promotion_performed",
    "deploy_performed",
)):
    errors.append("UNAUTHORIZED_ACTIVATION_EFFECT")

result = {
    "schema": "STORY_ONB004_EMAIL_REQUIREMENT_RESOLUTION_SELF_TEST_V1",
    "result": "PASS" if not errors else "FAIL",
    "errors": errors,
    "current_email_requirement": "REQUIRED",
    "legacy_email_conflict_preserved_as_historical_evidence": True,
    "current_effective_blockers": sorted(current_effective_blockers),
}
print(json.dumps(result, indent=2, sort_keys=True))
if errors:
    raise SystemExit(1)
