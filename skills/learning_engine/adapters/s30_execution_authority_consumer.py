from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve()
REPO_ROOT = HERE.parents[3]
S30_DIR = REPO_ROOT / "sandbox/lf_contract_gate_test/s30_data_access_candidate"
S30_POLICY = S30_DIR / "execution_authority_policy_v1.json"
S30_MODULE = S30_DIR / "lf_execution_authority.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("lf_s30_execution_authority", S30_MODULE)
    if spec is None or spec.loader is None:
        raise RuntimeError("S30_EXECUTION_AUTHORITY_MODULE_UNRESOLVABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_authority() -> tuple[Any, dict]:
    if not S30_POLICY.is_file() or not S30_MODULE.is_file():
        raise RuntimeError("S30_EXECUTION_AUTHORITY_SOURCE_MISSING")
    module = _load_module()
    policy = module.load_execution_authority(S30_POLICY)
    if policy.get("contract_version") != "S30_EXECUTION_AUTHORITY_V1":
        raise RuntimeError("S30_EXECUTION_AUTHORITY_VERSION_MISMATCH")
    return module, policy


def prepare_learning_work(task: Mapping[str, Any]) -> dict:
    module, policy = load_authority()
    decision = module.decide_execution_authority(task, policy)
    out = {
        "consumer": "ACT-0046",
        "authority_contract": policy["contract_version"],
        "decision": decision,
        "model_request": None,
    }
    if decision.get("model_call_allowed") is True:
        out["model_request"] = module.build_model_request(task, policy)
    return out


def validate_learning_semantic_delta(model_output: Any) -> dict:
    module, policy = load_authority()
    return module.validate_semantic_delta(model_output, policy)
