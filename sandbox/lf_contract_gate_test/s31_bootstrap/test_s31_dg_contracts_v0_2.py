#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("s31_dg_v02", ROOT / "validate_s31_dg_contracts_v0_2.py")
m = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = m
spec.loader.exec_module(m)


def load_json(name: str) -> dict:
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def load_schema(name: str) -> dict:
    schema = load_json(name)
    Draft7Validator.check_schema(schema)
    return schema


def schema_errors(schema: dict, value: dict) -> list[str]:
    return [e.message for e in sorted(Draft7Validator(schema).iter_errors(value), key=lambda e: list(e.path))]


def digest(record: dict) -> str:
    raw = json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def add_record(store: dict, ref: str, record: dict, resolver_id: str = "INDEPENDENT_RESOLVER") -> dict:
    record = copy.deepcopy(record)
    record["resolver_id"] = resolver_id
    store[ref] = record
    return {"ref": ref, "sha256": digest(record), "resolver_id": resolver_id}


def resolver_for(store: dict):
    return lambda ref: copy.deepcopy(store.get(ref))


D_SCHEMA = load_schema("lf_shared_authority_typed_context_v0_2_candidate.schema.json")
E_SCHEMA = load_schema("lf_capability_manifest_v0_3_candidate.schema.json")
F_SCHEMA = load_schema("lf_common_evidence_envelope_v0_3_candidate.schema.json")
G_REQUEST_SCHEMA = load_schema("lf_runtime_execution_port_v0_1_candidate.schema.json")
G_OUTPUT_SCHEMA = load_schema("lf_runtime_execution_output_v0_1_candidate.schema.json")
E_INVENTORY = load_json("s31_e_capability_registry_gap_inventory_v0_2.json")
SHA = "a" * 64
HEAD = "b" * 40
POS = 0
NEG = 0


def d_base() -> tuple[dict, dict]:
    store: dict = {}
    auth_binding = add_record(store, "evidence://d/auth", {
        "evidence_type": "SOURCE_CURRENTNESS_RECEIPT",
        "status": "PASS",
        "currentness": "CURRENT",
        "source_refs": ["repo://profile/x"],
        "source_sha256": SHA,
        "run_id": "run-001"
    })
    schema_binding = add_record(store, "evidence://d/schema", {
        "evidence_type": "SOURCE_CURRENTNESS_RECEIPT",
        "status": "PASS",
        "currentness": "CURRENT",
        "source_refs": ["repo://schema/x"],
        "source_sha256": SHA,
        "run_id": "run-001"
    })
    value = {
        "schema": "lf-shared-governed-typed-context/v0.2-candidate",
        "producer_id": "S31_D_PRODUCER",
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
            "cross_run_declared": False,
            "currentness_evidence": auth_binding
        }],
        "adapter_binding": [],
        "runtime_schema": {
            "source_ref": "repo://schema/x",
            "sha256": SHA,
            "schema_invention_allowed": False,
            "currentness_evidence": schema_binding
        },
        "provenance_reconstructible": True,
        "typed_context_sha256": SHA
    }
    return value, store


def e_base() -> tuple[dict, dict]:
    store: dict = {}
    refs = ["repo://runtime_authority.py"]
    digests = [SHA]
    current_binding = add_record(store, "evidence://e/current", {
        "evidence_type": "CAPABILITY_CURRENTNESS_RECEIPT",
        "status": "PASS",
        "currentness": "CURRENT",
        "source_refs": refs,
        "source_digests": digests
    })
    value = {
        "capability_id": "TYPED_RUNTIME_CONTEXT",
        "capability_version": "v0.3-candidate",
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
        "dependencies": [{"capability_id": "CARD_RESOLUTION", "version_constraint": ">=v0.1", "critical": True}],
        "compatibility": {"consumer_contracts": ["LF_RUNTIME_TYPED_CONTEXT_V1"], "boundary_adapters": ["S26_TYPED_CONTEXT_V1_TO_SHARED_V0_2"]},
        "execution_port": "TYPED_CONTEXT_RESOLUTION_PORT",
        "adapter_bindings": ["S26_RUNTIME_AUTHORITY_ADAPTER"],
        "evidence_contract": "LF_COMMON_EVIDENCE_ENVELOPE_V0_3",
        "currentness_binding": {
            "policy": "EXACT_SOURCE_REVISION",
            "stale_action": "FAIL_CLOSED",
            "evidence_ref": current_binding["ref"],
            "evidence_sha256": current_binding["sha256"],
            "resolver_id": current_binding["resolver_id"]
        },
        "source_refs": refs,
        "source_digests": digests,
        "claim_ceiling": "PROVENANCE"
    }
    return value, store


