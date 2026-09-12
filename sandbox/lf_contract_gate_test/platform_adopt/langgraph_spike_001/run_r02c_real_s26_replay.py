#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PKG = ROOT / "services" / "profile_runtime_api"
if str(PKG) not in sys.path:
    sys.path.insert(0, str(PKG))

from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.models import ProfileTask
from profile_runtime_api.settings import Settings

SOURCE_REF = "48916fd36bcaff8eadd60944848e81adbea55c54"
SOURCE_DIR = "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001"
EXPECTED_INPUT_SHA256 = "fdfb12f2c8c5313fef5152e1f6b6689ccae78ed94170358cf065bb02649135a1"
EXPECTED_RAW_SHA256 = "45b130b396abb690095cb6b64c1bf23b4a046a49c904aee1436ff0a46b450b0b"
EXPECTED_OUTPUT_SHA256 = "5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7"
TYPED_CONTEXT_SHA256 = "24c3e3c60e609a2dc2d55703c624364c9438d4057da13185288a3f537c16ba72"
PERSISTED_LANGGRAPH = HERE / "R02C_LANGGRAPH_FUNCTIONAL_OUTPUT.json"
PERSISTED_REPORT = HERE / "R02C_PARITY_REPORT.json"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git_show(path: str) -> bytes:
    proc = subprocess.run(
        ["git", "show", f"{SOURCE_REF}:{SOURCE_DIR}/{path}"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return proc.stdout


def materialize(engine: ProfileRuntimeEngine, task: ProfileTask, raw_text: str) -> str:
    result, _meta = engine._materialize_runtime_output(
        task=task,
        model_raw_output=raw_text,
        governed_receipt={"runtime_typed_context_sha256": TYPED_CONTEXT_SHA256},
    )
    if not isinstance(result, str):
        raise RuntimeError("R02C_MATERIALIZED_OUTPUT_NOT_STRING")
    return result


def main() -> int:
    input_bytes = git_show("input.txt")
    request_bytes = git_show("gate_f_exact_request.json")
    raw_bytes = git_show("gate_f_exact_model_output.json")
    expected_bytes = git_show("gate_f_exact_materialized_output.review.json")

    request = json.loads(request_bytes.decode("utf-8"))
    task = ProfileTask.model_validate(request["profile"])
    input_literal = request["profile"]["input_literal"]

    if sha256_bytes(input_literal.encode("utf-8")) != EXPECTED_INPUT_SHA256:
        raise RuntimeError("R02C_INPUT_SHA_MISMATCH")
    if sha256_bytes(raw_bytes) != EXPECTED_RAW_SHA256:
        raise RuntimeError("R02C_RAW_SHA_MISMATCH")
    if sha256_bytes(expected_bytes) != EXPECTED_OUTPUT_SHA256:
        raise RuntimeError("R02C_FROZEN_OUTPUT_SHA_MISMATCH")
    if input_bytes.decode("utf-8") != input_literal:
        raise RuntimeError("R02C_INPUT_LITERAL_MISMATCH")

    settings = Settings(
        repo_root=ROOT,
        state_dir=Path("/tmp/lf-r02c-state"),
        api_token="r02c-replay-only",
        source_sha=SOURCE_REF,
    )
    engine = ProfileRuntimeEngine(settings)
    raw_text = raw_bytes.decode("utf-8")

    direct_output = materialize(engine, task, raw_text)
    direct_bytes = direct_output.encode("utf-8")

    @task(name="lf_r02c_materialize_real_s26")
    def materialize_task(_: dict[str, Any]) -> str:
        return materialize(engine, task, raw_text)

    @entrypoint(checkpointer=InMemorySaver())
    def functional(_: dict[str, Any]) -> dict[str, Any]:
        return {"output": materialize_task({}).result()}

    wrapped = functional.invoke(
        {"request_id": request["profile"]["request_id"]},
        config={"configurable": {"thread_id": "r02c-s26-hp001-functional"}},
    )
    functional_output = wrapped["output"]
    functional_bytes = functional_output.encode("utf-8")

    persisted_functional = PERSISTED_LANGGRAPH.read_bytes()

    report = {
        "schema": "LF_LANGGRAPH_R02C_REAL_S26_ARTIFACT_PARITY_V1",
        "case_id": "S26-HP-001",
        "source_ref": SOURCE_REF,
        "profile": "ui_architect",
        "input_sha256": sha256_bytes(input_literal.encode("utf-8")),
        "model_raw_output_sha256": sha256_bytes(raw_bytes),
        "lf_direct_output_sha256": sha256_bytes(direct_bytes),
        "langgraph_functional_output_sha256": sha256_bytes(functional_bytes),
        "frozen_expected_output_sha256": sha256_bytes(expected_bytes),
        "persisted_langgraph_output_sha256": sha256_bytes(persisted_functional),
        "direct_equals_frozen": direct_bytes == expected_bytes,
        "functional_equals_frozen": functional_bytes == expected_bytes,
        "direct_equals_functional": direct_bytes == functional_bytes,
        "persisted_functional_equals_executed": persisted_functional == functional_bytes,
        "model_called": False,
        "network_calls": 0,
        "production_effect": False,
        "comparison_scope": "REAL_S26_FROZEN_INPUT_AND_MODEL_RAW__DETERMINISTIC_MATERIALIZATION_REPLAY",
        "status": "PASS",
    }

    if not all(
        [
            report["direct_equals_frozen"],
            report["functional_equals_frozen"],
            report["direct_equals_functional"],
            report["persisted_functional_equals_executed"],
        ]
    ):
        raise RuntimeError("R02C_ARTIFACT_PARITY_FAILED")
    if report["lf_direct_output_sha256"] != EXPECTED_OUTPUT_SHA256:
        raise RuntimeError("R02C_DIRECT_SHA_MISMATCH")
    if report["langgraph_functional_output_sha256"] != EXPECTED_OUTPUT_SHA256:
        raise RuntimeError("R02C_FUNCTIONAL_SHA_MISMATCH")

    persisted_report = json.loads(PERSISTED_REPORT.read_text(encoding="utf-8"))
    for key in (
        "case_id",
        "source_ref",
        "profile",
        "input_sha256",
        "model_raw_output_sha256",
        "frozen_expected_output_sha256",
        "comparison_scope",
    ):
        if persisted_report.get(key) != report.get(key):
            raise RuntimeError(f"R02C_PERSISTED_REPORT_MISMATCH:{key}")

    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
