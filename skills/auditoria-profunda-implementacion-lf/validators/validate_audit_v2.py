#!/usr/bin/env python3
"""Validate report accounting and evidence labels; no external permission granted."""
import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from jsonschema import Draft202012Validator

PACK = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACK / "scripts"))
from audit_v2 import STEP_ORDERS, contract_grade, flow_verdict, lot_coverage, materialization_assessment, plan_summary, sample_metrics
from assess_contracts import assess_authorization


def local_ref(root, ref):
    name, _, pointer = ref.partition("#")
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError("CAPTURE_NOT_RESOLVED:" + ref)
    if pointer:
        value = json.loads(path.read_text())
        if not pointer.startswith("/"): raise ValueError("CAPTURE_POINTER_INVALID:" + ref)
        for key in pointer[1:].split("/"):
            key = key.replace("~1", "/").replace("~0", "~")
            value = value[int(key)] if isinstance(value, list) else value[key]
        return value
    return path


def validate(report, root):
    schema = json.loads((PACK / "schemas/audit_report_v2.schema.json").read_text())
    errors = ["SCHEMA:" + "/".join(map(str, e.absolute_path)) + ":" + e.message
              for e in Draft202012Validator(schema).iter_errors(report)]
    if errors: return errors
    evidence = {e["id"]: e for e in report["evidence_catalog"]}
    if len(evidence) != len(report["evidence_catalog"]): errors.append("DUPLICATE_EVIDENCE_ID")
    for e in evidence.values():
        try:
            local_ref(root, e["capture_ref"])
            file = local_ref(root, e["capture_ref"].partition("#")[0])
            if hashlib.sha256(file.read_bytes()).hexdigest() != e["capture_sha256"]:
                errors.append("CAPTURE_HASH_DRIFT:" + e["id"])
        except (ValueError, OSError, KeyError, IndexError, TypeError) as exc: errors.append(str(exc))
        if e["kind"] == "MEASURED_THIS_AUDIT" and e["origin"] in ("SOURCE_FILE", "PRIOR_REPORT", "NONE"):
            errors.append("STATIC_OR_PRIOR_MISLABELED_CURRENT:" + e["id"])
        if e["kind"] == "CODE_READ_ONLY" and e["origin"] != "SOURCE_FILE":
            errors.append("CODE_EVIDENCE_ORIGIN_MISMATCH:" + e["id"])
        if e["kind"] == "MEASURED_PREVIOUSLY" and not e["observed_at"]:
            errors.append("PRIOR_EVIDENCE_DATE_REQUIRED:" + e["id"])
    def refs(values, owner):
        for ref in values:
            if ref not in evidence: errors.append("EVIDENCE_ID_UNKNOWN:" + owner + ":" + ref)
    for check in report["checklist"]:
        refs(check["evidence_refs"], check["ekb_code"])
        if check["applies"] and check["result"] == "NOT_APPLICABLE":
            errors.append("CHECKLIST_APPLICABILITY_CONTRADICTION:" + check["ekb_code"])
        if check["result"] == "REVIEWED" and not check["evidence_refs"]:
            errors.append("CHECKLIST_EVIDENCE_REQUIRED:" + check["ekb_code"])
    if sorted(s["order"] for s in report["steps"]) != list(STEP_ORDERS):
        errors.append("ELEVEN_STEP_LEDGER_REQUIRED")
    for step in report["steps"]:
        refs(step["evidence_refs"], "step:" + str(step["order"]))
        refs(step["resolved_receipts"], "resolved-step:" + str(step["order"]))
        if step["behavior_status"] == "EXECUTED_AND_VERIFIED" and not step["resolved_receipts"]:
            errors.append("EXECUTION_CLAIM_WITHOUT_RESOLVED_RECEIPT:" + str(step["order"]))
        if step["runtime_origin"] == "NEW_AUDIT_RUN":
            for ref in step["resolved_receipts"]:
                ev = evidence.get(ref, {})
                if ev.get("origin") != "LIVE_NEW_RUN" or ev.get("source_execution_id") != step["execution_id"]:
                    errors.append("NEW_RUN_RECEIPT_PROVENANCE_INVALID:" + str(step["order"]))
        if step["execution_id"] != report["audit_context"]["source_execution_id"]:
            errors.append("STEP_RUN_MISMATCH:" + str(step["order"]))
    required_hops = set(zip(STEP_ORDERS, STEP_ORDERS[1:]))
    got_hops = {(h["from_step"], h["to_step"]) for h in report["hops"]}
    if not required_hops.issubset(got_hops): errors.append("HOP_MATRIX_INCOMPLETE")
    for hop in report["hops"]: refs(hop["evidence_refs"], hop["id"])
    for task in report["audit_tasks"]:
        refs(task["evidence_refs"], task["id"])
        if task["status"] == "VERIFIED" and not task["evidence_refs"]:
            errors.append("VERIFIED_TASK_WITHOUT_EVIDENCE:" + task["id"])
        if task["status"] == "NOT_APPLICABLE" and not task["reason"]:
            errors.append("UNJUSTIFIED_TASK_NA:" + task["id"])
    expected_coverage = lot_coverage(report["audit_tasks"])["percent"]
    if report["completion"]["lot_coverage_percent"] != expected_coverage:
        errors.append("LOT_PERCENT_DOES_NOT_MATCH_CHECKS")
    expected_flow = flow_verdict(report)
    if report["completion"]["flow_verdict"] != expected_flow["verdict"]:
        errors.append("FLOW_VERDICT_OVERCLAIM")
    if report["completion"]["flow_reasons"] != expected_flow["reasons"]:
        errors.append("FLOW_REASON_DRIFT")
    ctx = report["audit_context"]
    if ctx["promotion_authorized"]:
        authority = evidence.get(ctx["authority_ref"], {})
        try:
            if authority.get("kind") != "MEASURED_THIS_AUDIT" or authority.get("origin") not in ("LIVE_EXISTING_RUN", "LIVE_NEW_RUN"):
                raise ValueError("PROMOTION_AUTHORITY_CURRENT_READBACK_REQUIRED")
            value = local_ref(root, authority["capture_ref"])
            if isinstance(value, Path): value = json.loads(value.read_text())
            auth_schema = json.loads((PACK / "schemas/authority_evidence.schema.json").read_text())
            if list(Draft202012Validator(auth_schema).iter_errors(value)):
                raise ValueError("AUTHORITY_READBACK_CONTRACT_INVALID")
            if not assess_authorization(value["evaluation"], value["policy"], value["evidence"])["promotion_authorized"]:
                raise ValueError("AUTHORITY_POLICY_DOES_NOT_AUTHORIZE_EFFECT")
        except (ValueError, OSError, KeyError, TypeError) as exc: errors.append(str(exc))
    if ctx["new_e2e_executed"]:
        try:
            began = dt.datetime.fromisoformat(ctx["started_at"].replace("Z", "+00:00"))
            run_began = dt.datetime.fromisoformat(ctx["source_run_started_at"].replace("Z", "+00:00"))
            if run_began < began: errors.append("HISTORICAL_RUN_IS_NOT_NEW_E2E")
        except (ValueError, TypeError, AttributeError): errors.append("NEW_E2E_TIME_BINDING_REQUIRED")
    profiles = json.loads((PACK / "references/contract_profiles_v2.json").read_text())["profiles"]
    for contract in report["contracts"]:
        grade = contract_grade(contract, profiles)
        errors.extend(contract["id"] + ":" + e for e in grade["errors"])
        if contract["grade"] != grade["grade"]: errors.append("CONTRACT_GRADE_OVERCLAIM:" + contract["id"])
        for name, cell in contract["fields"].items():
            if cell["literal"]:
                found = False
                for ref in cell["source_refs"]:
                    try:
                        source = local_ref(root, ref.partition("#")[0])
                        found = found or cell["literal"] in source.read_text()
                    except (ValueError, OSError): pass
                if not found: errors.append("CONTRACT_LITERAL_UNRESOLVED:" + contract["id"] + ":" + name)
    for query in report["sql_queries"]:
        refs(query["evidence_refs"], query["id"])
        if query["measurement_status"] == "MEASURED":
            if not (query["transaction_read_only"] and query["rollback_included"] and query["sample_count"] > 0
                    and type(query["execution_ms"]) in (int, float) and query["evidence_refs"]):
                errors.append("QUERY_MEASUREMENT_UNSUPPORTED:" + query["id"])
            matched = False
            for ref in query["evidence_refs"]:
                ev = evidence.get(ref, {})
                if ev.get("origin") != "LIVE_QUERY_PLAN" or ev.get("kind") != "MEASURED_THIS_AUDIT": continue
                try:
                    value = local_ref(root, ev["capture_ref"])
                    summary = plan_summary(value["plan"])
                    matched = matched or (value["sql"] == query["sql"] and all(query[k] == summary[k]
                        for k in ("execution_ms", "shared_hit_blocks", "shared_read_blocks")))
                except (ValueError, OSError, KeyError, IndexError, TypeError): pass
            if not matched: errors.append("QUERY_METRICS_OR_SQL_CAPTURE_DRIFT:" + query["id"])
        elif query["execution_ms"] is not None or query["sample_count"] != 0:
            errors.append("UNMEASURED_QUERY_HAS_METRICS:" + query["id"])
        if query["materialization_decision"] == "OPTIONAL_CANDIDATE":
            basis = query["materialization_basis"] or {}
            if (not query["frequency_measured"] or not query["frequency_source"]
                    or materialization_assessment(basis)["decision"] != "OPTIONAL_CANDIDATE"):
                errors.append("MATERIALIZATION_WITHOUT_MEASURED_BENEFIT_AND_SAFETY:" + query["id"])
    sample = report["run_sample"]
    refs(sample["evidence_refs"], "run_sample")
    sample_checked = False
    for ref in sample["evidence_refs"]:
        try:
            value = local_ref(root, evidence[ref]["capture_ref"])
            if isinstance(value, list) and (not value or "pass_steps" in value[0]):
                sample_checked = True
                if sample_metrics(value) != sample["metrics"] or len(value) != sample["sampled_runs"]:
                    errors.append("COHORT_METRICS_DRIFT")
        except (ValueError, OSError, KeyError, TypeError): pass
    if not sample_checked: errors.append("COHORT_EVIDENCE_NOT_RESOLVED")
    for emitter in report["pass_emitters"]:
        try:
            file = local_ref(root, emitter["file"])
            if (hashlib.sha256(file.read_bytes()).hexdigest() != emitter["source_sha256"]
                    or file.read_text().splitlines()[emitter["line"] - 1] != emitter["literal"]):
                errors.append("PASS_SOURCE_READBACK_DRIFT:" + emitter["id"])
        except (OSError, ValueError, IndexError) as exc: errors.append(str(exc))
        refs(emitter["negative_test"]["evidence_refs"], emitter["id"])
        if emitter["classification"] == "EMITTER" and not emitter["evidence_required"]:
            errors.append("PASS_REQUIRED_EVIDENCE_NOT_REVIEWED:" + emitter["id"])
        negative = emitter["negative_test"]
        if negative["status"] != "NOT_EXECUTED" and not (negative["command"] and negative["evidence_refs"]):
            errors.append("PASS_NEGATIVE_EXECUTION_NOT_PROVEN:" + emitter["id"])
    ids = set()
    for finding in report["findings"]:
        if finding["id"] in ids: errors.append("DUPLICATE_FINDING_ID:" + finding["id"])
        ids.add(finding["id"])
        refs(finding["current_audit_evidence_refs"], finding["id"])
        kinds = {evidence[r]["kind"] for r in finding["current_audit_evidence_refs"] if r in evidence}
        if finding["evidence_kind"] == "MEASURED_THIS_AUDIT" and "MEASURED_THIS_AUDIT" not in kinds:
            errors.append("FINDING_MEASUREMENT_NOT_CURRENT:" + finding["id"])
        loc = finding["location"]
        try:
            file = local_ref(root, loc["file"])
            data = file.read_bytes(); lines = data.decode().splitlines()
            if loc["end_line"] < loc["start_line"] or loc["end_line"] > len(lines):
                errors.append("LOCATION_RANGE_INVALID:" + finding["id"])
            if "\n".join(lines[loc["start_line"] - 1:loc["end_line"]]) != finding["found_code"]:
                errors.append("LITERAL_SOURCE_MISMATCH:" + finding["id"])
            if hashlib.sha256(data).hexdigest() != loc["sha256"]:
                errors.append("LOCATION_HASH_MISMATCH:" + finding["id"])
            if loc["commit"] != "WORKTREE_UNCOMMITTED_FIXTURE":
                baseline = subprocess.check_output(["git", "show", loc["commit"] + ":" + loc["file"]], cwd=root, stderr=subprocess.DEVNULL)
                if baseline != data: errors.append("LOCATION_COMMIT_DRIFT:" + finding["id"])
        except (ValueError, OSError, subprocess.CalledProcessError) as exc: errors.append(str(exc))
        frefs = finding["expected"]["contract_refs"] + finding["observed_result"]["evidence_refs"] + finding["readback"]["evidence_refs"]
        frefs += [t["evidence_ref"] for t in (finding["positive_test"], finding["negative_test"]) if t["evidence_ref"]]
        for ref in frefs:
            try: local_ref(root, ref)
            except (ValueError, OSError, KeyError, IndexError, TypeError) as exc: errors.append(str(exc))
        if finding["status"] in ("CONFIRMED", "FIX_VERIFIED") and not (
                finding["observed_result"]["executed"] and finding["readback"]["verified"]
                and finding["positive_test"]["executed"] and finding["negative_test"]["executed"]
                and finding["positive_test"]["evidence_ref"] and finding["negative_test"]["evidence_ref"]):
            errors.append("CONFIRMATION_EVIDENCE_INSUFFICIENT:" + finding["id"])
        if finding["status"] == "FIX_VERIFIED":
            if not finding["before_ref"] or not finding["after_ref"] or finding["fix_scope"] == "NONE":
                errors.append("FIX_BEFORE_AFTER_REQUIRED:" + finding["id"])
            else:
                for ref in (finding["before_ref"], finding["after_ref"]):
                    try: local_ref(root, ref)
                    except (ValueError, OSError, KeyError, IndexError, TypeError) as exc: errors.append(str(exc))
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path); parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    errors = validate(json.loads(args.report.read_text()), args.repo_root)
    print(json.dumps({"status": "PASS" if not errors else "FAIL", "errors": errors}, ensure_ascii=False, indent=2))
    raise SystemExit(bool(errors))