def f_base(level: str = "STRUCTURAL", ceiling: str = "STRUCTURAL") -> tuple[dict, dict]:
    store: dict = {}
    owner = add_record(store, "evidence://f/owner", {
        "evidence_type": "OWNER_RECEIPT",
        "status": "PASS",
        "owner_capability_id": "S31-F",
        "run_id": "run-001"
    })
    owner.update({"owner_capability_id": "S31-F", "preserved_without_rewrite": True})
    executed = level != "STRUCTURAL"
    value = {
        "receipt_version": "LF_EVIDENCE_V0_3",
        "run_id": "run-001",
        "producer_id": "S31_F_PRODUCER",
        "capability_or_gate_id": "S31-F",
        "input": {"exact": {"x": 1}, "digest": "1" * 64, "source_refs": ["repo://x"]},
        "validation_or_transformation": "DETERMINISTIC_VALIDATE",
        "output": {"exact": {"ok": True}, "digest": "2" * 64, "ref": "receipt://out"},
        "execution_identity": {
            "executed": executed,
            "execution_ref_kind": "BRANCH_HEAD" if executed else "NOT_EXECUTED",
            "executed_sha": HEAD if executed else None,
            "execution_id": "exec-001" if executed else None
        },
        "environment": "SANDBOX",
        "authority": {"source": "LF_AUTHORITY", "currentness": "CURRENT" if executed else "UNKNOWN"},
        "provenance": {"reconstructible": executed, "refs": ["repo://x"]},
        "owner_receipt": owner,
        "extensions": {"s31.f.test": {"preserves_owner_semantics": True}},
        "evidence_level": level,
        "claim_ceiling": ceiling,
        "first_bad_hop": None,
        "repair_disposition": "NONE"
    }
    if executed:
        value["resolved_evidence"] = {
            "execution_receipt": add_record(store, "evidence://f/execution", {
                "evidence_type": "EXECUTION_RECEIPT", "status": "PASS", "run_id": "run-001", "executed": True,
                "executed_sha": HEAD, "execution_id": "exec-001"
            }),
            "authority_currentness_receipt": add_record(store, "evidence://f/current", {
                "evidence_type": "AUTHORITY_CURRENTNESS_RECEIPT", "status": "PASS",
                "authority_source": "LF_AUTHORITY", "currentness": "CURRENT"
            }),
            "provenance_receipt": add_record(store, "evidence://f/provenance", {
                "evidence_type": "PROVENANCE_RECEIPT", "status": "PASS", "reconstructible": True, "refs": ["repo://x"]
            })
        }
    return value, store


def g_request() -> dict:
    return {
        "port_version": "LF_RUNTIME_EXECUTION_PORT_V0_1_CANDIDATE",
        "request_id": "run-001",
        "typed_context_ref": "context://001",
        "typed_context_sha256": SHA,
        "governed_input": {"prompt": "bounded"},
        "output_contract_ref": "lf_runtime_execution_output_v0_1_candidate.schema.json",
        "execution_budget": {"max_runtime_ms": 1000, "max_output_units": 2000},
        "runtime_policy": {"provider_or_adapter": "PROFILE_RUNTIME_EXECUTOR_ADAPTER", "silent_fallback_allowed": False},
        "authority_decisions_forbidden": ["AUTHORITY", "CURRENTNESS", "CARD_APPLICABILITY", "PROMOTION", "GOLDEN", "PRODUCTION"]
    }


def g_output() -> dict:
    return {
        "raw_output": {"business_payload": "ok"},
        "runtime_receipt": {
            "run_id": "run-001",
            "executor_id": "PROFILE_RUNTIME_EXECUTOR_ADAPTER",
            "status": "PASS",
            "receipt_ref": "receipt://runtime/001",
            "receipt_sha256": SHA,
            "authority_grants_allowed": False,
            "downstream_authorized": False,
            "golden_authorized": False,
            "production_authorized": False,
            "authority_effects": []
        },
        "transport_diagnostics": {},
        "resource_usage": {},
        "failure_code": None
    }


