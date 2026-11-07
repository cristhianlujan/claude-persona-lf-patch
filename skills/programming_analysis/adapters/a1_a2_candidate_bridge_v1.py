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


def prepare_candidate(a1_input, a2_signals, expected_business=None,
                      run_readback=None, actor_parent_execution_id=None):
    a1 = _load("steps/a1/validators/run.py", "analysis_a1_step").run(a1_input)
    a2 = _load("steps/a2/validators/run.py", "analysis_a2_step").run(a1, a2_signals)
    # No caller field authenticates readback. Pending READ_ONLY native flow
    # does not have final COMPLETED invocation or evidence_ref before judge.
    # Child RUN and immutable step 0 are mandatory; fail closed otherwise.
    rows = run_readback if isinstance(run_readback, dict) else {}
    run_binding = _load(
        "adapters/native_pending_run_binding_v1.py", "analysis_pending_run_business_binding"
    ).verify_pending(
        rows.get("parent_run"), rows.get("skill_invocation"),
        rows.get("child_run"), rows.get("step0"), actor_parent_execution_id,
    )
    resolved_business = run_binding.get("business") if (
        run_binding.get("status") == "CANDIDATE_PENDING_RUN_CONSISTENT"
        and (expected_business is None or expected_business == run_binding["business"])
    ) else None
    handoff = _load("adapters/a2_a3_business_handoff_v1.py", "analysis_a2_a3_scope_guard").prepare_candidate(
        a1, a2, resolved_business
    )
    return {
        "schema_version": "A1_A2_SOURCE_CANDIDATE_BRIDGE_V1",
        "skill_code": "PROGRAMMING_ANALYSIS_LF",
        "a1_result": a1,
        "a2_result": a2,
        "a3_handoff_candidate": handoff,
        "run_business_binding_candidate": run_binding,
        "runtime_qualified": False,
        "external_invocation_count": 0,
        "next_step": None,
        "no_write_performed": True,
    }



def prepare_semantic_transport(raw_request, *, business, semantic_producer,
                               semantic_reviewer, depth_signals=None,
                               evidence_refs=None):
    """A1 -> A2 source-only handoff, no RUN/Router/external side effects.

    Semantic hints are NOT the nine evidence-derived depth signals. A1 cannot
    assert CURRENT authority, reversibility or materiality from a user phrase.
    """
    a1 = _load("steps/a1/validators/run.py", "analysis_a1_semantic_step").run(
        raw_request, business=business, semantic_producer=semantic_producer,
        semantic_reviewer=semantic_reviewer,
    )
    if a1["status"] != "VALID_OUTPUT":
        return {
            "schema_version": "A1_A2_SEMANTIC_TRANSPORT_CANDIDATE_V1",
            "status": "HALTED_AT_A1", "a1_result": a1,
            "a2_signal_bundle": None, "a2_result": None,
            "no_run_created": True,
        }
    intent = a1["intent_analysis"]
    hint = {
        "change_type": intent["operation"]["kind"],
        "target_granularity": intent["target"]["artifact_kind"],
        "target_ref": a1["payload"]["target_hints"][0],
        "business": a1["business"],
        "analysis_hints": intent["analysis_hints"],
        "dimensions_to_investigate": intent["dimensions_to_investigate"],
    }
    if not isinstance(depth_signals, dict) or not isinstance(evidence_refs, list) or not evidence_refs:
        return {
            "schema_version": "A1_A2_SEMANTIC_TRANSPORT_CANDIDATE_V1",
            "status": "A1_READY_A2_EVIDENCE_REQUIRED",
            "a1_result": a1, "a2_intent_hint": hint,
            "a2_signal_bundle": None, "a2_result": None,
            "missing": ["EVIDENCE_DERIVED_NINE_DEPTH_SIGNALS", "A2_EVIDENCE_REFS"],
            "no_run_created": True,
        }
    bundle = {
        "schema_version": "ANALYSIS_A2_TYPED_SIGNAL_CANDIDATE_V1",
        "business": a1["business"],
        "target_ref": hint["target_ref"],
        "change_type": hint["change_type"],
        "target_granularity": hint["target_granularity"],
        "nested_parent_ref": None,
        "evidence_refs": evidence_refs,
        "depth_signals": depth_signals,
    }
    a2 = _load("steps/a2/validators/run.py", "analysis_a2_semantic_step").run(a1, bundle)
    return {
        "schema_version": "A1_A2_SEMANTIC_TRANSPORT_CANDIDATE_V1",
        "status": "A2_CANDIDATE_RETURNED" if a2["status"] != "BLOCKED" else "BLOCKED_AT_A2",
        "a1_result": a1, "a2_intent_hint": hint,
        "a2_signal_bundle": bundle, "a2_result": a2,
        "no_run_created": True,
    }
