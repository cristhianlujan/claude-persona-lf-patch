#!/usr/bin/env python3
"""Generic adversarial coverage for derived owner/authority search.

Does not query live DB, claim authority, or grant SUPER_ADMIN permissions.
"""
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT / "validators"))
from producer_depth import _owner_authority_research_errors

historical = json.loads(
    (REPO / "skills/profile_creator/operational_cases/systemic_root_cause_repair_lf/runs/RUN-WEB001-CANDIDATE-20261029.json").read_text()
)
prior_owner = historical["output"]["owner"]
def codes(owner, manifest=None):
    return {r["code"] for r in _owner_authority_research_errors(owner, manifest)}

assert prior_owner["authority_kind"] == "DERIVED_PROPOSAL"
checks = {
    "WEB001_PREVIOUS_ANALOGY_NOW_REJECTED":
        "OWNER_AUTHORITY_SEARCH_REQUIRED" in codes(prior_owner),
}

steps = [
    ("DIRECT_ASSET", "SUPABASE_TABLE_OR_VIEW", "sql:select owner_name from lf_activos where codigo_activo=$1", "NO_MATCH"),
    ("DECLARED_POLICY", "SUPABASE_TABLE_OR_VIEW", "sql:select policy_payload from lf_policy_versions where status='ACTIVE'", "NO_MATCH"),
    ("GOVERNANCE_CONTRACT", "GITHUB_SOURCE", "github://repo@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/contracts/governance.json", "FOUND_CANDIDATE_ONLY"),
]
attempts = [
    {"stage": stage, "surface": surface, "locator": locator,
     "evidence_id": "EV-AUTH-" + str(i), "result": result}
    for i, (stage, surface, locator, result) in enumerate(steps)
]
manifest = {"evidence": [
    {"evidence_id": a["evidence_id"], "source_locator": a["locator"], "state": "CURRENT",
     "digest": "sha256:" + str(i+1)*64,
     "revision_or_observed_at": "2026-10-30T00:00:00Z"}
    for i, a in enumerate(attempts)
]}
owner = copy.deepcopy(prior_owner)
owner["derivation"]["authority_research"] = {
    "scope_classification": "asset owner vs governance custodian vs human authority vs runner",
    "alias_terms": ["asset canonical ID", "owner", "responsable", "governance custodian"],
    "authority_effect": "PROPOSAL_REQUIRES_RATIFICATION",
    "attempts": attempts
}
checks["COMPLETE_SCOPE_SEARCH_ACCEPTED"] = not codes(owner, manifest)
def variant(fn, m=manifest):
    x = copy.deepcopy(owner)
    fn(x["derivation"]["authority_research"])
    return codes(x, m)

checks.update({
    "NO_GITHUB_CONTRACT_REJECTED":
      "OWNER_AUTHORITY_STAGE_ORDER_OR_COVERAGE" in variant(lambda x: x["attempts"].pop()),
    "MISSING_ALIAS_EXPANSION_REJECTED":
      "OWNER_AUTHORITY_ALIAS_EXPANSION_REQUIRED" in variant(lambda x: x.update(alias_terms=["ACT-0058"])),
    "NO_RATIFICATION_REJECTED":
      "OWNER_AUTHORITY_RATIFICATION_REQUIRED" in variant(lambda x: x.update(authority_effect="AUTO_ASSIGN")),
    "POLICY_NOT_GENERAL_LOOKUP_REJECTED":
      "OWNER_AUTHORITY_GENERAL_POLICY_LOOKUP_REQUIRED" in variant(lambda x: x["attempts"][1].update(locator=x["attempts"][0]["locator"])),
    "GITHUB_NOT_IN_SOURCE_CLASS_REJECTED":
      "OWNER_AUTHORITY_GITHUB_NOT_CHECKED" in variant(lambda x: x["attempts"][2].update(surface="SUPABASE_TABLE_OR_VIEW")),
    "WRONG_EVIDENCE_ID_REJECTED":
      "OWNER_AUTHORITY_EVIDENCE_NOT_CURRENT" in variant(lambda x: x["attempts"][1].update(evidence_id="EV-OTHER")),
    "BORROWED_LOCATOR_REJECTED":
      "OWNER_AUTHORITY_EVIDENCE_LOCATOR_MISMATCH" in variant(lambda x: x["attempts"][2].update(locator="github://other")),
    "STALE_MANIFEST_REJECTED":
      "OWNER_AUTHORITY_EVIDENCE_NOT_CURRENT" in codes(owner, {"evidence": [
          dict(y, state="SUPERSEDED") if i == 2 else y
          for i, y in enumerate(manifest["evidence"])
      ]}),
    "ACCESS_ERROR_REQUIRED":
      "OWNER_AUTHORITY_ACCESS_ERROR_REQUIRED" in variant(lambda x: x["attempts"][2].update(result="NO_SOURCE_ACCESSIBLE")),
    "ACCESS_ERROR_EXPLICIT_IS_RECORDED":
      not variant(lambda x: x["attempts"][2].update(result="NO_SOURCE_ACCESSIBLE", error_detail="GITHUB_READER_NOT_AVAILABLE")),
    "EVIDENCE_REUSE_REJECTED":
      "OWNER_AUTHORITY_EVIDENCE_REUSED" in variant(lambda x: x["attempts"][2].update(evidence_id=x["attempts"][1]["evidence_id"])),
    "SOURCE_POLICY_STAGE_MUST_BE_DB":
      "OWNER_AUTHORITY_POLICY_NOT_CHECKED" in variant(lambda x: x["attempts"][1].update(surface="GITHUB_SOURCE")),
    "UNRELATED_AUTHORITATIVE_OWNER_UNCHANGED":
      not codes({"authority_kind": "EXISTING_AUTHORITY"}, None),
})
for name, passed in checks.items():
    print(("PASS " if passed else "FAIL ")+name)
print("OWNER_AUTHORITY_DISCOVERY_CASES="+str(sum(checks.values()))+"/"+str(len(checks)))
raise SystemExit(0 if all(checks.values()) else 1)
