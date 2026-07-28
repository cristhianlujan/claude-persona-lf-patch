"""Validate one Story Pack against the canonical A-Q section contract. J03 support."""
import sys

from lf_common import argv_path, emit, load

SECTIONS = [
    "identity", "core", "interaction", "fields", "validations", "observations",
    "errors", "security_privacy", "states", "audit", "tokens_messages",
    "analytics", "observability", "responsive_accessibility", "tests",
    "dependencies_risks", "judges_evidence",
]
CORE_KEYS = [
    "actor", "need", "benefit", "preconditions", "trigger", "main_flow",
    "alternative_flows", "postconditions", "acceptance_criteria", "out_of_scope",
]


def main():
    pack = load(argv_path(1))
    failed = []
    missing_sections = [s for s in SECTIONS if s not in pack]
    if missing_sections:
        failed.append("missing_sections=%d" % len(missing_sections))
    core = pack.get("core", {})
    missing_core = [k for k in CORE_KEYS if not core.get(k)]
    if missing_core:
        failed.append("core_keys_missing=%d" % len(missing_core))
    criteria = core.get("acceptance_criteria", [])
    no_gwt = [c for c in criteria if not (
        isinstance(c, dict) and c.get("given") and c.get("when") and c.get("then"))]
    if no_gwt:
        failed.append("criteria_without_given_when_then=%d" % len(no_gwt))
    if not pack.get("identity", {}).get("source_decision_id"):
        failed.append("stories_without_source_trace=1")
    evidence = {
        "sections_present": len(SECTIONS) - len(missing_sections),
        "sections_expected": len(SECTIONS),
        "acceptance_criteria_count": len(criteria),
        "missing_sections": missing_sections,
        "missing_core_keys": missing_core,
    }
    return emit("J03_STORY_CORE", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