# D: positive and adversarial currentness cases.
d, store = d_base()
assert not schema_errors(D_SCHEMA, d)
assert m.validate_shared_typed_context(d, resolver_for(store))["status"] == m.PASS
POS += 1
assert m.validate_shared_typed_context(d, None)["code"] == "BLOCK_EVIDENCE_RESOLVER_MISSING"; NEG += 1
x = copy.deepcopy(d); x["authority_resolution"][0]["currentness_evidence"]["ref"] = "evidence://missing"
assert m.validate_shared_typed_context(x, resolver_for(store))["code"] == "BLOCK_EVIDENCE_UNRESOLVED"; NEG += 1
x, s = d_base(); r = s["evidence://d/auth"]; r["currentness"] = "STALE"; x["authority_resolution"][0]["currentness_evidence"]["sha256"] = digest(r)
assert m.validate_shared_typed_context(x, resolver_for(s))["code"] == "BLOCK_D_AUTHORITY_CURRENTNESS_MISMATCH"; NEG += 1
x, s = d_base(); r = s["evidence://d/auth"]; r["source_refs"] = ["repo://fake"]; x["authority_resolution"][0]["currentness_evidence"]["sha256"] = digest(r)
assert m.validate_shared_typed_context(x, resolver_for(s))["code"] == "BLOCK_D_AUTHORITY_CURRENTNESS_MISMATCH"; NEG += 1
x, s = d_base(); r = s["evidence://d/auth"]; r["resolver_id"] = "S31_D_PRODUCER"; b = x["authority_resolution"][0]["currentness_evidence"]; b["resolver_id"] = "S31_D_PRODUCER"; b["sha256"] = digest(r)
assert m.validate_shared_typed_context(x, resolver_for(s))["code"] == "BLOCK_EVIDENCE_SELF_RESOLVER"; NEG += 1
x, s = d_base(); x["authority_resolution"][0]["run_id"] = "old-run"
assert m.validate_shared_typed_context(x, resolver_for(s))["code"] == "BLOCK_D_UNDECLARED_CROSS_RUN_AUTHORITY"; NEG += 1
x, s = d_base(); x["runtime_schema"]["sha256"] = "short"
assert schema_errors(D_SCHEMA, x); NEG += 1

# E: frozen source-model identity plus resolver-derived source currentness.
e, store = e_base()
assert not schema_errors(E_SCHEMA, e)
assert m.validate_registry_inventory_schema(E_INVENTORY, E_SCHEMA)["status"] == m.PASS
assert m.validate_capability_manifest(e, resolver_for(store))["status"] == m.PASS
POS += 2
old_inventory = copy.deepcopy(E_INVENTORY); old_inventory["required_capability_manifest_fields"] = ["lifecycle_state" if x == "lifecycle" else x for x in old_inventory["required_capability_manifest_fields"]]
assert m.validate_registry_inventory_schema(old_inventory, E_SCHEMA)["code"] == "BLOCK_E_SOURCE_MODEL_REQUIRED_FIELDS_MISMATCH"; NEG += 1
x, s = e_base(); x["source_digests"] = ["12345678"]
assert schema_errors(E_SCHEMA, x); NEG += 1
x, s = e_base(); assert m.validate_capability_manifest(x, None)["code"] == "BLOCK_EVIDENCE_RESOLVER_MISSING"; NEG += 1
x, s = e_base(); r = s["evidence://e/current"]; r["currentness"] = "STALE"; x["currentness_binding"]["evidence_sha256"] = digest(r)
assert m.validate_capability_manifest(x, resolver_for(s))["code"] == "BLOCK_E_CURRENTNESS_RECEIPT_MISMATCH"; NEG += 1
x, s = e_base(); r = s["evidence://e/current"]; r["resolver_id"] = "S31-D"; x["currentness_binding"]["resolver_id"] = "S31-D"; x["currentness_binding"]["evidence_sha256"] = digest(r)
assert m.validate_capability_manifest(x, resolver_for(s))["code"] == "BLOCK_EVIDENCE_SELF_RESOLVER"; NEG += 1
x, s = e_base(); x["dependencies"].append(copy.deepcopy(x["dependencies"][0]))
assert m.validate_capability_manifest(x, resolver_for(s))["code"] == "BLOCK_E_DUPLICATE_DEPENDENCY"; NEG += 1

