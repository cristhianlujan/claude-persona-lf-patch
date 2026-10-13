#!/usr/bin/env python3
"""Source-contract audit only: 45 individually scoped validator BINDINGS, not 45 operational PASS receipts.

The existing validators must still run through governed authority, executor and
independent-assurance consumer for operational qualification. Never infer it here.
"""
from __future__ import annotations

import argparse
import ast
import copy
import json
import re
from pathlib import Path

CODES = (
    "PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1",
    "PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1",
    "PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1",
)
STAGES = [f"A{i}" for i in range(1, 16)]
REQUIRED_FIELDS = {"schema", "checkpoint_code", "subject_ref", "criterion",
                   "evidence_must_be_fresh", "prior_done_not_evidence",
                   "acceptance_state", "executable_binding_state", "pass_rule",
                   "failure_rule", "stage_specific_assertion",
                   "acceptance_evidence_fields", "positive_control_spec",
                   "negative_control_spec", "negative_controls"}


def check(catalog, migration, original_validator_source, campaign_validator_source):
    problems = []
    def reject(code, subject):
        problems.append(f"{subject}:{code}")
    if len(catalog.get("units", [])) != 15:
        reject("UNIT_CARDINALITY", "$")
    existing_original = {x.name for x in ast.parse(original_validator_source).body
                         if isinstance(x, (ast.FunctionDef, ast.AsyncFunctionDef))}
    existing_campaign = {x.name for x in ast.parse(campaign_validator_source).body
                         if isinstance(x, (ast.FunctionDef, ast.AsyncFunctionDef))}
    seen = set()
    for idx, unit in enumerate(catalog.get("units", [])):
        stage = f"A{idx+1}"
        if unit.get("unit_code") != stage or unit.get("qualification_unit_code") != stage+"Q":
            reject("UNIT_ORDER_OR_ID", stage)
        checks = unit.get("checkpoints", [])
        if len(checks) != 3:
            reject("CHECKPOINT_COUNT", stage)
        for i, cp in enumerate(checks):
            ident = stage+"Q_C"+str(i+1)
            if cp.get("code") != ident or ident in seen:
                reject("CHECKPOINT_ID_OR_DUPLICATE", ident)
            seen.add(ident)
            contract = cp.get("validator_contract", {})
            if not REQUIRED_FIELDS.issubset(contract):
                reject("CONTRACT_FIELDS_MISSING", ident)
                continue
            if (contract["checkpoint_code"] != ident
                    or contract["subject_ref"] != f"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/{stage}Q/{ident}"):
                reject("SUBJECT_CROSS_BIND", ident)
            if (contract["acceptance_state"] != "NOT_QUALIFIED"
                    or contract["executable_binding_state"] != "AWAITING_EXACT_CONSUMER_ADAPTER_AND_RECEIPT"):
                reject("UNSUPPORTED_ADMISSION", ident)
            if not contract["evidence_must_be_fresh"] or not contract["prior_done_not_evidence"]:
                reject("HISTORICAL_PASS_REUSE", ident)
            if not contract.get("stage_specific_assertion") or not contract.get("criterion"):
                reject("NO_INDIVIDUAL_ASSERTION", ident)
            pos = contract["positive_control_spec"]
            neg = contract["negative_control_spec"]
            if pos.get("stage_specific_assertion") != contract["stage_specific_assertion"]:
                reject("POSITIVE_ASSERTION_MISMATCH", ident)
            if neg.get("expected") != "FAIL_OR_BLOCK_NOT_PASS":
                reject("NEGATIVE_EXPECTATION_MISSING", ident)
            if i == 0:
                if not set(CODES).issubset(set(contract.get("reused_validators", []))):
                    reject("SOURCE_VALIDATOR_NOT_REUSED", ident)
                if "CURRENTNESS_AUTHORITY@1.0.0" not in contract.get("reusable_capabilities", []):
                    reject("CURRENTNESS_AUTHORITY_MISSING", ident)
                structural = contract.get("stage_structure_validator")
                if idx < 9:
                    if not structural or structural.get("path", "").split("/")[-1] != "validate_wave1_boundary_contracts_v1.py":
                        reject("ANALYSIS_STAGE_VALIDATOR_MISSING", ident)
                    elif structural["callable"] not in existing_original:
                        reject("CANONICAL_VALIDATOR_NOT_FOUND", ident)
                elif idx < 14:
                    if (not structural
                            or structural.get("callable") not in existing_campaign
                            or not structural.get("input_source", "").endswith("analysis_evaluation_campaign_contract_v1.json")):
                        reject("CAMPAIGN_SOURCE_VALIDATOR_MISMATCH", ident)
                elif structural is not None:
                    reject("A15_WAVE1_VALIDATOR_MISAPPLIED", ident)
                if idx == 8 and structural and structural.get("callable") != "validate_handoff_parity":
                    reject("A9_CONTRACT_VALIDATOR_NOT_PARITY", ident)
            elif i == 1:
                if contract.get("owner") != "EXISTING_PROFILE_RUNTIME":
                    reject("NO_RUNTIME_REUSE", ident)
                if "profiles/programming_analysis_lf/validators/runtime_validate.py" not in contract.get("reused_validators", []):
                    reject("PROFILE_VALIDATOR_MISSING", ident)
                if "provider_response_id_attested_by_transport" not in contract.get("acceptance_evidence_fields", []):
                    reject("MODEL_ATTESTATION_MISSING", ident)
                if idx == 8 and not any(x.endswith("::validate_programming_snapshot_payload_v1") for x in contract.get("reused_validators", [])):
                    reject("A9_OUTPUT_VALIDATOR_MISSING", ident)
            else:
                if (contract.get("owner") != "INDEPENDENT_ASSURANCE@2.0.1"
                        or contract.get("reused_entrypoint") != "public.lf_independent_review_begin_v3"
                        or not contract.get("independent_reviewer_required")):
                    reject("INDEPENDENT_ASSURANCE_NOT_BOUND", ident)
                if "evidence_ledger_verified_ref" not in contract.get("acceptance_evidence_fields", []):
                    reject("ASSURANCE_LEDGER_ATTESTATION_MISSING", ident)
                if idx == 8:
                    x = contract.get("additional_consumer_guard", {})
                    if x.get("fn") != "programacion.fn_analysis_pg01_exact_receipt_guard_v1":
                        reject("A9_REAL_PG01_REQUIRED", ident)
                if idx == 13:
                    x = contract.get("required_thresholds", {})
                    if x.get("critical_false_ready") != 0 or x.get("classification_accuracy_min") != .95:
                        reject("A14_HOLDOUT_THRESHOLDS_WEAKENED", ident)
                if idx == 14:
                    if contract.get("terminal_dependencies", {}).get("all_earlier_qualifiers_required") != 14:
                        reject("A15_TERMINAL_DEPENDENCIES_MISSING", ident)
    if len(seen) != 45:
        reject("TOTAL_CHECKPOINTS_NOT_45", "$")

    # Verify that the eventual SQL persists exactly the same individual contracts.
    start = migration.find("v_catalog jsonb := '")
    end = migration.find("'::jsonb;", start)
    if start < 0 or end < 0:
        reject("SQL_CATALOG_UNAVAILABLE", "$")
    else:
        embedded = migration[start + len("v_catalog jsonb := '"):end]
        try:
            units_sql = json.loads(embedded.replace("''", "'"))
        except (ValueError, json.JSONDecodeError):
            reject("SQL_CATALOG_INVALID_JSON", "$")
        else:
            if units_sql != catalog["units"]:
                reject("SQL_CATALOG_DRIFT", "$")
    if ("'validator_contract',v_checkpoint->'validator_contract'" not in migration
            or "BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED" not in migration
            or "'PENDING',v_actor" not in migration
            or "v_expected<>45" not in migration):
        reject("FAIL_CLOSED_SQL_GATE_MISSING", "$")
    return problems


