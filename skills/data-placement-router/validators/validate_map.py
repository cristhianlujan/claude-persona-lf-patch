#!/usr/bin/env python3
from pathlib import Path
import sys
import yaml

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "adapters" / "project-data-map.yaml"


def fail(msg: str) -> None:
    print(f"FAIL_DATA_PLACEMENT_ROUTER: {msg}")
    sys.exit(1)


def main() -> None:
    data = yaml.safe_load(MAP.read_text(encoding="utf-8"))
    projects = data.get("projects") or {}
    for code in ("LF_BACKOFFICE", "OVERALL", "SALY"):
        if code not in projects:
            fail(f"missing project mapping {code}")
        if not projects[code].get("schema"):
            fail(f"missing schema {code}")
    if projects["LF_BACKOFFICE"].get("mappings", {}).get("RULE") != "reglas":
        fail("LF_BACKOFFICE RULE route mismatch")
    if projects["OVERALL"].get("mappings", {}).get("SCREEN") != "app_screens":
        fail("OVERALL SCREEN route mismatch")
    if projects["SALY"].get("blocked_types", {}).get("SCREEN") != "BLOCKED_NO_DESTINATION":
        fail("SALY SCREEN must remain blocked without authorized destination")
    rules = data.get("rules") or {}
    if rules.get("never_create_table_automatically") is not True:
        fail("automatic table creation must remain forbidden")
    if rules.get("never_fallback_to_public") is not True:
        fail("public fallback must remain forbidden")
    print("PASS_DATA_PLACEMENT_ROUTER")


if __name__ == "__main__":
    main()
