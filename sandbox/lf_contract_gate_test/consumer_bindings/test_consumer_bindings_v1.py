from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODULE_PATH = HERE / "consumer_bindings_v1.py"
CONTRACT_PATH = HERE / "consumer_bindings_contract_v1.json"
INVENTORY_PATH = HERE / "consumer_bindings_inventory_v1.json"
SQL_PATH = HERE / "CONSUMER_BINDINGS_source_projection_v1.sql"
README_PATH = HERE / "README.md"

spec = importlib.util.spec_from_file_location("consumer_bindings_v1", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

checks = 0

def check(condition: bool, message: str) -> None:
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1

contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
sql = SQL_PATH.read_text(encoding="utf-8")
readme = README_PATH.read_text(encoding="utf-8")

validated = mod.validate_contract(contract)
check(validated is contract, "contract validates")
check(contract["schema_version"] == mod.SCHEMA_VERSION, "schema")
check(contract["expected_target"] == mod.EXPECTED_TARGET, "target")
check(contract["canonical_authority"]["registry"] == mod.CANONICAL_REGISTRY, "registry")
check(contract["canonical_authority"]["current"] == mod.CANONICAL_CURRENT, "current")
check(contract["canonical_authority"]["relations"] == mod.CANONICAL_RELATIONS, "relations")
check(contract["canonical_authority"]["owner_runner_carrier"] == mod.OWNER_RUNNER_CARRIER_AUTHORITY, "owner authority")
check(contract["canonical_authority"]["entry_guard"] == mod.ENTRY_GUARD, "guard")
check(contract["canonical_authority"]["binding_entrypoint"] == mod.CANONICAL_BIND_ENTRYPOINT, "bind entrypoint")
check(contract["invariants"]["parallel_binding_registry"] is False, "no parallel registry")
check(contract["invariants"]["owner_recalculation"] is False, "no owner recalc")
check(contract["invariants"]["binding_bypass_allowed"] is False, "no bypass")
check(contract["invariants"]["applicability_rediscovery"] is False, "no applicability rediscovery")
check(contract["invariants"]["cutover_executed"] is False, "no cutover")
check(contract["invariants"]["runtime_activated"] is False, "no runtime")
check(contract["invariants"]["production_activated"] is False, "no production")
check(contract["invariants"]["artifact_transport_policy"] == mod.ARTIFACT_POLICY, "artifact policy")
check(len(contract["consumers"]) == 3, "consumer count")
post = next(x for x in contract["consumers"] if x["consumer_code"] == "POST_PASE_ORCHESTRATOR_V1")
check(len(post["capabilities"]) == 7, "post-pase capability count")
check(post["binding_bypass_allowed"] is False, "post-pase no bypass")
check(post["legacy_execution_path_retained"] is True, "legacy retained until L5")
reuse = mod.validate_reuse_sources(contract, ROOT)
check(reuse["PASE_ORCHESTRATOR_V1"].startswith("REUSE_PATH_VALIDATED"), "pase reuse")
check(reuse["ASSURANCE_EVALUATOR"].startswith("REUSE_PATH_VALIDATED"), "assurance reuse")
check(inventory["parallel_registry_count"] == 0, "inventory no parallel registry")
check(inventory["owner_recalculation_count"] == 0, "inventory no owner recalc")
check(inventory["binding_bypass_count"] == 0, "inventory no bypass")
check(inventory["zip_authority"] is False, "inventory no zip authority")
check("create table" not in sql.lower(), "source projection creates no table")
check("insert into public.lf_capability_registry" not in sql.lower(), "does not write capability registry")
check("insert into public.lf_capability_current" not in sql.lower(), "does not write current pointer")
check("public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text)" in sql, "canonical bind function precondition")
check("insert into public.lf_activo_relaciones" in sql.lower(), "material relations projection")
check("PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1" in readme, "no zip policy documented")
check("SADM-PP-L5-022" in readme, "cutover deferred")

digest1 = mod.sha256_json(contract)
digest2 = mod.sha256_json(json.loads(json.dumps(contract)))
check(digest1 == digest2 and len(digest1) == 64, "stable manifest digest")

call = mod.build_bind_call(
    consumer_execution_id="EXEC-1",
    capability_code="CURRENTNESS_AUTHORITY",
    expected_manifest_sha256="a" * 64,
    plan_digest="b" * 64,
    dispatch_receipt_id="11111111-1111-4111-8111-111111111111",
    actor_execution_id="ACTOR-1",
)
check(call["entrypoint"] == mod.CANONICAL_BIND_ENTRYPOINT, "call entrypoint")
check(call["owner_authority"] == mod.OWNER_RUNNER_CARRIER_AUTHORITY, "call owner authority")
check(call["args"]["p_capability_code"] == "CURRENTNESS_AUTHORITY", "call capability")

ready = mod.validate_bind_readback({
    "ready": True,
    "entry_guard": {"decision": "ORCHESTRATOR_ENTRY_ACCEPTED", "guard_code": mod.ENTRY_GUARD},
    "binding": {"decision": "READY_CURRENT", "manifest_sha256": "c" * 64},
})
check(ready["ready"] is True, "ready readback")
blocked = mod.validate_bind_readback({"ready": False, "decision": "BLOCK_NO_CURRENT_CAPABILITY"})
check(blocked == {"ready": False, "decision": "BLOCK_NO_CURRENT_CAPABILITY"}, "typed block readback")

bad = copy.deepcopy(contract)
bad["invariants"]["parallel_binding_registry"] = True
try:
    mod.validate_contract(bad)
    raise AssertionError("parallel registry should block")
except mod.ConsumerBindingError as exc:
    check(str(exc) == "BLOCK_PARALLEL_BINDING_REGISTRY", "parallel registry blocks")

bad = copy.deepcopy(contract)
bad["consumers"].append(copy.deepcopy(bad["consumers"][0]))
try:
    mod.validate_contract(bad)
    raise AssertionError("duplicate consumer should block")
except mod.ConsumerBindingError as exc:
    check(str(exc) == "BLOCK_DUPLICATE_CONSUMER", "duplicate consumer blocks")

try:
    mod.build_bind_call(
        consumer_execution_id="EXEC-1", capability_code="CURRENTNESS_AUTHORITY",
        expected_manifest_sha256="bad", plan_digest="b" * 64,
        dispatch_receipt_id="11111111-1111-4111-8111-111111111111", actor_execution_id="ACTOR-1")
    raise AssertionError("invalid manifest should block")
except mod.ConsumerBindingError as exc:
    check(str(exc) == "BLOCK_INVALID_EXPECTED_MANIFEST_SHA256", "invalid manifest blocks")

try:
    mod.build_bind_call(
        consumer_execution_id="EXEC-1", capability_code="CURRENTNESS_AUTHORITY",
        expected_manifest_sha256="a" * 64, plan_digest="b" * 64,
        dispatch_receipt_id="not-a-uuid", actor_execution_id="ACTOR-1")
    raise AssertionError("invalid receipt should block")
except mod.ConsumerBindingError as exc:
    check(str(exc) == "BLOCK_INVALID_DISPATCH_RECEIPT_ID", "invalid receipt blocks")

try:
    mod.validate_bind_readback({
        "ready": True,
        "entry_guard": {"decision": "ORCHESTRATOR_ENTRY_ACCEPTED", "guard_code": "WRONG"},
        "binding": {"decision": "READY_CURRENT", "manifest_sha256": "c" * 64},
    })
    raise AssertionError("wrong guard should block")
except mod.ConsumerBindingError as exc:
    check(str(exc) == "BLOCK_BIND_READBACK_GUARD_CODE", "wrong guard blocks")

print(f"PASS_CONSUMER_BINDINGS_V1 checks={checks}")
