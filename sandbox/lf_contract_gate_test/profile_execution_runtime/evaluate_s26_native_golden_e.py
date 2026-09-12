#!/usr/bin/env python3
"""Evaluate fresh S26 Native Golden Run E up to the independent-quality boundary."""
from __future__ import annotations
import contextlib
import io
import json
import os
from pathlib import Path

import evaluate_s26_native_golden_c as base
from profile_runtime_runner import _build_lf_adapter_invocations

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005"
MATERIALIZATION_COMMIT = "5044763bc3ccdd0bac5bc2ded7342a74f20f8ed3"
MATERIALIZATION_COMMIT_AT = "2026-09-09T00:11:34+00:00"
PRODUCER_RUN_ID = "CHATGPT-NATIVE-S26-N08E-GOLDEN-E-001"
PREBOUND_COMMIT = "be81529076840bd73c1a883ee504f929760c6906"


def build_adapter_invocations(preflight):
    binding = json.loads((EVIDENCE / "router_adapter_binding_snapshot.json").read_text(encoding="utf-8"))
    capsule_path = ROOT / "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"
    content = capsule_path.read_text(encoding="utf-8")
    request_stub = {
        "execution_id": preflight["execution_id"],
        "profile_code": "PERFIL-UI-ARCHITECT",
        "lf_adapter_sources": [{
            "adapter_code": binding["adapter_code"],
            "assurance_revision": binding["assurance_revision"],
            "binding_ref": "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/router_adapter_binding_snapshot.json",
            "target_ref": binding["target_asset_code"],
            "ref": "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml",
            "content": content,
            "capsule_char_count": len(content),
        }],
    }
    return _build_lf_adapter_invocations(request_stub)


def main() -> int:
    raw = json.loads((EVIDENCE / "raw_output.json").read_text(encoding="utf-8"))
    governed = raw.get("deliverable_created", {}).get("governance_context", {})
    if governed.get("prebound_commit_sha") != PREBOUND_COMMIT:
        raise SystemExit("BLOCK_RUN_E_PREBOUND_COMMIT_MISMATCH")
    rendered = json.dumps(raw, ensure_ascii=False)
    for forbidden in ("visual-artifact:", '"mode": "UPSTREAM_VALUE"', '"current_page": 1'):
        if forbidden in rendered:
            raise SystemExit("BLOCK_RUN_E_FORBIDDEN_RAW_PATTERN:" + forbidden)
    expected_headers = ["Fecha de carga","Archivo","Tipo","Registros","Válidos","Con error","Estado","Usuario","Fecha de proceso","Acciones"]
    table = next((item for item in raw["deliverable_created"]["component_tree"] if item.get("component_id") == "history_table"), {})
    if table.get("content", {}).get("headers") != expected_headers:
        raise SystemExit("BLOCK_RUN_E_HEADER_PARITY")

    base.EVIDENCE = EVIDENCE
    base.RAW_PATH = EVIDENCE / "raw_output.json"
    base.INPUT_PATH = EVIDENCE / "input.txt"
    base.GOVERNED_CONTEXT_PATH = EVIDENCE / "governed_context_receipt.json"
    base.METRICS_PATH = EVIDENCE / "metrics_plan.json"
    base.PREPARE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/prepare_s26_native_golden_e.py"
    base.MATERIALIZATION_COMMIT = MATERIALIZATION_COMMIT
    base.MATERIALIZATION_COMMIT_AT = MATERIALIZATION_COMMIT_AT
    base.PRODUCER_RUN_ID = PRODUCER_RUN_ID
    base.build_adapter_invocations = build_adapter_invocations

    old = os.environ.get("S26_RUN_E_ALLOW_RAW_REEVAL")
    os.environ["S26_RUN_E_ALLOW_RAW_REEVAL"] = "1"
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = base.main()
    finally:
        if old is None:
            os.environ.pop("S26_RUN_E_ALLOW_RAW_REEVAL", None)
        else:
            os.environ["S26_RUN_E_ALLOW_RAW_REEVAL"] = old
    text = buf.getvalue()
    if rc != 0:
        print(text, end="")
        return rc

    result = json.loads(text)
    result["schema"] = "S26_NATIVE_GOLDEN_E_EVALUATION_V1"
    result["run_revision"] = "E"
    result["producer_run_id"] = PRODUCER_RUN_ID
    result["prebound_commit_sha"] = PREBOUND_COMMIT
    result["materialization_commit_sha"] = MATERIALIZATION_COMMIT
    result["golden_eligible"] = False
    result["golden_declared"] = False
    result["next_gate"] = "INDEPENDENT_CHAT_CONTEXT"
    result["blocking_codes"] = ["INDEPENDENT_QUALITY_REVIEW_NOT_EXECUTED"]
    result["resolver_backed_upstream"] = True
    result["current_page_prebound"] = False
    result["derived_rule_claimed_upstream"] = False
    result["header_parity"] = True

    (EVIDENCE / "evaluation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (EVIDENCE / "execution_receipt.json").write_text(json.dumps(result["execution_receipt"], ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (EVIDENCE / "semantic_check_bundle.json").write_text(json.dumps(result["check_bundle"], ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": result["status"],
        "execution_id": result["execution_id"],
        "run_revision": "E",
        "ui_architect_validator": result["ui_architect_validator"],
        "depth_gate": result["depth_gate"],
        "semantic_checks_pending": result["semantic_checks_pending"],
        "execution_receipt_sha256": result["execution_receipt_sha256"],
        "check_bundle_sha256": result["check_bundle_sha256"],
        "context_fingerprint": result["context_fingerprint"],
        "resolver_backed_upstream": True,
        "header_parity": True,
        "next_gate": result["next_gate"],
        "golden_declared": False,
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
