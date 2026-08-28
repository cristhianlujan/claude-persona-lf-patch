#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "validators" / "validate_frontend_artifact.py"
HTML_SCHEMA_PATH = ROOT / "schemas" / "html_sandbox_output.schema.json"
MISSING_SCHEMA_PATH = ROOT / "schemas" / "frontend_missing_input.schema.json"
SCOPE_BLOCK_SCHEMA_PATH = ROOT / "schemas" / "frontend_scope_block.schema.json"

spec = importlib.util.spec_from_file_location("frontend_validator", VALIDATOR_PATH)
validator = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(validator)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def score():
    names = [
        "Source fidelity",
        "Static implementation quality",
        "Accessibility and semantic structure",
        "Boundary control",
        "Handoff/readback readiness",
    ]
    return {
        "total": 25,
        "criteria": [
            {"criterion": name, "points": 5, "evidence_refs": [f"evidence:{idx}:{name}"]}
            for idx, name in enumerate(names, 1)
        ],
    }


def base_payload(workspace: Path, mode: str = "CREATE_AND_VERIFY_ARTIFACT") -> dict:
    product = b"product direction: approved current\n"
    ui = b"ui architect: approved current\n"
    html = b"<!doctype html><html><head><title>LF</title></head><body><main><button>Continuar</button></main></body></html>"
    (workspace / "upstream").mkdir(parents=True, exist_ok=True)
    (workspace / "sandbox_runs/case").mkdir(parents=True, exist_ok=True)
    (workspace / "upstream/product.md").write_bytes(product)
    (workspace / "upstream/ui.md").write_bytes(ui)
    (workspace / "sandbox_runs/case/index.html").write_bytes(html)

    artifact_evidence = []
    if mode == "CREATE_AND_VERIFY_ARTIFACT":
        artifact_evidence = [{
            "path": "sandbox_runs/case/index.html",
            "declared_sha256": sha(html),
            "readback_sha256": sha(html),
            "bytes": len(html),
            "exists": True,
            "readback": True,
            "parse_status": "HTML_PARSE_PASS",
        }]

    return {
        "worker": "frontend_prototype_architect_lf",
        "output_type": "HTML_SANDBOX_SPEC",
        "deliverable_created": {
            "prototype_decision": {"execution_mode": mode, "summary": "static checkout prototype"},
            "source_inputs": [
                {"authority_role": "PRODUCT_DIRECTION", "source_ref": "upstream/product.md", "source_sha256": sha(product), "currentness": "CURRENT", "verdict": "APPROVED"},
                {"authority_role": "UI_ARCHITECT", "source_ref": "upstream/ui.md", "source_sha256": sha(ui), "currentness": "CURRENT", "verdict": "PASS"},
            ],
            "files_to_create": ["sandbox_runs/case/index.html"],
            "artifact_evidence": artifact_evidence,
            "html_structure": {"main": ["button"]},
            "css_structure": {"layout": "static"},
            "accessibility_baseline": ["semantic main", "keyboard button"],
            "interaction_states": ["idle/default", "loading:not-applicable-static", "empty:not-applicable-static", "error:not-applicable-static", "success:not-applicable-static"],
            "forbidden_runtime_scope": ["backend", "api", "database", "auth", "production"],
            "validation_checklist": ["button remains in main and preserves upstream CTA intent"],
            "local_run_instructions": ["open sandbox_runs/case/index.html"],
            "handoff_to_next": {"target": "QA"},
            "traceability": {"changed_now": ["artifact provenance hardening"]},
        },
        "score": score(),
        "self_verdict": "PASS_ARTIFACT_VERIFIED" if mode == "CREATE_AND_VERIFY_ARTIFACT" else "ADVISORY_COMPLETE",
        "traceability": {"audit_lot": "20260827"},
    }


def schema_validate(payload: dict, schema_path: Path = HTML_SCHEMA_PATH) -> tuple[bool, str]:
    import jsonschema
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    try:
        jsonschema.Draft202012Validator(schema).validate(payload)
        return True, "PASS"
    except jsonschema.ValidationError as exc:
        return False, exc.message


def run_case(name: str, mutate, expect_validator: bool, expect_schema: bool) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        workspace = Path(tmp)
        payload = base_payload(workspace)
        if mutate:
            mutate(payload, workspace)
        validated = validator.validate(payload, workspace)
        schema_ok, schema_detail = schema_validate(payload)
        ok = (validated["valid"] is expect_validator) and (schema_ok is expect_schema)
        return {
            "case": name,
            "expected_validator_valid": expect_validator,
            "validator_valid": validated["valid"],
            "validator_errors": validated["errors"],
            "expected_schema_valid": expect_schema,
            "schema_valid": schema_ok,
            "schema_detail": schema_detail,
            "pass": ok,
        }


def run_schema_case(name: str, payload: dict, schema_path: Path, expect_schema: bool) -> dict:
    schema_ok, schema_detail = schema_validate(payload, schema_path)
    return {
        "case": name,
        "expected_schema_valid": expect_schema,
        "schema_valid": schema_ok,
        "schema_detail": schema_detail,
        "pass": schema_ok is expect_schema,
    }


