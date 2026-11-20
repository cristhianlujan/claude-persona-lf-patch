"""Conservative, read-only compatibility check for a PIP-1 run candidate.

It cannot authenticate a DB row; caller must obtain it through trusted RO tools.
A match is not operational admission or checkpoint authority.
"""
from collections.abc import Mapping
import re

class PreflightError(ValueError): pass
SHA40 = re.compile(r"^[a-f0-9]{40}$")
SHA64 = re.compile(r"^[a-f0-9]{64}$")

def compare_operation(run, operation: Mapping, *, observed_inventory_sha256: str) -> dict:
    run.validate()  # canonical Carril D contract
    if not isinstance(operation, Mapping): raise PreflightError("OPERATION_NOT_OBJECT")
    if not SHA64.fullmatch(observed_inventory_sha256 or ""): raise PreflightError("INVENTORY_DIGEST_INVALID")
    if run.pins.inventory_sha256 != observed_inventory_sha256: raise PreflightError("INVENTORY_DRIFT")
    if operation.get("execution_id") != run.execution_id: raise PreflightError("EXECUTION_MISMATCH")
    if operation.get("operation_code") != "CIERRE_CHECKPOINT_INGENIERIA_LF":
        raise PreflightError("OPERATION_CODE_NOT_COMPATIBLE")
    if operation.get("target_type") != "ENGINEERING_CHECKPOINT":
        raise PreflightError("TARGET_TYPE_MISMATCH")
    if operation.get("status") not in {"CREATED","IN_PROGRESS","BLOCKED","COMPLETED"}:
        raise PreflightError("UNKNOWN_OPERATION_STATUS")
    manifest = operation.get("manifest")
    if not isinstance(manifest, Mapping): raise PreflightError("MANIFEST_NOT_OBJECT")
    if manifest.get("pip1_run_id") != run.run_id: raise PreflightError("RUN_ID_UNBOUND")
    if manifest.get("inventory_sha256") != observed_inventory_sha256: raise PreflightError("INVENTORY_UNBOUND")
    if manifest.get("head_sha") != run.pins.head_sha: raise PreflightError("HEAD_UNBOUND")
    return {"schema_version":"PIP1_OPERATION_COMPATIBILITY_PREFLIGHT_V1",
            "run_id":run.run_id,"execution_id":run.execution_id,
            "identity_shape_matches":True,"source_authenticated":False,
            "authority_verified":False,"write_authorized":False,
            "transition_authorized":False,"checkpoint_accredited":False,
            "required_next":"TRUSTED_RUNTIME_READBACK_AND_INDEPENDENT_RECEIPT_VERIFIER"}
