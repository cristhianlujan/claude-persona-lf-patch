#!/usr/bin/env python3
"""Thin owner boundary for reusable visual source analysis.

VISUAL_SOURCE_ANALYSIS does not create a second visual engine. It delegates to
the existing historical P0 v4 loop and exposes only the producer-side result
needed by downstream evidence validation.

Boundary:
- owns invocation of the visual producer/analysis loop;
- owns producer-side regression coverage inventory;
- does not decide applicability or repository/path admission;
- does not perform Human Review or persist human decisions;
- does not own durable evidence persistence/currentness transport;
- does not own premerge/release governance or P0-5 benchmark annotation;
- does not authorize runtime, merge or production.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any, Callable, Mapping

SCHEMA_VERSION = "lf-visual-source-analysis/v1"
RESULT_SCHEMA = "lf-visual-source-analysis-result/v1"
CONTROL_ID = "VISUAL_SOURCE_ANALYSIS"
REPO_ROOT = Path(__file__).resolve().parents[3]
HISTORICAL_SCRIPT_ROOT = REPO_ROOT / "sandbox/story_creator_p0_visual/v1.1/scripts"
HISTORICAL_ENGINE = HISTORICAL_SCRIPT_ROOT / "run_p0_visual_quality_loop_v4.py"

OWNERSHIP = {
    "visual_source_analysis": True,
    "producer_regressions": True,
    "applicability": False,
    "path_admission": False,
    "visual_evidence_gate": False,
    "human_review": False,
    "durable_evidence_persistence": False,
    "premerge_release_governance": False,
    "p0_5_benchmark_annotation": False,
    "runtime_or_production_authorization": False,
}

# Producer-only historical coverage. These commands remain physically where they
# are today; this inventory establishes ownership without copying their logic.
PRODUCER_REGRESSION_COMMANDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("ocr-causal-regression", ("sandbox/lf_contract_gate_test/P0_OCR_CAUSAL_REGRESSION_V1.py",)),
    ("text-group-family-generalization", ("sandbox/lf_contract_gate_test/P0_TEXT_GROUP_FAMILY_GENERALIZATION_V1.py",)),
    ("legacy-negative-suite", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_machine_visual_quality_negative_suite.py",)),
    ("v2-negative-restore-suite", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_machine_visual_quality_negative_suite_v2.py",)),
    ("v2-runtime-regressions", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_quality_runtime_regression_suite.py",)),
    ("v2-forward-adversarial", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_blind_forward_adversarial_test.py",)),
    ("v3-schema-contracts", ("sandbox/story_creator_p0_visual/v1.1/scripts/validate_p0_v3_schemas.py",)),
    ("v3-negative-restore-regressions", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_fidelity_v3_suite.py",)),
    ("v3-forward-adversarial", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_fidelity_forward_adversarial_v3.py",)),
    ("v3-runtime-hash-inventory", ("sandbox/story_creator_p0_visual/v1.1/scripts/verify_p0_v3_manifest.py",)),
    ("v4-contracts", ("sandbox/story_creator_p0_visual/v1.1/scripts/validate_p0_v4_closed_loop.py",)),
    ("v4-graders", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_discovery_v4_suite.py",)),
    ("v4-grader-coverage", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_grader_coverage_v4.py",)),
    ("v4-closed-loop", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_closed_loop_v4_suite.py",)),
    ("v4-known-failure-regressions", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_known_failure_regression_v4.py",)),
    ("v4-forward-adversarial", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_forward_adversarial_v4.py",)),
    ("v4-independent-omission-sweep", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_independent_omission_sweep_v4.py",)),
    ("v4-reader-producer-contract", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_reader_producer_contract_v4.py",)),
    ("v4-grader-producer-field-audit", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_grader_producer_field_audit_v4.py",)),
)

FOREIGN_HISTORICAL_COMMANDS = {
    "human-binding-selftest": "HUMAN_REVIEW_AUTHORITY",
    "legacy-integration-verifier": "LEGACY_P0_INTEGRATION_GOVERNANCE",
    "v3-premerge-compliance": "PREMERGE_RELEASE_GOVERNANCE",
    "v4-durable-state": "EVIDENCE_PERSISTENCE_STATE",
    "p0-5-blind-annotation-contract": "P0_5_BENCHMARK_ANNOTATION",
}


class VisualSourceAnalysisError(RuntimeError):
    pass


def _safe_repo_relative(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value:
        return False
    path = Path(value)
    return ".." not in path.parts and "." not in path.parts


def _validate_regression_inventory(repo_root: Path = REPO_ROOT) -> None:
    if len(PRODUCER_REGRESSION_COMMANDS) != 19:
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_REGRESSION_COUNT")
    labels = [label for label, _ in PRODUCER_REGRESSION_COMMANDS]
    paths = [args[0] for _, args in PRODUCER_REGRESSION_COMMANDS]
    if len(labels) != len(set(labels)) or len(paths) != len(set(paths)):
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_DUPLICATE_REGRESSION")
    forbidden = ("human_binding", "integration_candidate", "handoff_v3_compliance", "durable_state", "p0_5_blind_annotation")
    for label, args in PRODUCER_REGRESSION_COMMANDS:
        if not args or not _safe_repo_relative(args[0]):
            raise VisualSourceAnalysisError(f"FAIL_VISUAL_SOURCE_ANALYSIS_UNSAFE_PATH:{label}")
        lowered = args[0].lower()
        if any(token in lowered for token in forbidden):
            raise VisualSourceAnalysisError(f"FAIL_VISUAL_SOURCE_ANALYSIS_FOREIGN_REGRESSION:{label}")
        if not (repo_root / args[0]).is_file():
            raise VisualSourceAnalysisError(f"FAIL_VISUAL_SOURCE_ANALYSIS_REGRESSION_MISSING:{label}")


def _load_historical_engine(repo_root: Path = REPO_ROOT) -> Callable[..., Mapping[str, Any]]:
    script_root = repo_root / "sandbox/story_creator_p0_visual/v1.1/scripts"
    engine_path = script_root / "run_p0_visual_quality_loop_v4.py"
    if not engine_path.is_file():
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_ENGINE_MISSING")
    inserted = str(script_root)
    added = inserted not in sys.path
    if added:
        sys.path.insert(0, inserted)
    try:
        spec = importlib.util.spec_from_file_location("visual_source_analysis_historical_engine", engine_path)
        if spec is None or spec.loader is None:
            raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_ENGINE_LOAD")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
    finally:
        if added and sys.path and sys.path[0] == inserted:
            sys.path.pop(0)
    runner = getattr(module, "run_loop", None)
    if not callable(runner):
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_ENGINE_ENTRYPOINT")
    return runner


def analyze_source(
    *,
    source_path: str | Path,
    expected_source_sha256: str,
    full_reader: Callable[..., Any],
    remediator: Callable[..., Any],
    targeted_reread: Callable[..., Any],
    code_head_sha: str,
    configuration_id: str,
    configuration_sha256: str,
    regression_proof: Mapping[str, Any] | None,
    adversarial_proof: Mapping[str, Any] | None,
    artifact_hash_proof: Mapping[str, Any] | None,
    engine_runner: Callable[..., Mapping[str, Any]] | None = None,
    max_remediation_cycles: int = 5,
    required_clean_passes: int = 2,
) -> Mapping[str, Any]:
    """Run the existing producer and return a non-persistent analysis envelope."""
    runner = engine_runner or _load_historical_engine(REPO_ROOT)
    result = runner(
        source_path=str(source_path),
        expected_source_sha256=expected_source_sha256,
        full_reader=full_reader,
        remediator=remediator,
        targeted_reread=targeted_reread,
        code_head_sha=code_head_sha,
        configuration_id=configuration_id,
        configuration_sha256=configuration_sha256,
        max_remediation_cycles=max_remediation_cycles,
        required_clean_passes=required_clean_passes,
        regression_proof=regression_proof,
        adversarial_proof=adversarial_proof,
        artifact_hash_proof=artifact_hash_proof,
    )
    if not isinstance(result, Mapping):
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_ENGINE_RESULT_SHAPE")

    upstream_result = result.get("result")
    receipt = result.get("convergence_receipt")
    if upstream_result != "PASS_P0_V4_CLOSED_LOOP":
        return {
            "schema_version": RESULT_SCHEMA,
            "control_id": CONTROL_ID,
            "result": "BLOCKED",
            "upstream_result": upstream_result or "UNKNOWN",
            "evidence_receipt": None,
        }
    if not isinstance(receipt, Mapping):
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_PASS_WITHOUT_RECEIPT")

    return {
        "schema_version": RESULT_SCHEMA,
        "control_id": CONTROL_ID,
        "result": "PASS",
        "upstream_result": upstream_result,
        "evidence_receipt": dict(receipt),
    }


def self_test(repo_root: Path = REPO_ROOT) -> Mapping[str, object]:
    if not HISTORICAL_ENGINE.is_file() and repo_root == REPO_ROOT:
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_ENGINE_MISSING")
    _validate_regression_inventory(repo_root)
    true_keys = [key for key, value in OWNERSHIP.items() if value]
    if true_keys != ["visual_source_analysis", "producer_regressions"]:
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_OWNER_BOUNDARY")
    if set(FOREIGN_HISTORICAL_COMMANDS) != {
        "human-binding-selftest",
        "legacy-integration-verifier",
        "v3-premerge-compliance",
        "v4-durable-state",
        "p0-5-blind-annotation-contract",
    }:
        raise VisualSourceAnalysisError("FAIL_VISUAL_SOURCE_ANALYSIS_FOREIGN_MAP")
    print("PASS_VISUAL_SOURCE_ANALYSIS_SELFTEST=19/19")
    return {
        "schema_version": SCHEMA_VERSION,
        "control_id": CONTROL_ID,
        "producer_regression_count": len(PRODUCER_REGRESSION_COMMANDS),
        "foreign_command_count": len(FOREIGN_HISTORICAL_COMMANDS),
        "ownership": dict(OWNERSHIP),
    }
