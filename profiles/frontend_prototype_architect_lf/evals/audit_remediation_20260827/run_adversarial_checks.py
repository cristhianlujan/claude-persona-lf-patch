#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "validators" / "validate_frontend_artifact.py"
SCHEMA_PATH = ROOT / "schemas" / "html_sandbox_output.schema.json"

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


def schema_validate(payload: dict) -> tuple[bool, str]:
    try:
        import jsonschema
    except ImportError:
        return False, "jsonschema dependency unavailable"
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        jsonschema.Draft202012Validator(schema).validate(payload)
        return True, "PASS"
    except jsonschema.ValidationError as exc:
        return False, exc.message


def main() -> int:
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        workspace = Path(tmp)
        good = base_payload(workspace)

        cases = []
        cases.append(("POSITIVE_REAL_ARTIFACT", good, True, True))

        empty = copy.deepcopy(good)
        empty["deliverable_created"]["files_to_create"] = []
        empty["deliverable_created"]["artifact_evidence"] = []
        empty["deliverable_created"]["html_structure"] = {}
        empty["deliverable_created"]["css_structure"] = {}
        cases.append(("ADVERSARIAL_EMPTY_SPEC", empty, False, False))

        missing = copy.deepcopy(good)
        (workspace / "sandbox_runs/case/index.html").unlink()
        cases.append(("ADVERSARIAL_MISSING_ARTIFACT", missing, False, True))
        (workspace / "sandbox_runs/case/index.html").write_bytes(b"<!doctype html><html><body>changed</body></html>")

        tampered = copy.deepcopy(good)
        cases.append(("ADVERSARIAL_TAMPERED_ARTIFACT_SHA", tampered, False, True))

        (workspace / "sandbox_runs/case/index.html").write_bytes(b"<!doctype html><html><head><title>LF</title></head><body><main><button>Continuar</button></main></body></html>")
        fake_source = copy.deepcopy(good)
        fake_source["deliverable_created"]["source_inputs"][0]["source_ref"] = "upstream/nonexistent.md"
        fake_source["deliverable_created"]["source_inputs"][0]["source_sha256"] = "0" * 64
        cases.append(("ADVERSARIAL_FICTITIOUS_UPSTREAM", fake_source, False, True))

        stale = copy.deepcopy(good)
        stale["deliverable_created"]["source_inputs"][1]["currentness"] = "STALE"
        stale["deliverable_created"]["source_inputs"][1]["verdict"] = "FAIL"
        cases.append(("ADVERSARIAL_STALE_UPSTREAM", stale, False, False))

        advisory = base_payload(workspace, mode="ADVISORY_SPEC_ONLY")
        cases.append(("HOLDOUT_ADVISORY_NO_FALSE_ARTIFACT_CLAIM", advisory, True, True))

        all_ok = True
        for name, payload, expect_validator, expect_schema in cases:
            validated = validator.validate(payload, workspace)
            schema_ok, schema_detail = schema_validate(payload)
            ok = (validated["valid"] is expect_validator) and (schema_ok is expect_schema)
            all_ok = all_ok and ok
            results.append({
                "case": name,
                "expected_validator_valid": expect_validator,
                "validator_valid": validated["valid"],
                "validator_errors": validated["errors"],
                "expected_schema_valid": expect_schema,
                "schema_valid": schema_ok,
                "schema_detail": schema_detail,
                "pass": ok,
            })

    print(json.dumps({"suite": "FRONTEND_AUDIT_REMEDIATION_20260827", "all_pass": all_ok, "results": results}, ensure_ascii=False, indent=2))
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
