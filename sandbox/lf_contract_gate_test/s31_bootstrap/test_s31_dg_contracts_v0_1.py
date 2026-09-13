#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("s31_dg", ROOT / "validate_s31_dg_contracts_v0_1.py")
m = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = m
spec.loader.exec_module(m)


def load_schema(name: str) -> dict:
    schema = json.loads((ROOT / name).read_text(encoding="utf-8"))
    Draft7Validator.check_schema(schema)
    return schema


def schema_errors(schema: dict, value: dict) -> list[str]:
    validator = Draft7Validator(schema)
    return [e.message for e in sorted(validator.iter_errors(value), key=lambda e: list(e.path))]


D_SCHEMA = load_schema("lf_shared_authority_typed_context_v0_1_candidate.schema.json")
E_SCHEMA = load_schema("lf_capability_manifest_v0_2_candidate.schema.json")
F_SCHEMA = load_schema("lf_common_evidence_envelope_v0_2_candidate.schema.json")
G_SCHEMA = load_schema("lf_runtime_execution_port_v0_1_candidate.schema.json")

SHA = "a" * 64


def d_base() -> dict:
    return {
        "schema": "lf-shared-governed-typed-context/v0.1-candidate",
        "current_run_id": "run-001",
        "classification": {"surface_code": "PROFILE:X", "task_code": "EXECUTE:JSON"},
        "input": {"input_fields": {"x": 1}},
        "card_resolution": {"status": "RESOLVED", "mode": "EXACT", "schema_invention_allowed": False},
        "authority_resolution": [{
            "authority_type": "PROFILE_SOURCE",
            "authority_id": "PROFILE_X",
            "source_refs": ["repo://profile/x"],
            "source_sha256": SHA,
            "run_id": "run-001",
            "cross_run_declared": False
        }],
        "adapter_binding": [],
        "runtime_schema": {"source_ref": "repo://schema/x", "sha256": SHA, "schema_invention_allowed": False},
        "provenance_reconstructible": True,
        "typed_context_sha256": SHA
    }


def e_base() -> dict:
    return {
        "capability_id": "TYPED_RUNTIME_CONTEXT",
        "capability_version": "v0.2-candidate",
        "capability_class": "CONTEXT",
        "owner": "S31-D",
        "lifecycle": {
            "artifact_maturity_label": "CANDIDATE_READ_ONLY",
            "runtime_activation": False,
            "promotion_authority": "INDEPENDENT_LF_GOVERNANCE",
            "self_certification_allowed": False,
            "canonical_vocabulary_status": "UNRESOLVED"
        },
        "authority_contract": "LF_AUTHORITY_CONTRACT",
        "input_contract": "LF_TYPED_CONTEXT_INPUT",
        "output_contract": "LF_TYPED_CONTEXT_OUTPUT",
        "dependencies": [
            {"capability_id": "CARD_RESOLUTION", "version_constraint": ">=v0.1", "critical": True}
        ],
        "compatibility": {
            "consumer_contracts": ["LF_RUNTIME_TYPED_CONTEXT_V1"],
            "boundary_adapters": ["S26_TYPED_CONTEXT_V1_TO_SHARED_V0_1"]
        },
        "execution_port": "TYPED_CONTEXT_RESOLUTION_PORT",
        "adapter_bindings": ["S26_RUNTIME_AUTHORITY_ADAPTER"],
        "evidence_contract": "LF_COMMON_EVIDENCE_ENVELOPE_V0_2",
        "currentness_binding": {"policy": "EXACT_SOURCE_REVISION", "stale_action": "FAIL_CLOSED"},
        "source_refs": ["repo://runtime_authority.py"],
        "source_digests": [SHA],
        "claim_ceiling": "PROVENANCE"
    }


def f_base(level: str = "STRUCTURAL", ceiling: str = "STRUCTURAL") -> dict:
    executed = level != "STRUCTURAL"
    return {
        "receipt_version": "LF_EVIDENCE_V0_2",
        "run_id": "run-001",
        "capability_or_gate_id": "S31-D",
        "input": {"exact": {"x": 1}, "digest": "12345678", "source_refs": ["repo://x"]},
        "validation_or_transformation": "DETERMINISTIC_VALIDATE",
        "output": {"exact": {"ok": True}, "digest": "abcdefgh", "ref": "receipt://out"},
        "execution_identity": {
            "executed": executed,
            "execution_ref_kind": "BRANCH_HEAD" if executed else "NOT_EXECUTED",
            "executed_sha": "b" * 40 if executed else None,
            "execution_id": "exec-001" if executed else None
        },
        "environment": "SANDBOX",
        "authority": {"source": "LF", "currentness": "CURRENT" if executed else "UNKNOWN"},
        "provenance": {"reconstructible": executed, "refs": ["repo://x"]},
        "evidence_level": level,
        "claim_ceiling": ceiling,
        "first_bad_hop": None,
        "repair_disposition": "NONE"
    }


