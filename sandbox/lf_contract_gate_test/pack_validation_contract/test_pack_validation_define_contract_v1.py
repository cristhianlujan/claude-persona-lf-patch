#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "gobernanza/contratos/pack_validation_define_contract_v1.json"


def main() -> int:
    c = json.loads(CONTRACT.read_text(encoding="utf-8"))

    assert c["schema_version"] == "lf-pack-validation-contract/v1"
    assert c["durable_name"] == "PACK_VALIDATION_DEFINE_CONTRACT"
    assert c["capability"] == "PACK_VALIDATION"
    assert c["action"] == "DEFINE"
    assert c["object"] == "CONTRACT"
    assert c["owner"] == "PACK_VALIDATION"

    statuses = c["output_contract"]["status_enum"]
    assert statuses == ["PASS", "FAIL", "SKIP"]

    auth = c["output_contract"]["authorization_fields"]
    assert auth
    assert all(value is False for value in auth.values())

    profile = c["pack_types"]["PROFILE_PACK"]
    skill = c["pack_types"]["SKILL_PACK"]
    assert profile["generic_discovery_required"] is True
    assert skill["generic_discovery_required"] is True
    assert profile["slug_hardcoding_for_privileged_canary"] is False
    assert skill["slug_hardcoding_for_privileged_canary"] is False

    excluded = "\n".join(c["scope"]["excluded"]).lower()
    for required_boundary in (
        "runtime",
        "git-write",
        "database",
        "supabase",
        "assurance",
        "observability",
        "ekb",
        "lifecycle",
        "deployment",
        "production",
    ):
        assert required_boundary in excluded, required_boundary

    steps = c["execution_contract"]["steps"]
    assert steps == [
        "RESOLVE_AFFECTED_PACKS",
        "VALIDATE_PACK_STRUCTURE",
        "VALIDATE_PACK_MANIFEST_AND_SCHEMAS",
        "EXECUTE_PACK_LOCAL_VALIDATOR",
        "AGGREGATE_PACK_RESULT",
    ]

    migration = c["migration_sequence"]
    assert migration == [
        "PACK_DISCOVERY_RESOLVE_AFFECTED_PACKS",
        "PACK_VALIDATION_EXECUTE_PACK_CHECKS",
        "PROFILE_PACK_VALIDATION_CLEAN_VALIDATOR",
        "PACK_VALIDATION_CLEAN_WORKFLOW",
        "CI_CONTROL_REBIND_VALIDATE_PACKS_CONTROLS",
        "PACK_VALIDATION_VERIFY_E2E_FLOW",
    ]

    assert not any("GATE" in name for name in [c["durable_name"], *migration])

    print("PASS_PACK_VALIDATION_DEFINE_CONTRACT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
