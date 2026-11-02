#!/usr/bin/env python3
"""Fail-closed governance check for manually deploying GitHub OIDC Edge."""
import json
import sys

def qualify(doc):
    if not isinstance(doc, dict) or doc.get("name") != "lf-edge-deploy":
        return "ENVIRONMENT_IDENTITY_MISMATCH"
    if doc.get("can_admins_bypass") is not False:
        return "ADMIN_BYPASS_ENABLED_OR_UNKNOWN"
    rules = doc.get("protection_rules")
    if not isinstance(rules, list):
        return "PROTECTION_RULES_MISSING"
    reviewers = [r for r in rules if isinstance(r, dict) and r.get("type") == "required_reviewers"]
    if len(reviewers) != 1:
        return "REQUIRED_REVIEWERS_NOT_CONFIGURED"
    users = reviewers[0].get("reviewers", [])
    if not isinstance(users, list) or not users:
        return "REVIEWER_IDENTITIES_MISSING"
    if not any(isinstance(x,dict) and x.get("reviewer",{}).get("id") for x in users):
        return "REVIEWER_IDENTITIES_MISSING"
    return None

if __name__ == "__main__":
    try:
        result = qualify(json.load(open(sys.argv[1],encoding="utf8")))
    except (OSError, ValueError, IndexError):
        result = "ENVIRONMENT_READBACK_INVALID"
    print(json.dumps({"result":"BLOCKED" if result else "ENVIRONMENT_GOVERNANCE_PASS","reason":result}))
    sys.exit(2 if result else 0)
