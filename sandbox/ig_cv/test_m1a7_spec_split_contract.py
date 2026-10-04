#!/usr/bin/env python3
import copy
import json
from pathlib import Path

MANIFEST = Path(__file__).parents[2] / "docs/input-governance/input_readiness_spec_split_5_13_v1.json"
VALID_CLASSES = {
    "PRODUCTION": "CURATOR",
    "ACCEPTANCE": "VALIDATOR",
    "FAMILY": "FAMILY_POLICY_AUTHORITY",
}


def validate(data):
    rows = data["classification"]
    keys = [r["clause_key"] for r in rows]
    if len(rows) != 60 or len(set(keys)) != 60:
        raise AssertionError("M1A7_CLAUSE_CARDINALITY_OR_DUPLICATION")
    for row in rows:
        expected_owner = VALID_CLASSES.get(row["rule_class"])
        if expected_owner is None:
            raise AssertionError("M1A7_UNKNOWN_RULE_CLASS")
        if row["responsibility_owner"] != expected_owner:
            raise AssertionError(
                f"M1A7_OWNER_MISMATCH:{row['clause_key']}:{row['rule_class']}:{row['responsibility_owner']}"
            )
        if not row["enforcement_owner"] or not row["authority_ref"]:
            raise AssertionError(f"M1A7_OWNER_OR_AUTHORITY_MISSING:{row['clause_key']}")
    counts = {c: sum(r["rule_class"] == c for r in rows) for c in VALID_CLASSES}
    declared = {c: data["partition_contract"]["classes"][c]["count"] for c in VALID_CLASSES}
    if counts != declared:
        raise AssertionError(f"M1A7_DECLARED_COUNT_MISMATCH:{counts}:{declared}")
    if data["source_contract"]["clause_bodies_duplicated"] is not False:
        raise AssertionError("M1A7_CLAUSE_BODY_DUPLICATION_NOT_FORBIDDEN")
    return True


def negative_probe(data):
    mutated = copy.deepcopy(data)
    target = next(r for r in mutated["classification"] if r["rule_class"] == "ACCEPTANCE")
    target["responsibility_owner"] = "CURATOR"
    try:
        validate(mutated)
    except AssertionError as exc:
        if not str(exc).startswith("M1A7_OWNER_MISMATCH:"):
            raise
        return True
    raise AssertionError("M1A7_NEGATIVE_PROBE_FALSE_GREEN")


if __name__ == "__main__":
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert validate(data)
    assert negative_probe(data)
    print("M1A7_SPEC_SPLIT_PASS clauses=60 production=45 acceptance=12 family=3 negative=DETECTED")