# F: claim ceiling plus independent execution/currentness/provenance resolution.
f, store = f_base()
assert not schema_errors(F_SCHEMA, f)
assert m.validate_evidence_envelope(f, None)["status"] == m.PASS
POS += 1
x, s = f_base(); x["input"]["digest"] = "12345678"
assert schema_errors(F_SCHEMA, x); NEG += 1
x, s = f_base(); x.pop("owner_receipt")
assert schema_errors(F_SCHEMA, x); NEG += 1
semantic, store = f_base("SEMANTIC", "SEMANTIC")
assert not schema_errors(F_SCHEMA, semantic)
assert m.validate_evidence_envelope(semantic, resolver_for(store))["status"] == m.PASS
POS += 1
assert m.validate_evidence_envelope(semantic, None)["code"] == "BLOCK_EVIDENCE_RESOLVER_MISSING"; NEG += 1
x, s = f_base("SEMANTIC", "SEMANTIC"); x["resolved_evidence"]["execution_receipt"]["ref"] = "evidence://fake"
assert m.validate_evidence_envelope(x, resolver_for(s))["code"] == "BLOCK_EVIDENCE_UNRESOLVED"; NEG += 1
x, s = f_base("SEMANTIC", "SEMANTIC"); x["resolved_evidence"]["execution_receipt"]["sha256"] = "f" * 64
assert m.validate_evidence_envelope(x, resolver_for(s))["code"] == "BLOCK_EVIDENCE_DIGEST_MISMATCH"; NEG += 1
x, s = f_base("SEMANTIC", "SEMANTIC"); r = s["evidence://f/current"]; r["resolver_id"] = "S31_F_PRODUCER"; b = x["resolved_evidence"]["authority_currentness_receipt"]; b["resolver_id"] = "S31_F_PRODUCER"; b["sha256"] = digest(r)
assert m.validate_evidence_envelope(x, resolver_for(s))["code"] == "BLOCK_EVIDENCE_SELF_RESOLVER"; NEG += 1
x, s = f_base("SEMANTIC", "SEMANTIC"); r = s["evidence://f/current"]; r["currentness"] = "STALE"; x["resolved_evidence"]["authority_currentness_receipt"]["sha256"] = digest(r)
assert m.validate_evidence_envelope(x, resolver_for(s))["code"] == "BLOCK_F_AUTHORITY_CURRENTNESS_RECEIPT_MISMATCH"; NEG += 1
x, s = f_base("SEMANTIC", "SEMANTIC"); r = s["evidence://f/provenance"]; r["reconstructible"] = False; x["resolved_evidence"]["provenance_receipt"]["sha256"] = digest(r)
assert m.validate_evidence_envelope(x, resolver_for(s))["code"] == "BLOCK_F_PROVENANCE_RECEIPT_MISMATCH"; NEG += 1
x, s = f_base("STRUCTURAL", "BEHAVIORAL")
assert schema_errors(F_SCHEMA, x); NEG += 1
x, s = f_base(); x["extensions"]["s31.f.extra"] = {"owner_specific": "preserved"}
assert not schema_errors(F_SCHEMA, x); POS += 1

# G: request invariants and typed output prevents nested authority grants.
g = g_request()
assert not schema_errors(G_REQUEST_SCHEMA, g)
assert m.validate_runtime_port_request(g)["status"] == m.PASS
POS += 1
x = copy.deepcopy(g); x["runtime_policy"]["silent_fallback_allowed"] = True
assert schema_errors(G_REQUEST_SCHEMA, x); NEG += 1
x = copy.deepcopy(g); x["authority_decisions_forbidden"].pop()
assert schema_errors(G_REQUEST_SCHEMA, x); NEG += 1
out = g_output()
assert not schema_errors(G_OUTPUT_SCHEMA, out)
assert m.validate_runtime_port_output(out)["status"] == m.PASS
POS += 1
x = copy.deepcopy(out); x["runtime_receipt"]["production_authorized"] = True
assert schema_errors(G_OUTPUT_SCHEMA, x)
assert m.validate_runtime_port_output(x)["code"] == "BLOCK_G_NESTED_AUTHORITY_FLAG"; NEG += 1
x = copy.deepcopy(out); x["runtime_receipt"]["authority_effects"] = ["ENABLE_PRODUCTION"]
assert schema_errors(G_OUTPUT_SCHEMA, x)
assert m.validate_runtime_port_output(x)["code"] == "BLOCK_G_NESTED_AUTHORITY_EFFECT"; NEG += 1
x = copy.deepcopy(out); x["runtime_receipt"]["authority_grants_allowed"] = True
assert schema_errors(G_OUTPUT_SCHEMA, x)
assert m.validate_runtime_port_output(x)["code"] == "BLOCK_G_NESTED_AUTHORITY_GRANT_ALLOWED"; NEG += 1
x = copy.deepcopy(out); x["runtime_receipt"]["nested"] = {"golden_authorized": True}
assert schema_errors(G_OUTPUT_SCHEMA, x)
assert m.validate_runtime_port_output(x)["code"] == "BLOCK_G_NESTED_AUTHORITY_FLAG"; NEG += 1

assert POS >= 8, POS
assert NEG >= 25, NEG
print(json.dumps({
    "contract": "S31_DG_CONTRACT_MATRIX_V0_2",
    "schemas_valid": ["D_TYPED_CONTEXT_V0_2", "E_CAPABILITY_MANIFEST_V0_3", "F_EVIDENCE_ENVELOPE_V0_3", "G_RUNTIME_REQUEST_V0_1", "G_RUNTIME_OUTPUT_V0_1"],
    "positive_cases": POS,
    "negative_fail_closed_cases": NEG,
    "result": "PASS"
}, sort_keys=True))