def run_selftest(catalog, sql, original, campaign):
    assert not check(catalog, sql, original, campaign), "Baseline source binding must be structurally well formed"
    bad_mutations = [
        ("CHANGED_STAGE_ASSERTION", lambda d: d["units"][1]["checkpoints"][2]["validator_contract"].update(stage_specific_assertion="")),
        ("WRONG_A15_VALIDATOR", lambda d: d["units"][14]["checkpoints"][0]["validator_contract"].update(stage_structure_validator={"callable": "validate_manifest"})),
        ("FALSE_PASS", lambda d: d["units"][0]["checkpoints"][0]["validator_contract"].update(acceptance_state="QUALIFIED")),
        ("A9_CONSUMER_BYPASS", lambda d: d["units"][8]["checkpoints"][2]["validator_contract"].pop("additional_consumer_guard")),
        ("A14_THRESHOLDS_WEAKENED", lambda d: d["units"][13]["checkpoints"][2]["validator_contract"]["required_thresholds"].update(classification_accuracy_min=.90)),
        ("CROSS_SUBJECT", lambda d: d["units"][4]["checkpoints"][2]["validator_contract"].update(subject_ref="PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A6Q/A6Q_C3")),
        ("UNBOUND_RUNTIME", lambda d: d["units"][2]["checkpoints"][1]["validator_contract"].update(reused_validators=[])),
        ("MISSING_CURRENTNESS", lambda d: d["units"][0]["checkpoints"][0]["validator_contract"].update(reusable_capabilities=[])),
    ]
    for name, mutation in bad_mutations:
        subject = copy.deepcopy(catalog)
        mutation(subject)
        errors = check(subject, sql, original, campaign)
        if not errors:
            raise AssertionError("False PASS on negative: " + name)
    print("PASS_45_INDIVIDUAL_BINDINGS_SOURCE_ONLY positives=45 negatives=" + str(len(bad_mutations))
          + " operational_receipts=0 source_only=true")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True)
    p.add_argument("--migration", required=True)
    p.add_argument("--original-validator", required=True)
    p.add_argument("--campaign-validator", required=True)
    x = p.parse_args()
    cat = json.loads(Path(x.catalog).read_text(encoding="utf8"))
    sql = Path(x.migration).read_text(encoding="utf8")
    original = Path(x.original_validator).read_text(encoding="utf8")
    campaign = Path(x.campaign_validator).read_text(encoding="utf8")
    run_selftest(cat, sql, original, campaign)