def main() -> int:
    cases = []
    cases.append(run_case("POSITIVE_REAL_ARTIFACT", None, True, True))

    def empty(payload, workspace):
        payload["deliverable_created"]["files_to_create"] = []
        payload["deliverable_created"]["artifact_evidence"] = []
        payload["deliverable_created"]["html_structure"] = {}
        payload["deliverable_created"]["css_structure"] = {}
    cases.append(run_case("ADVERSARIAL_EMPTY_SPEC", empty, False, False))

    def missing(payload, workspace):
        (workspace / "sandbox_runs/case/index.html").unlink()
    cases.append(run_case("ADVERSARIAL_MISSING_ARTIFACT", missing, False, True))

    def tampered(payload, workspace):
        (workspace / "sandbox_runs/case/index.html").write_bytes(b"<!doctype html><html><body>changed</body></html>")
    cases.append(run_case("ADVERSARIAL_TAMPERED_ARTIFACT_SHA", tampered, False, True))

    def fake_source(payload, workspace):
        payload["deliverable_created"]["source_inputs"][0]["source_ref"] = "upstream/nonexistent.md"
        payload["deliverable_created"]["source_inputs"][0]["source_sha256"] = "0" * 64
    cases.append(run_case("ADVERSARIAL_FICTITIOUS_UPSTREAM", fake_source, False, True))

    def stale(payload, workspace):
        payload["deliverable_created"]["source_inputs"][1]["currentness"] = "STALE"
        payload["deliverable_created"]["source_inputs"][1]["verdict"] = "FAIL"
    cases.append(run_case("ADVERSARIAL_STALE_UPSTREAM", stale, False, False))

    with tempfile.TemporaryDirectory() as tmp:
        workspace = Path(tmp)
        advisory = base_payload(workspace, mode="ADVISORY_SPEC_ONLY")
        validated = validator.validate(advisory, workspace)
        schema_ok, schema_detail = schema_validate(advisory)
        cases.append({
            "case": "HOLDOUT_ADVISORY_NO_FALSE_ARTIFACT_CLAIM",
            "expected_validator_valid": True,
            "validator_valid": validated["valid"],
            "validator_errors": validated["errors"],
            "expected_schema_valid": True,
            "schema_valid": schema_ok,
            "schema_detail": schema_detail,
            "pass": validated["valid"] and schema_ok,
        })

    missing_product = {
        "worker": "frontend_prototype_architect_lf",
        "output_type": "FRONTEND_MISSING_INPUT_STATE",
        "blocked": True,
        "missing_fields": ["authoritative Product Direction for CTA intent"],
        "resolved_from_context": ["viewport=desktop", "UI hierarchy=current"],
        "conflicts_detected": [],
        "why_required": ["CTA intent is a Product decision"],
        "risk_if_assumed": ["frontend could change product intent"],
        "pipeline_action": "RETURN_TO_ORCHESTRATOR",
        "resolution_target": "PRODUCT_DIRECTION",
        "question_to_orchestrator": "Resolve the authoritative CTA intent only."
    }
    cases.append(run_schema_case("REDIRECT_MISSING_PRODUCT_TO_ORCHESTRATOR", missing_product, MISSING_SCHEMA_PATH, True))

    direct_profile_call = dict(missing_product)
    direct_profile_call["target_profile"] = "product_director_lf"
    cases.append(run_schema_case("ADVERSARIAL_DIRECT_PROFILE_REDIRECT_FIELD", direct_profile_call, MISSING_SCHEMA_PATH, False))

    shell_redirect = {
        "worker": "frontend_prototype_architect_lf",
        "output_type": "BLOCKED_FRONTEND_SCOPE",
        "blocked": True,
        "blocking_code": "SHELL_CHANGE_REQUIRED",
        "requested_capability": "change locked LF shell header",
        "pipeline_action": "RETURN_TO_ORCHESTRATOR",
        "resolution_target": "LF_SHELL_GOVERNANCE",
        "reason": "requested implementation modifies a SHELL_LOCKED target"
    }
    cases.append(run_schema_case("REDIRECT_SHELL_CHANGE_TO_ORCHESTRATOR", shell_redirect, SCOPE_BLOCK_SCHEMA_PATH, True))

    wrong_shell_target = dict(shell_redirect)
    wrong_shell_target["resolution_target"] = "BACKEND_OR_RUNTIME_OWNER"
    cases.append(run_schema_case("ADVERSARIAL_SHELL_REDIRECT_WRONG_TARGET", wrong_shell_target, SCOPE_BLOCK_SCHEMA_PATH, False))

    sensitive_block = {
        "worker": "frontend_prototype_architect_lf",
        "output_type": "BLOCKED_FRONTEND_SCOPE",
        "blocked": True,
        "blocking_code": "REAL_OR_SENSITIVE_DATA_REQUIRED",
        "requested_capability": "render prototype using real user credentials",
        "pipeline_action": "BLOCK_PIPELINE",
        "resolution_target": "NONE",
        "reason": "real or sensitive user data is forbidden in the sandbox prototype"
    }
    cases.append(run_schema_case("BLOCK_SENSITIVE_DATA_FAIL_CLOSED", sensitive_block, SCOPE_BLOCK_SCHEMA_PATH, True))

    all_ok = all(item["pass"] for item in cases)
    print(json.dumps({"suite": "FRONTEND_AUDIT_REMEDIATION_20260827", "all_pass": all_ok, "count": len(cases), "results": cases}, ensure_ascii=False, indent=2))
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
