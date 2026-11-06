"""Small internal A1 -> A2 candidate bridge; no Router or profile invocation."""
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    if spec is None or spec.loader is None:
        raise RuntimeError("ANALYSIS_STEP_SOURCE_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare_candidate(a1_input, a2_signals, expected_business=None):
    a1 = _load("steps/a1/validators/run.py", "analysis_a1_step").run(a1_input)
    a2 = _load("steps/a2/validators/run.py", "analysis_a2_step").run(a1, a2_signals)
    handoff = _load("adapters/a2_a3_business_handoff_v1.py", "analysis_a2_a3_scope_guard").prepare_candidate(
        a1, a2, expected_business
    )
    return {
        "schema_version": "A1_A2_SOURCE_CANDIDATE_BRIDGE_V1",
        "skill_code": "PROGRAMMING_ANALYSIS_LF",
        "a1_result": a1,
        "a2_result": a2,
        "a3_handoff_candidate": handoff,
        "runtime_qualified": False,
        "external_invocation_count": 0,
        "next_step": None,
        "no_write_performed": True,
    }
