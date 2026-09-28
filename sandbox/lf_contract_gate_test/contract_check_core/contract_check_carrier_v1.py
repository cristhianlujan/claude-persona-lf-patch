#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

CORE_PATH = Path(__file__).with_name("contract_check_core_v1.py")


def _load_core():
    spec = importlib.util.spec_from_file_location("contract_check_core_v1", CORE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("contract_check_core_unloadable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


def run(packet: Any) -> dict[str, Any]:
    core = _load_core()
    return core.evaluate(packet)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Thin carrier for Contract Check Core V1")
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

    core = _load_core()
    try:
        result = core.evaluate(packet)
    except core.ContractCheckInputError as exc:
        _emit(sys.stderr, {"error": "CARRIER_PACKET_INVALID", "detail": str(exc)}, args.pretty)
        return 3

    _emit(sys.stdout, result, args.pretty)
    if result.get("verdict") == "PASS":
        return 0
    if result.get("verdict") == "BLOCK":
        return 2
    _emit(sys.stderr, {"error": "CARRIER_RESULT_INVALID", "detail": result.get("verdict")}, args.pretty)
    return 4


if __name__ == "__main__":
    raise SystemExit(main())
