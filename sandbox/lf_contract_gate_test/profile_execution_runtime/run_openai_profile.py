#!/usr/bin/env python3
"""Run one governed repository profile through OpenAI Responses with provider readback."""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path

from openai_responses_runtime import (
    OpenAIResponsesAdapter,
    OpenAIResponsesReadbackVerifier,
)
from profile_runtime_runner import RuntimeExecutionBlocked, execute_profile_runtime


def _source_arg(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("--source must use REF=PATH")
    ref, path = value.split("=", 1)
    ref = ref.strip()
    path = path.strip()
    if not ref or not path:
        raise argparse.ArgumentTypeError("--source must use non-empty REF=PATH")
    return ref, Path(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile-code", required=True)
    parser.add_argument("--profile-slug", required=True)
    parser.add_argument(
        "--source",
        action="append",
        type=_source_arg,
        required=True,
        help="Canonical profile source as REF=PATH; repeat for every source.",
    )
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--input")
    input_group.add_argument("--input-file", type=Path)
    parser.add_argument("--execution-id")
    parser.add_argument("--model")
    parser.add_argument("--reasoning-effort")
    parser.add_argument("--max-output-tokens", type=int, default=16000)
    args = parser.parse_args()

    profile_sources = []
    for ref, path in args.source:
        try:
            content = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise SystemExit(f"cannot read profile source {path}: {exc}") from exc
        profile_sources.append({"ref": ref, "content": content})

    if args.input_file:
        try:
            input_literal = args.input_file.read_text(encoding="utf-8")
        except OSError as exc:
            raise SystemExit(f"cannot read input file {args.input_file}: {exc}") from exc
    else:
        input_literal = args.input

    execution_id = args.execution_id or f"EXEC-PROFILE-OPENAI-{uuid.uuid4()}"
    adapter = OpenAIResponsesAdapter(
        model=args.model,
        reasoning_effort=args.reasoning_effort,
        max_output_tokens=args.max_output_tokens,
    )
    verifier = OpenAIResponsesReadbackVerifier()

    try:
        package = execute_profile_runtime(
            execution_id=execution_id,
            profile_code=args.profile_code,
            profile_slug=args.profile_slug,
            profile_sources=profile_sources,
            input_literal=input_literal,
            adapter=adapter,
            attestation_verifier=verifier,
            allow_test_doubles=False,
        )
    except RuntimeExecutionBlocked as exc:
        detail = f": {exc.detail}" if exc.detail else ""
        print(f"BLOCK {exc.code}{detail}", file=sys.stderr)
        return 2

    print(json.dumps(package, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
