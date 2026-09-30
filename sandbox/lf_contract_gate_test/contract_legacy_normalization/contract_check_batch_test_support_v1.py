from __future__ import annotations

from typing import Any


def build_core_packet(
    core_module: Any,
    operation_code: str,
    typed_contract: dict[str, Any],
    evaluations: list[dict[str, Any]],
    phase: str = "CLOSURE",
) -> dict[str, Any]:
    """Build the canonical Contract Check Core input packet for batch regressions."""
    return {
        "schema_version": core_module.SCHEMA_VERSION,
        "operation_code": operation_code,
        "phase": phase,
        "contracts": [typed_contract],
        "evaluations": evaluations,
    }


def evaluate_core(
    core_module: Any,
    operation_code: str,
    typed_contract: dict[str, Any],
    evaluations: list[dict[str, Any]],
    phase: str = "CLOSURE",
) -> dict[str, Any]:
    return core_module.evaluate(
        build_core_packet(
            core_module,
            operation_code,
            typed_contract,
            evaluations,
            phase,
        )
    )
