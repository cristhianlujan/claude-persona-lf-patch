#!/usr/bin/env python3
"""Product Director RAW origin preflight: one narrowly bounded, auditable self-repair.

Never invents policy, changes decisions or authority, or claims a model invocation.
The canonical schema/validator remains the authority for both passes.
"""
import copy
import json
import sys

from validate_product_director_output import validate


def prepare(payload):
    initial = validate(payload)
    if initial["valid"]:
        return {"status": "UNCHANGED_VALID", "profile_output": payload,
                "added_qualifiers": [], "original_blocking_codes": []}
    codes = initial["blocking_codes"]
    if codes != ["HANDOFF_QUALIFIER_LOSS"]:
        return {"status": "BLOCKED", "profile_output": None,
                "added_qualifiers": [], "original_blocking_codes": codes}

    # Repair only literal preservation of information already in the decision.
    try:
        decision = payload["deliverable_created"]["product_decision"]
        handoff = payload["deliverable_created"]["handoff_to_next"]
        qualifiers = decision["semantic_qualifiers"]
        preserved = handoff["qualifiers_to_preserve"]
        if (not isinstance(qualifiers, list) or not isinstance(preserved, list)
                or not all(isinstance(q, str) and q.strip() for q in qualifiers + preserved)):
            raise ValueError("QUALIFIERS_INVALID")
        missing = [q for q in qualifiers if q not in preserved]
        if not missing:
            raise ValueError("NO_SAFE_EXACT_REPAIR")
        candidate = copy.deepcopy(payload)
        candidate["deliverable_created"]["handoff_to_next"]["qualifiers_to_preserve"].extend(missing)
    except (KeyError, TypeError, ValueError):
        return {"status": "BLOCKED", "profile_output": None,
                "added_qualifiers": [], "original_blocking_codes": codes}

    # Exactly one repair attempt; never relax another failing control.
    final = validate(candidate)
    if not final["valid"]:
        return {"status": "BLOCKED", "profile_output": None,
                "added_qualifiers": [], "original_blocking_codes": sorted(set(codes + final["blocking_codes"]))}
    return {"status": "SELF_REPAIRED_HANDOFF_QUALIFIERS",
            "profile_output": candidate, "added_qualifiers": missing,
            "original_blocking_codes": codes}


if __name__ == "__main__":
    try:
        receipt = prepare(json.load(sys.stdin))
        print(json.dumps(receipt, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        sys.exit(0 if receipt["status"] != "BLOCKED" else 2)
    except (TypeError, ValueError, json.JSONDecodeError):
        print(json.dumps({"status": "BLOCKED", "profile_output": None,
                          "added_qualifiers": [], "original_blocking_codes": ["MALFORMED_INPUT"]}))
        sys.exit(2)
