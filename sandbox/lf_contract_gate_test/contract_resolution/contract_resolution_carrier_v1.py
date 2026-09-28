#!/usr/bin/env python3
"""Thin transport carrier for Contract Resolution Core V1."""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Mapping

CORE_PATH = Path(__file__).with_name("contract_resolution_core_v1.py")
REQUEST_SCHEMA_VERSION = "lf-contract-resolution-request/v1"
CANONICAL_AUTHORITY_SOURCE = "public.lf_operation_contracts"


class ContractResolutionCarrierError(ValueError):
    pass


def _load_core():
    spec = importlib.util.spec_from_file_location("contract_resolution_core_v1", CORE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("contract_resolution_core_unloadable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CORE = _load_core()


def _emit(stream, payload: dict[str, Any], pretty: bool = False) -> None:
    if pretty:
        text = json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=True)
    else:
        text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    stream.write(text + "\n")


def _read_packet(input_path: str) -> Any:
    if input_path == "-":
        raw = sys.stdin.read()
    else:
        raw = Path(input_path).read_text(encoding="utf-8")
    return json.loads(raw)


def _validate_packet(packet: Any) -> tuple[str, list[Mapping[str, Any]]]:
    if not isinstance(packet, Mapping):
        raise ContractResolutionCarrierError("FAIL_CONTRACT_RESOLUTION_CARRIER_PACKET_SHAPE")
    if packet.get("schema_version") != REQUEST_SCHEMA_VERSION:
        raise ContractResolutionCarrierError("FAIL_CONTRACT_RESOLUTION_CARRIER_SCHEMA")
    operation_code = packet.get("operation_code")
    if not isinstance(operation_code, str) or not operation_code.strip():
        raise ContractResolutionCarrierError("FAIL_CONTRACT_RESOLUTION_CARRIER_OPERATION_CODE")
    authority_source = packet.get("authority_source")
    if authority_source != CANONICAL_AUTHORITY_SOURCE:
        raise ContractResolutionCarrierError("FAIL_CONTRACT_RESOLUTION_CARRIER_AUTHORITY_SOURCE")
    contracts = packet.get("contracts")
    if not isinstance(contracts, list):
        raise ContractResolutionCarrierError("FAIL_CONTRACT_RESOLUTION_CARRIER_CONTRACTS_SHAPE")
    return operation_code.strip(), contracts


def run(packet: Any) -> dict[str, Any]:
    operation_code, contracts = _validate_packet(packet)
    return CORE.resolve_contracts(operation_code=operation_code, contracts=contracts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Thin carrier for Contract Resolution Core V1")
    parser.add_argument("--input", default="-", help="JSON packet path, or '-' for stdin")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print result JSON")
    args = parser.parse_args(argv)

    try:
        packet = _read_packet(args.input)
    except (OSError, UnicodeError) as exc:
        _emit(sys.stderr, {"error": "CARRIER_INPUT_READ_ERROR", "detail": str(exc)}, args.pretty)
        return 3
    except json.JSONDecodeError as exc:
        _emit(
            sys.stderr,
            {"error": "CARRIER_JSON_INVALID", "detail": f"line={exc.lineno} column={exc.colno}"},
            args.pretty,
        )
        return 3

    try:
        result = run(packet)
    except ContractResolutionCarrierError as exc:
        _emit(sys.stderr, {"error": "CARRIER_PACKET_INVALID", "detail": str(exc)}, args.pretty)
        return 3
    except CORE.ContractResolutionError as exc:
        detail = str(exc)
        code = 2 if detail.startswith("BLOCK_") else 3
        _emit(
            sys.stderr,
            {
                "error": "CONTRACT_RESOLUTION_BLOCKED" if code == 2 else "CONTRACT_RESOLUTION_INVALID",
                "detail": detail,
            },
            args.pretty,
        )
        return code

    _emit(sys.stdout, result, args.pretty)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