def g_base() -> dict:
    return {
        "port_version": "LF_RUNTIME_EXECUTION_PORT_V0_1_CANDIDATE",
        "request_id": "run-001",
        "typed_context_ref": "context://001",
        "typed_context_sha256": SHA,
        "governed_input": {"prompt": "bounded"},
        "output_contract_ref": "contract://output",
        "execution_budget": {"max_runtime_ms": 1000, "max_output_units": 2000},
        "runtime_policy": {"provider_or_adapter": "PROFILE_RUNTIME_EXECUTOR_ADAPTER", "silent_fallback_allowed": False},
        "authority_decisions_forbidden": ["AUTHORITY", "CURRENTNESS", "CARD_APPLICABILITY", "PROMOTION", "GOLDEN", "PRODUCTION"]
    }


# D positive + fail-closed cases.
d = d_base()
assert not schema_errors(D_SCHEMA, d)
assert m.validate_shared_typed_context(d)["status"] == m.PASS
x = copy.deepcopy(d); x["authority_resolution"][0]["run_id"] = "old-run"
assert m.validate_shared_typed_context(x)["code"] == "BLOCK_D_UNDECLARED_CROSS_RUN_AUTHORITY"
x = copy.deepcopy(d); x["card_resolution"] = {"status": "NO_DIRECT_CARD", "mode": "EXACT", "schema_invention_allowed": False}
assert m.validate_shared_typed_context(x)["code"] == "BLOCK_D_NONRESOLVED_CARD_HAS_MODE"
x = copy.deepcopy(d); x["card_resolution"]["schema_invention_allowed"] = True
assert schema_errors(D_SCHEMA, x)

# E positive + lifecycle/source/dependency fail-closed cases.
e = e_base()
assert not schema_errors(E_SCHEMA, e)
assert m.validate_capability_manifest(e)["status"] == m.PASS
x = copy.deepcopy(e); x["lifecycle"]["canonical_vocabulary_status"] = "RESOLVED"
assert schema_errors(E_SCHEMA, x)
x = copy.deepcopy(e); x["lifecycle"]["self_certification_allowed"] = True
assert schema_errors(E_SCHEMA, x)
x = copy.deepcopy(e); x["source_digests"] = [SHA, "b" * 64]
assert m.validate_capability_manifest(x)["code"] == "BLOCK_E_SOURCE_BINDING_CARDINALITY"
x = copy.deepcopy(e); x["dependencies"].append(copy.deepcopy(x["dependencies"][0]))
assert m.validate_capability_manifest(x)["code"] == "BLOCK_E_DUPLICATE_DEPENDENCY"

# F evidence ceiling and execution/currentness/provenance enforcement.
f = f_base()
assert not schema_errors(F_SCHEMA, f)
assert m.validate_evidence_envelope(f)["status"] == m.PASS
x = f_base("STRUCTURAL", "BEHAVIORAL")
assert schema_errors(F_SCHEMA, x)
x = f_base("SEMANTIC", "SEMANTIC"); x["execution_identity"]["executed"] = False
assert schema_errors(F_SCHEMA, x)
x = f_base("SEMANTIC", "SEMANTIC"); x["authority"]["currentness"] = "STALE"
assert schema_errors(F_SCHEMA, x)
x = f_base("SEMANTIC", "SEMANTIC"); x["provenance"]["reconstructible"] = False
assert schema_errors(F_SCHEMA, x)

# G request/output boundaries.
g = g_base()
assert not schema_errors(G_SCHEMA, g)
assert m.validate_runtime_port_request(g)["status"] == m.PASS
x = copy.deepcopy(g); x["runtime_policy"]["silent_fallback_allowed"] = True
assert schema_errors(G_SCHEMA, x)
x = copy.deepcopy(g); x["authority_decisions_forbidden"].pop()
assert schema_errors(G_SCHEMA, x)
valid_output = {
    "raw_output": "{}",
    "runtime_receipt": {"run_id": "run-001"},
    "transport_diagnostics": {},
    "resource_usage": {},
    "failure_code": None
}
assert m.validate_runtime_port_output(valid_output)["status"] == m.PASS
x = copy.deepcopy(valid_output); x["downstream_authorized"] = True
assert m.validate_runtime_port_output(x)["code"] == "BLOCK_G_OUTPUT_AUTHORIZES_DOWNSTREAM"
x = copy.deepcopy(valid_output); x["authority_effects"] = ["PROMOTE_GOLDEN"]
assert m.validate_runtime_port_output(x)["code"] == "BLOCK_G_OUTPUT_AUTHORITY_EFFECT"

print(json.dumps({
    "contract": "S31_DG_CONTRACT_MATRIX_V0_1",
    "schemas_valid": ["D_TYPED_CONTEXT_V0_1", "E_CAPABILITY_MANIFEST_V0_2", "F_EVIDENCE_ENVELOPE_V0_2", "G_RUNTIME_PORT_V0_1"],
    "positive_cases": 5,
    "negative_fail_closed_cases": 14,
    "result": "PASS"
}, sort_keys=True))
