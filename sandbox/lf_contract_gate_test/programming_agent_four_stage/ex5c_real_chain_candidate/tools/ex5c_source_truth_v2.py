"""Explicit EX5C V2 provenance limits and a real architecture boundary command.

Does not monkeypatch V1: preserves prior synthetic regression. Do NOT report
a true smoke process exit_code when only HTTP status/response evidence exists.
"""
from __future__ import annotations

import hashlib
import subprocess
import tempfile
from pathlib import Path

import ex5c_real_world_v1 as w
from pg07_ex5c_format_remediation_v3_adapter_v1 import (
    V3_FIXTURE, V3_SHA, decode, load_v3,
)

SOURCE_ONLY_EXCEPTIONS = {
    "pg07.cached_input_price_per_million": {
        "value": "2.00",
        "status": "ASSUMPTION_NOT_PROVIDER_PRICE",
        "ref": "ex5c://assumption/zero-cache-tokens-no-billing-impact",
    },
    "pg07.context_window_tokens": {
        "value": 200000,
        "status": "ASSUMPTION_NOT_MODEL_CAPABILITY_ATTESTED",
        "ref": "ex5c://assumption/context-budget-not-provider-readback",
    },
    "pg04.validation_registry": {
        "value": "fixture://registry/current",
        "status": "SYNTHETIC_DECLARATIVE_REGISTRY_EXCEPTION",
        "ref": "ex5c://exception/pg04-registry-not-real",
    },
    "pg08.smoke.exit_code": {
        "value": 0,
        "status": "DERIVED_PLACEHOLDER_NOT_PROCESS_EXIT_RECEIPT",
        "ref": "ex5c://exception/smoke-http-only-no-process-exit",
    },
    "pg08.c7.archunit_modulith": {
        "value": "NOT_APPLICABLE",
        "status": "NO_ARCHUNIT_OR_MODULITH_CONFIGURATION",
        "ref": "ex5c://exception/archunit-modulith-absent",
    },
}


def check_controller_repository_boundary_v2():
    """Run grep on exact V3 bytes, not strings copied from a report.

    Positive: controller mentions interface ReminderRepository (exit 0).
    Negative: controller must never mention concrete InMemoryReminderRepository
    (grep exit 1), with SHA256 hashes of the actual command streams.
    """
    v3 = load_v3(V3_FIXTURE, V3_SHA)
    target = w.J + "/reminder/ReminderController.java"
    rows = [row for row in v3["git"]["files"] if row["path"] == target]
    if len(rows) != 1:
        raise AssertionError("EX5C_V2_CONTROLLER_BLOB_MISSING_OR_DUPLICATE")
    data = decode(rows[0]["content_base64"])
    with tempfile.TemporaryDirectory(prefix="ex5c_v2_arch_") as td:
        file = Path(td) / "ReminderController.java"
        file.write_bytes(data)
        receipts = []
        for needle, expected in (("ReminderRepository", 0),
                                 ("InMemoryReminderRepository", 1)):
            argv = ["grep", "-n", "-F", needle, str(file)]
            result = subprocess.run(argv, capture_output=True, check=False)
            receipt = {
                "argv": argv,
                "exit_code": result.returncode,
                "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
                "stderr_sha256": hashlib.sha256(result.stderr).hexdigest(),
                "findings": result.stdout.decode("utf-8", "replace").splitlines(),
                "source_blob_oid": rows[0]["oid"],
                "source_commit": w.N1,
                "tool_execution_authenticated": False,
                "production_authority": False,
            }
            if result.returncode != expected:
                raise AssertionError("EX5C_V2_CONTROLLER_REPOSITORY_BOUNDARY_BLOCK:" + needle)
            receipts.append(receipt)
    if not receipts[0]["findings"] or receipts[1]["findings"]:
        raise AssertionError("EX5C_V2_CONTROLLER_BOUNDARY_NOT_PROVEN")
    return {
        "interface_required": "ReminderRepository",
        "concrete_dependency_forbidden": "InMemoryReminderRepository",
        "commands": receipts,
        "source": V3_SHA,
        "required_boundary_observed_locally": True,
        "source_authentication_verified": False,
        "production_authority": False,
    }


def smoke_v3_provenance_v2():
    v3 = load_v3(V3_FIXTURE, V3_SHA)
    smoke = v3["execution"]["smoke"]
    if "exit_code" in smoke:
        raise AssertionError("EX5C_V2_SMOKE_EXIT_ASSUMPTION_CHANGED")
    if not isinstance(smoke.get("steps"), list) or len(smoke["steps"]) != 5:
        raise AssertionError("EX5C_V2_SMOKE_HTTP_STEPS_INVALID")
    return {
        "http_steps_observed_from_v3": len(smoke["steps"]),
        "process_exit_code_authenticated": False,
        "imposed_v1_exit_code_is_exception": True,
        "stdout_sha256": smoke["stdout"]["sha256"],
        "stderr_sha256": smoke["stderr"]["sha256"],
        "production_authority": False,
    }
