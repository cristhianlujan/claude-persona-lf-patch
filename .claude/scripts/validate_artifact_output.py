#!/usr/bin/env python3
"""Validate artifact encoding, structure, parsability, counts, and wrapper safety."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

FENCE_RE = re.compile(r"^(?P<indent> {0,3})(?P<fence>`{3,}|~{3,})(?P<info>.*)$")
BACKTICK_RUN_RE = re.compile(r"`+")
TILDE_RUN_RE = re.compile(r"~+")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate one textual artifact and emit machine-readable evidence."
    )
    parser.add_argument("path", type=Path)
    parser.add_argument(
        "--format",
        choices=("auto", "text", "markdown", "json", "yaml", "python"),
        default="auto",
    )
    parser.add_argument("--expected-sha256")
    parser.add_argument("--expected-bytes", type=int)
    parser.add_argument("--expected-lines", type=int)
    parser.add_argument("--require-final-newline", action="store_true")
    return parser.parse_args()


def detect_format(path: Path, requested: str) -> str:
    if requested != "auto":
        return requested
    suffix = path.suffix.lower()
    return {
        ".md": "markdown",
        ".markdown": "markdown",
        ".json": "json",
        ".yaml": "yaml",
        ".yml": "yaml",
        ".py": "python",
    }.get(suffix, "text")


def max_run(pattern: re.Pattern[str], text: str) -> int:
    return max((len(match.group(0)) for match in pattern.finditer(text)), default=0)


def recommended_wrapper(text: str) -> dict[str, Any]:
    backticks = max_run(BACKTICK_RUN_RE, text)
    tildes = max_run(TILDE_RUN_RE, text)
    candidates = [
        ("`", max(4, backticks + 1)),
        ("~", max(4, tildes + 1)),
    ]
    char, length = min(candidates, key=lambda item: (item[1], item[0] != "`"))
    return {
        "character": "backtick" if char == "`" else "tilde",
        "length": length,
        "opening": char * length,
        "closing": char * length,
        "longest_backtick_run": backticks,
        "longest_tilde_run": tildes,
    }


def validate_markdown_fences(text: str) -> list[dict[str, Any]]:
    errors: list[dict[str, Any]] = []
    active: tuple[str, int, int] | None = None

    for line_number, line in enumerate(text.splitlines(), start=1):
        match = FENCE_RE.match(line)
        if not match:
            continue

        fence = match.group("fence")
        char = fence[0]
        length = len(fence)
        info = match.group("info")

        if active is None:
            active = (char, length, line_number)
            continue

        active_char, active_length, _opening_line = active
        if char == active_char and length >= active_length and not info.strip():
            active = None

    if active is not None:
        char, length, opening_line = active
        errors.append(
            {
                "assertion": "markdown_fence_balanced",
                "message": "Unclosed Markdown fence.",
                "opening_line": opening_line,
                "character": char,
                "length": length,
            }
        )

    return errors


def parse_payload(text: str, artifact_format: str) -> tuple[str, list[dict[str, Any]]]:
    errors: list[dict[str, Any]] = []

    try:
        if artifact_format == "json":
            json.loads(text)
        elif artifact_format == "yaml":
            try:
                import yaml  # type: ignore
            except ImportError as exc:
                return "BLOCKED", [
                    {
                        "assertion": "yaml_parser_available",
                        "message": "Install PyYAML to validate YAML artifacts.",
                        "detail": str(exc),
                    }
                ]
            yaml.safe_load(text)
        elif artifact_format == "python":
            compile(text, "<artifact>", "exec")
        elif artifact_format == "markdown":
            errors.extend(validate_markdown_fences(text))
    except Exception as exc:
        errors.append(
            {
                "assertion": f"{artifact_format}_parse",
                "message": str(exc),
            }
        )

    return ("FAIL" if errors else "PASS"), errors


def line_count(text: str) -> int:
    if not text:
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def main() -> int:
    args = parse_args()
    path: Path = args.path

    if not path.is_file():
        print(
            json.dumps(
                {
                    "result": "BLOCKED",
                    "blocking_assertions": ["artifact_path_is_file = false"],
                    "artifact_path": str(path),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
        return 2

    raw = path.read_bytes()
    errors: list[dict[str, Any]] = []

    if raw.startswith(b"\xef\xbb\xbf"):
        errors.append(
            {
                "assertion": "utf8_without_bom",
                "message": "UTF-8 BOM detected.",
            }
        )

    try:
        text = raw.decode("utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8")
    except UnicodeDecodeError as exc:
        print(
            json.dumps(
                {
                    "result": "FAIL",
                    "artifact_path": str(path),
                    "failed_assertions": [
                        {
                            "assertion": "utf8_decodable",
                            "message": str(exc),
                        }
                    ],
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
        return 1

    if b"\r\n" in raw or b"\r" in raw.replace(b"\r\n", b""):
        errors.append(
            {
                "assertion": "line_endings_lf",
                "message": "CR or CRLF line endings detected.",
            }
        )

    if args.require_final_newline and raw and not raw.endswith(b"\n"):
        errors.append(
            {
                "assertion": "final_newline_present",
                "message": "Final newline is required.",
            }
        )

    artifact_format = detect_format(path, args.format)
    parser_result, parser_errors = parse_payload(text, artifact_format)
    errors.extend(parser_errors)

    sha256 = hashlib.sha256(raw).hexdigest()
    bytes_count = len(raw)
    lines_count = line_count(text)

    comparisons = {
        "sha256_match": (
            None
            if args.expected_sha256 is None
            else sha256.lower() == args.expected_sha256.lower()
        ),
        "bytes_match": (
            None if args.expected_bytes is None else bytes_count == args.expected_bytes
        ),
        "lines_match": (
            None if args.expected_lines is None else lines_count == args.expected_lines
        ),
    }

    for key, matched in comparisons.items():
        if matched is False:
            errors.append(
                {
                    "assertion": key,
                    "message": f"{key} = false",
                }
            )

    result = "PASS" if not errors else ("BLOCKED" if parser_result == "BLOCKED" else "FAIL")
    evidence = {
        "artifact_path": str(path),
        "format": artifact_format,
        "sha256": sha256,
        "bytes": bytes_count,
        "lines": lines_count,
        "utf8": True,
        "bom_present": raw.startswith(b"\xef\xbb\xbf"),
        "line_endings": "LF" if not any(
            error["assertion"] == "line_endings_lf" for error in errors
        ) else "MIXED_OR_CRLF",
        "final_newline": bool(raw.endswith(b"\n")),
        "parser_result": parser_result,
        "comparisons": comparisons,
        "recommended_markdown_wrapper": recommended_wrapper(text),
    }

    output = {
        "result": result,
        "compliance_bit": 1 if result == "PASS" else 0,
        "failed_assertions": errors,
        "evidence": evidence,
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if result == "PASS" else (2 if result == "BLOCKED" else 1)


if __name__ == "__main__":
    sys.exit(main())
