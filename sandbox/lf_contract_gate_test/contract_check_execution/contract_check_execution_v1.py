#!/usr/bin/env python3
"""Minimal executable composition for the single Contract Check solution.

This module closes the development-only execution gap between an already-resolved
caller operation context and the existing Contract Check semantic stack:

    explicit operation_code + authority snapshot
      -> Contract Resolution carrier
      -> explicit TYPED / LEGACY_TRANSLATION bindings
      -> Final Thin Carrier
      -> Semantic Integration -> Predicate Semantics -> Core

It does not decide applicability, infer operation identity, query Supabase, infer
legacy meaning, create facts/evidence, call sibling controls, or mutate state.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RESOLUTION_PATH = ROOT / "sandbox/lf_contract_gate_test/contract_resolution/contract_resolution_carrier_v1.py"
CONTRACT_CHECK_PATH = ROOT / "sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py"

SCHEMA_VERSION = "lf-contract-check-execution-request/v1"
CANONICAL_AUTHORITY_SOURCE = "public.lf_operation_contracts"


class ContractCheckExecutionInputError(ValueError):
    pass


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot_load:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


RESOLUTION = _load(RESOLUTION_PATH, "contract_resolution_carrier_v1_for_contract_check_execution")
CONTRACT_CHECK = _load(CONTRACT_CHECK_PATH, "contract_check_carrier_v1_for_execution")


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ContractCheckExecutionInputError(f"{label}_must_be_object")
    return value


def _text(row: Mapping[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else ""


def _validate_packet(packet: Any) -> tuple[str, str, list[Mapping[str, Any]], list[Any], Mapping[str, Any]]:
    p = _mapping(packet, "packet")
    allowed_top = {"schema_version", "phase", "operation_context", "bindings", "facts"}
    extra_top = sorted(set(p) - allowed_top)
    if extra_top:
        raise ContractCheckExecutionInputError("unexpected_top_level_keys:" + ",".join(extra_top))
    if p.get("schema_version") != SCHEMA_VERSION:
        raise ContractCheckExecutionInputError("schema_version_invalid")

    phase = _text(p, "phase")
    if phase not in {"ENTRY", "CLOSURE"}:
        raise ContractCheckExecutionInputError("phase_invalid")

    context = _mapping(p.get("operation_context"), "operation_context")
    allowed_context = {"operation_code", "authority_source", "authority_contracts"}
    extra_context = sorted(set(context) - allowed_context)
    if extra_context:
        raise ContractCheckExecutionInputError("unexpected_operation_context_keys:" + ",".join(extra_context))

    operation_code = _text(context, "operation_code")
    if not operation_code:
        raise ContractCheckExecutionInputError("operation_code_missing")
    if context.get("authority_source") != CANONICAL_AUTHORITY_SOURCE:
        raise ContractCheckExecutionInputError("authority_source_invalid")

    authority_contracts = context.get("authority_contracts")
    if not isinstance(authority_contracts, list):
        raise ContractCheckExecutionInputError("authority_contracts_must_be_array")
    if any(not isinstance(row, Mapping) for row in authority_contracts):
        raise ContractCheckExecutionInputError("authority_contract_row_must_be_object")

    bindings = p.get("bindings")
    if not isinstance(bindings, list):
        raise ContractCheckExecutionInputError("bindings_must_be_array")

    facts = _mapping(p.get("facts"), "facts")
    return phase, operation_code, authority_contracts, bindings, facts


def run(packet: Any) -> dict[str, Any]:
    """Execute the already-designed Contract Check chain without adding semantics."""
    phase, operation_code, authority_contracts, bindings, facts = _validate_packet(packet)

    resolution = RESOLUTION.run(
        {
            "schema_version": RESOLUTION.REQUEST_SCHEMA_VERSION,
            "operation_code": operation_code,
            "authority_source": CANONICAL_AUTHORITY_SOURCE,
            "contracts": authority_contracts,
        }
    )

    semantic_packet = {
        "schema_version": CONTRACT_CHECK.INTEGRATION.INPUT_SCHEMA_VERSION,
        "phase": phase,
        "resolution": resolution,
        "bindings": bindings,
        "facts": dict(facts),
    }
    return CONTRACT_CHECK.run(semantic_packet)


def _emit(stream, payload: Mapping[str, Any], pretty: bool = False) -> None:
    kwargs = {"sort_keys": True, "ensure_ascii": True}
    if pretty:
        text = json.dumps(payload, indent=2, **kwargs)
    else:
        text = json.dumps(payload, separators=(",", ":"), **kwargs)
    stream.write(text + "\n")


def _read_packet(input_path: str) -> Any:
    raw = sys.stdin.read() if input_path == "-" else Path(input_path).read_text(encoding="utf-8")
    return json.loads(raw)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Execute Contract Check from explicit operation context")
    parser.add_argument("--input", default="-", help="JSON packet path, or '-' for stdin")
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args(argv)

    try:
        packet = _read_packet(args.input)
        result = run(packet)
    except (OSError, UnicodeError) as exc:
        _emit(sys.stderr, {"error": "EXECUTION_INPUT_READ_ERROR", "detail": str(exc)}, args.pretty)
        return 3
    except json.JSONDecodeError as exc:
        _emit(sys.stderr, {"error": "EXECUTION_JSON_INVALID", "detail": f"line={exc.lineno} column={exc.colno}"}, args.pretty)
        return 3
    except ContractCheckExecutionInputError as exc:
        _emit(sys.stderr, {"error": "EXECUTION_INPUT_INVALID", "detail": str(exc)}, args.pretty)
        return 3
    except RESOLUTION.ContractResolutionCarrierError as exc:
        _emit(sys.stderr, {"error": "CONTRACT_RESOLUTION_INPUT_INVALID", "detail": str(exc)}, args.pretty)
        return 3
    except RESOLUTION.CORE.ContractResolutionError as exc:
        detail = str(exc)
        code = 2 if detail.startswith("BLOCK_") else 3
        _emit(sys.stderr, {"error": "CONTRACT_RESOLUTION_BLOCKED" if code == 2 else "CONTRACT_RESOLUTION_INVALID", "detail": detail}, args.pretty)
        return code
    except CONTRACT_CHECK.ContractCheckCarrierError as exc:
        _emit(sys.stderr, {"error": "CONTRACT_CHECK_CARRIER_INVALID", "detail": str(exc)}, args.pretty)
        return 3
    except CONTRACT_CHECK.INTEGRATION.ContractCheckSemanticIntegrationInputError as exc:
        _emit(sys.stderr, {"error": "CONTRACT_CHECK_INPUT_INVALID", "detail": str(exc)}, args.pretty)
        return 3

    _emit(sys.stdout, result, args.pretty)
    return 0 if result.get("verdict") == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
