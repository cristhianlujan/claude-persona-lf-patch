"""Check rule -> criterion -> test traceability chain. J07 support."""
import sys

from lf_common import argv_path, emit, load


def main():
    pack = load(argv_path(1))
    criteria = pack.get("core", {}).get("acceptance_criteria", [])
    tests = pack.get("tests", [])
    rules = pack.get("validations", [])
    criteria_ids = {c.get("criterion_code") for c in criteria if isinstance(c, dict)}
    covered = set()
    orphan_tests = []
    for test in tests:
        ref = test.get("criterion_ref")
        if ref in criteria_ids:
            covered.add(ref)
        else:
            orphan_tests.append(test.get("test_code"))
    uncovered = sorted(criteria_ids - covered)
    rules_without_source = [
        r.get("validation_code") for r in rules if not r.get("source_ref")]
    failed = []
    if uncovered:
        failed.append("criteria_without_test_reference=%d" % len(uncovered))
    if orphan_tests:
        failed.append("tests_without_story_reference=%d" % len(orphan_tests))
    if rules_without_source:
        failed.append("rules_without_source_reference=%d" % len(rules_without_source))
    evidence = {
        "criteria_count": len(criteria_ids),
        "tests_count": len(tests),
        "uncovered_criteria": uncovered,
        "orphan_tests": orphan_tests,
        "traceability_breaks": len(uncovered) + len(orphan_tests),
    }
    return emit("J07_AUDIT_TRACEABILITY", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
