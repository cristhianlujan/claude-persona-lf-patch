#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "s31_dg_v03", ROOT / "validate_s31_dg_contracts_v0_3.py"
)
m = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = m
assert spec.loader is not None
spec.loader.exec_module(m)

RESOLVER = m.TrustedRefResolver(ROOT)
HEAD = RESOLVER.head
TRUST = m.TRUSTED_RESOLVER_ID
HISTORICAL = "191b53fca993bf28aefccf5e1e67007ad9a35dfa"
EVIDENCE = "sandbox/lf_contract_gate_test/s31_bootstrap/trusted_evidence"
POS = 0
NEG = 0


def ref(name: str, revision: str | None = None) -> str:
    return f"github://{RESOLVER.repo}@{revision or HEAD}/{EVIDENCE}/{name}"


def obs(name: str):
    return RESOLVER.resolve(ref(name))


def binding(name: str) -> dict:
    observed = obs(name)
    return {
        "ref": ref(name),
        "sha256": observed["sha256"],
        "resolver_id": TRUST,
    }


def sha(name: str) -> str:
    return obs(name)["sha256"]


def canonical(value) -> str:
    return hashlib.sha256(
        json.dumps(
            value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")
    ).hexdigest()


def f_base(level: str = "STRUCTURAL", ceiling: str = "STRUCTURAL") -> dict:
    inp = {"x": 1}
    out = {"ok": True}
    executed = level != "STRUCTURAL"
    value = {
        "receipt_version": "LF_EVIDENCE_V0_3",
        "run_id": "run-001",
        "producer_id": "S31_F_PRODUCER",
        "capability_or_gate_id": "S31-F",
        "input": {
            "exact": inp,
            "digest": canonical(inp),
            "source_refs": [ref("provenance_source.txt")],
            "source_digests": [sha("provenance_source.txt")],
        },
        "validation_or_transformation": "DETERMINISTIC_VALIDATE",
        "output": {
            "exact": out,
            "digest": canonical(out),
            "ref": "receipt://out",
        },
        "execution_identity": {
            "executed": executed,
            "execution_ref_kind": "BRANCH_HEAD" if executed else "NOT_EXECUTED",
            "executed_sha": HEAD if executed else None,
            "execution_id": "exec-001" if executed else None,
        },
        "environment": "SANDBOX",
        "authority": {
            "source": "LF_AUTHORITY",
            "source_ref": ref("source_authority.txt"),
            "source_digest": sha("source_authority.txt"),
            "source_revision": HEAD,
            "currentness": "CURRENT" if executed else "UNKNOWN",
        },
        "provenance": {
            "reconstructible": executed,
            "refs": [ref("provenance_source.txt")],
            "digests": [sha("provenance_source.txt")],
        },
        "owner_receipt": {
            **binding("f_owner_receipt.json"),
            "owner_capability_id": "S31-F",
            "preserved_without_rewrite": True,
        },
        "extensions": {"s31.f.v03": {"strict_execution_binding": True}},
        "evidence_level": level,
        "claim_ceiling": ceiling,
        "first_bad_hop": None,
        "repair_disposition": "NONE",
    }
    if executed:
        value["resolved_evidence"] = {
            "execution_receipt": binding("f_execution_receipt.json"),
            "authority_currentness_receipt": binding("f_authority_receipt.json"),
            "provenance_receipt": binding("f_provenance_receipt.json"),
        }
    return value


def g_request(context_name: str) -> dict:
    return {
        "port_version": "LF_RUNTIME_EXECUTION_PORT_V0_1_CANDIDATE",
        "request_id": "run-001",
        "typed_context_ref": ref(context_name),
        "typed_context_sha256": sha(context_name),
        "typed_context_resolver_id": TRUST,
        "governed_input": {"prompt": "bounded"},
        "output_contract_ref": "lf_runtime_execution_output_v0_1_candidate.schema.json",
        "execution_budget": {"max_runtime_ms": 1000, "max_output_units": 2000},
        "runtime_policy": {
            "provider_or_adapter": "PROFILE_RUNTIME_EXECUTOR_ADAPTER",
            "silent_fallback_allowed": False,
        },
        "authority_decisions_forbidden": [
            "AUTHORITY",
            "CURRENTNESS",
            "CARD_APPLICABILITY",
            "PROMOTION",
            "GOLDEN",
            "PRODUCTION",
        ],
    }


# F positive: all providers are bound to the exact execution revision.
f = f_base("SEMANTIC", "SEMANTIC")
assert m.validate_evidence_envelope(f, RESOLVER)["status"] == m.PASS
POS += 1

# IR-002 exploit: STRUCTURAL owner receipt resolved but not bound to envelope capability.
x = f_base()
x["capability_or_gate_id"] = "OTHER"
assert m.v2.validate_evidence_envelope(x, RESOLVER)["status"] == m.PASS
assert (
    m.validate_evidence_envelope(x, RESOLVER)["code"]
    == "BLOCK_F_OWNER_CAPABILITY_BINDING_MISMATCH"
)
NEG += 1

# IR-002 exploit: content-current historical receipts are not execution-bound.
for key in ("authority_currentness_receipt", "provenance_receipt"):
    x = f_base("SEMANTIC", "SEMANTIC")
    x["resolved_evidence"][key]["ref"] = ref(
        "f_authority_receipt.json"
        if key == "authority_currentness_receipt"
        else "f_provenance_receipt.json",
        HISTORICAL,
    )
    assert m.v2.validate_evidence_envelope(x, RESOLVER)["status"] == m.PASS
    result = m.validate_evidence_envelope(x, RESOLVER)
    assert result["code"] == "BLOCK_F_PROVIDER_REVISION_NOT_EXECUTION_BOUND", result
    NEG += 1

# IR-002 exploit: provenance source can be historical with identical bytes.
x = f_base("SEMANTIC", "SEMANTIC")
x["provenance"]["refs"] = [ref("provenance_source.txt", HISTORICAL)]
assert m.v2.validate_evidence_envelope(x, RESOLVER)["status"] == m.PASS
result = m.validate_evidence_envelope(x, RESOLVER)
assert result["code"] == "BLOCK_F_PROVIDER_REVISION_NOT_EXECUTION_BOUND", result
NEG += 1

# G positive: exact context plus governed internals all resolve.
g = g_request("typed_context.json")
assert m.v2.validate_runtime_port_request(g, RESOLVER)["status"] == m.PASS
assert m.validate_runtime_port_request(g, RESOLVER)["status"] == m.PASS
POS += 1

# IR-002 exploit: outer context hash can be correct while internal authority is invalid.
x = g_request("typed_context_invalid_authority.json")
assert m.v2.validate_runtime_port_request(x, RESOLVER)["status"] == m.PASS
result = m.validate_runtime_port_request(x, RESOLVER)
assert result["code"] == "BLOCK_G_TYPED_CONTEXT_SEMANTIC_GOVERNANCE", result
assert result["nested_code"] == "BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH", result
NEG += 1

# Canonical resolver boundary remains fail-closed.
result = m.validate_runtime_port_request(g, lambda _ref: {})
assert result["code"] == "BLOCK_UNTRUSTED_RESOLVER_TYPE", result
NEG += 1

assert POS == 2, POS
assert NEG == 6, NEG
print(
    json.dumps(
        {
            "contract": "S31_DG_IR002_HARDENING_V0_3",
            "positive_cases": POS,
            "negative_fail_closed_cases": NEG,
            "base_v0_2_exploits_demonstrated_then_closed": 5,
            "trusted_resolver": TRUST,
            "result": "PASS",
        },
        sort_keys=True,
    )
)
