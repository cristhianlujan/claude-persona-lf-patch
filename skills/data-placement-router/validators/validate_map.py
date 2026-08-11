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

    lf = projects["LF_BACKOFFICE"]
    if lf.get("mappings", {}).get("RULE") != "reglas":
        fail("LF_BACKOFFICE RULE route mismatch")

    visual = lf.get("visual_system") or {}
    if visual.get("schema") != "lf_design":
        fail("LF_BACKOFFICE visual schema must be lf_design")
    if visual.get("design_system_code") != "LF_DS_V1":
        fail("LF_BACKOFFICE design system must be LF_DS_V1")
    required_visual = {
        "DESIGN_SYSTEM": "design_systems",
        "COLOR_TOKEN": "color_tokens",
        "TYPOGRAPHY_TOKEN": "typography_tokens",
        "SPACING_TOKEN": "spacing_tokens",
        "RESPONSIVE_TOKEN": "responsive_tokens",
        "COMPONENT_TOKEN": "component_tokens",
        "THEME_BINDING": "theme_bindings",
        "ICON": "icon_catalog",
        "BRAND_ASSET": "brand_assets",
        "VISUAL_DECISION": "visual_decisions",
    }
    mappings = visual.get("mappings") or {}
    for key, table in required_visual.items():
        if mappings.get(key) != table:
            fail(f"LF_BACKOFFICE visual route mismatch {key}")
    if visual.get("rules", {}).get("never_invent_visual_token") is not True:
        fail("LF_BACKOFFICE must forbid invented visual tokens")

    if projects["OVERALL"].get("mappings", {}).get("SCREEN") != "app_screens":
        fail("OVERALL SCREEN route mismatch")
    if projects["SALY"].get("blocked_types", {}).get("SCREEN") != "BLOCKED_NO_DESTINATION":
        fail("SALY SCREEN must remain blocked without authorized destination")

    rules = data.get("rules") or {}
    if rules.get("never_create_table_automatically") is not True:
        fail("automatic table creation must remain forbidden")
    if rules.get("never_fallback_to_public") is not True:
        fail("public fallback must remain forbidden")
    if rules.get("never_cross_project_schema") is not True:
        fail("cross-project schema routing must remain forbidden")

    print("PASS_DATA_PLACEMENT_ROUTER")


if __name__ == "__main__":
    main()
