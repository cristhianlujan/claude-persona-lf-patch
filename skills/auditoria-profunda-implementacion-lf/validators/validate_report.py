#!/usr/bin/env python3
"""Validate structure, source bindings and claim sufficiency, not model provenance."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

PACK = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACK / "scripts"))
from assess_contracts import assess_authorization


def file_at(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("EVIDENCE_PATH_OUTSIDE_REPOSITORY:" + relative)
    return path


def resolve_ref(root, ref, bound):
    path, _, fragment = ref.partition("#")
    if path not in bound:
        raise ValueError("UNBOUND_EVIDENCE_REF:" + ref)
    target = file_at(root, path)
    if fragment:
        if not fragment.startswith("/"):
            raise ValueError("UNSUPPORTED_EVIDENCE_FRAGMENT:" + ref)
        value = json.loads(target.read_text(encoding="utf8"))
        for key in fragment[1:].split("/"):
            key = key.replace("~1", "/").replace("~0", "~")
            value = value[int(key)] if isinstance(value, list) else value[key]
        return value
    return json.loads(target.read_text(encoding="utf8")) if target.suffix == ".json" else target


def validate(report, root):
    schema = json.loads((PACK / "schemas/output.schema.json").read_text(encoding="utf8"))
    Draft202012Validator.check_schema(schema)
    errors = ["SCHEMA:" + "/".join(map(str, e.absolute_path)) + ":" + e.message
              for e in Draft202012Validator(schema).iter_errors(report)]
    if errors:
        return errors
    if report["status"] == "READY_FOR_JUDGE" and sorted(report["phases"]) != list(range(1, 7)):
        errors.append("PHASE_COVERAGE_INCOMPLETE")
    # An offline validator never grants authority. A true flag needs a separately
    # resolved CURRENT governance readback, checked by the native auditor.
    if report["promotion_authorized"] and not report["authority_ref"]:
        errors.append("PROMOTION_AUTHORITY_READBACK_REQUIRED")
    bound = report["evidence_files"]
    for name, sha in bound.items():
        try:
            actual = hashlib.sha256(file_at(root, name).read_bytes()).hexdigest()
            if actual != sha:
                errors.append("EVIDENCE_HASH_MISMATCH:" + name)
        except (ValueError, OSError) as exc:
            errors.append(str(exc))
    def refs(values):
        for ref in values:
            try:
                resolve_ref(root, ref, bound)
            except (ValueError, TypeError, KeyError, IndexError, OSError, json.JSONDecodeError) as exc:
                errors.append("EVIDENCE_UNRESOLVED:" + ref + ":" + str(exc))
    if report["authority_ref"]:
        refs([report["authority_ref"]])
    if report["promotion_authorized"] and report["authority_ref"]:
        try:
            authority = resolve_ref(root, report["authority_ref"], bound)
            auth_schema = json.loads((PACK / "schemas/authority_evidence.schema.json").read_text())
            problems = list(Draft202012Validator(auth_schema).iter_errors(authority))
            if problems:
                errors.append("AUTHORITY_READBACK_CONTRACT_INVALID")
            elif not assess_authorization(authority["evaluation"], authority["policy"], authority["evidence"])["promotion_authorized"]:
                errors.append("AUTHORITY_POLICY_DOES_NOT_AUTHORIZE_EFFECT")
        except (ValueError, TypeError, KeyError, OSError, IndexError) as exc:
            errors.append("AUTHORITY_NOT_RESOLVED:" + str(exc))
    identifiers = set()
    for finding in report["findings"]:
        ident = finding["id"]
        if ident in identifiers:
            errors.append("DUPLICATE_FINDING_ID:" + ident)
        identifiers.add(ident)
        loc = finding["location"]
        try:
            path = file_at(root, loc["file"])
            data = path.read_bytes()
            lines = data.decode("utf8").splitlines()
            if loc["end_line"] < loc["start_line"] or loc["end_line"] > len(lines):
                errors.append("LOCATION_RANGE_INVALID:" + ident)
            literal = "\n".join(lines[loc["start_line"] - 1:loc["end_line"]])
            if literal != finding["found_code"]:
                errors.append("LITERAL_SOURCE_MISMATCH:" + ident)
            if hashlib.sha256(data).hexdigest() != loc["sha256"]:
                errors.append("LOCATION_HASH_MISMATCH:" + ident)
            if loc["commit"] != "WORKTREE_UNCOMMITTED_FIXTURE":
                base_data = subprocess.check_output(["git", "show", loc["commit"] + ":" + loc["file"]], cwd=root)
                if base_data != data:
                    errors.append("LOCATION_COMMIT_DRIFT:" + ident)
        except (ValueError, OSError, subprocess.CalledProcessError) as exc:
            errors.append("LOCATION_UNRESOLVED:" + ident + ":" + str(exc))
        refs(finding["expected"]["contract_refs"])
        refs(finding["observed_result"]["evidence_refs"])
        refs(finding["readback"]["evidence_refs"])
        for probe in (finding["positive_test"], finding["negative_test"]):
            if probe["evidence_ref"]:
                refs([probe["evidence_ref"]])
        if finding["status"] in ("CONFIRMED", "FIX_VERIFIED"):
            if not (finding["observed_result"]["executed"] and finding["readback"]["verified"]
                    and finding["observed_result"]["evidence_refs"] and finding["readback"]["evidence_refs"]
                    and finding["positive_test"]["executed"] and finding["negative_test"]["executed"]
                    and finding["positive_test"]["evidence_ref"] and finding["negative_test"]["evidence_ref"]):
                errors.append("CONFIRMATION_EVIDENCE_INSUFFICIENT:" + ident)
        if finding["status"] == "FIX_VERIFIED":
            if not (finding["before_ref"] and finding["after_ref"] and finding["fix_scope"] != "NONE"):
                errors.append("FIX_BEFORE_AFTER_REQUIRED:" + ident)
            else:
                refs([finding["before_ref"], finding["after_ref"]])
    for edge in report["behavior_chain"]:
        refs(edge["evidence_refs"])
    for check in report["checklist"]:
        refs(check["evidence_refs"])
        if check["result"] == "NOT_APPLICABLE" and check["applies"]:
            errors.append("CHECKLIST_APPLICABILITY_CONTRADICTION:" + check["ekb_code"])
        if check["result"] == "REVIEWED" and not check["evidence_refs"]:
            errors.append("CHECKLIST_EVIDENCE_REQUIRED:" + check["ekb_code"])
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    errors = validate(json.loads(args.report.read_text(encoding="utf8")), args.repo_root)
    print(json.dumps({"status": "PASS" if not errors else "FAIL", "errors": errors}, ensure_ascii=False, indent=2))
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
