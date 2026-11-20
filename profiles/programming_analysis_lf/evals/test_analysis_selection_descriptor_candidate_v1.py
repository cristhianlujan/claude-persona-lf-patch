#!/usr/bin/env python3
"""Non-runtime contract checks for the Analysis LF selector descriptor candidate.

The live Router catalog, business authority, registration, RUN creation,
and semantic selection are NOT tested by this local file.
"""
from pathlib import Path
import copy
import json
import unittest

ROOT=Path(__file__).resolve().parents[1]
DESCRIPTOR=json.loads((ROOT/"contracts/selection_descriptor_candidate_v1.json").read_text())
SOURCE_BINDING=json.loads((ROOT/"contracts/analysis_source_binding.json").read_text())
RUNTIME_BINDING=json.loads((ROOT/"contracts/runtime_binding.json").read_text())
SKILL=(ROOT/"SKILL.md").read_text()

REQUIRED_KINDS={"PURPOSE","ACTIVATION","EXCLUSION"}


def validate(candidate):
    issues=[]
    if not isinstance(candidate,dict):
        return ["CANDIDATE_INVALID"]
    if candidate.get("schema_version")!="LF_PROFILE_SELECTOR_CANDIDATE_PROPOSAL_V1":
        issues.append("CANDIDATE_SCHEMA_INVALID")
    if candidate.get("status")!="CANDIDATE_NOT_REGISTERED":
        issues.append("CANDIDATE_CANNOT_DECLARE_REGISTERED")
    if candidate.get("business")!="LF" or candidate.get("business")!=SOURCE_BINDING["business"]:
        issues.append("BUSINESS_CONTEXT_MISMATCH")
    if candidate.get("profile_code")!=RUNTIME_BINDING["profile_code"] or candidate.get("profile_slug")!=RUNTIME_BINDING["profile_slug"]:
        issues.append("PROFILE_IDENTITY_MISMATCH")
    if candidate.get("source_path")!="profiles/programming_analysis_lf/SKILL.md":
        issues.append("PROFILE_SOURCE_PATH_MISMATCH")
    if candidate.get("operation_code")!="EJECUCION_PERFIL_LF" or candidate.get("action_code")!="PROFILE_EXECUTION":
        issues.append("CANONICAL_OPERATION_MISMATCH")
    proposal=candidate.get("proposed_descriptor")
    if not isinstance(proposal,dict) or proposal.get("schema_version")!="LF_PROFILE_SELECTION_DESCRIPTOR_V1":
        issues.append("DESCRIPTOR_SCHEMA_MISMATCH")
    else:
        entries=proposal.get("selection_evidence")
        if not isinstance(entries,list) or {e.get("kind") for e in entries if isinstance(e,dict)}!=REQUIRED_KINDS:
            issues.append("SEMANTIC_SELECTION_EVIDENCE_INVALID")
        elif any(e.get("source_section") not in ("Purpose","Runtime method capsule","Critical separation") or not e.get("value") for e in entries):
            issues.append("DESCRIPTOR_UNBOUND_TO_SKILL_SECTIONS")
    q=candidate.get("qualification")
    if not isinstance(q,dict) or q.get("status")!="BLOCKED_PENDING_GOVERNED_QUALIFICATION" or any(q.get(key) is not False for key in (
        "source_currentness_verified","source_attestation_A1_A9_verified",
        "router_admission_verified","governed_run_execution_verified",
        "transition_10_1_10_2_verified","model_output_semantic_judge_verified"
    )):
        issues.append("FALSE_OPERATIONAL_QUALIFICATION")
    rules=candidate.get("rules")
    if not isinstance(rules,dict) or any(rules.get(key) is not True for key in (
        "no_direct_router_profile_call","no_manual_run_without_valid_router_handoff",
        "never_infer_current_from_candidate","no_catalog_registration_from_this_file",
        "profile_code_must_be_current_eligible","dynamic_business_source_resolution_required",
        "do_not_hardcode_B2B_target"
    )):
        issues.append("ROUTER_OR_SOURCE_BYPASS")
    return issues


class SelectorCandidateTests(unittest.TestCase):
    def test_01_candidate_consistent_with_current_source(self):
        self.assertEqual(validate(DESCRIPTOR),[])
        self.assertIn("## Purpose",SKILL)
        self.assertIn("## Runtime method capsule",SKILL)
        self.assertIn("## Critical separation",SKILL)

    def test_02_does_not_claim_activation(self):
        self.assertEqual(DESCRIPTOR["status"],"CANDIDATE_NOT_REGISTERED")
        self.assertFalse(DESCRIPTOR["qualification"]["router_admission_verified"])

    def test_03_saly_cannot_use_lf_source_binding(self):
        data=copy.deepcopy(DESCRIPTOR);data["business"]="SALY"
        self.assertIn("BUSINESS_CONTEXT_MISMATCH",validate(data))

    def test_04_bad_profile_identity_blocks(self):
        data=copy.deepcopy(DESCRIPTOR);data["profile_code"]="PERFIL-OTHER"
        self.assertIn("PROFILE_IDENTITY_MISMATCH",validate(data))

    def test_05_cannot_self_promote_current(self):
        data=copy.deepcopy(DESCRIPTOR);data["status"]="CURRENT"
        self.assertIn("CANDIDATE_CANNOT_DECLARE_REGISTERED",validate(data))

    def test_06_cannot_claim_router_qualification(self):
        data=copy.deepcopy(DESCRIPTOR);data["qualification"]["router_admission_verified"]=True
        self.assertIn("FALSE_OPERATIONAL_QUALIFICATION",validate(data))

    def test_07_cannot_claim_direct_router_profile_invocation(self):
        data=copy.deepcopy(DESCRIPTOR);data["rules"]["no_direct_router_profile_call"]=False
        self.assertIn("ROUTER_OR_SOURCE_BYPASS",validate(data))

    def test_08_wrong_operation_rejected(self):
        data=copy.deepcopy(DESCRIPTOR);data["operation_code"]="NEW_ENGINE"
        self.assertIn("CANONICAL_OPERATION_MISMATCH",validate(data))


if __name__=="__main__":
    unittest.main(verbosity=2)
