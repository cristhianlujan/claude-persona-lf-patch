"""Detect hardcoded values, invalid token status and incomplete messages for J08."""
from __future__ import annotations

import json
import re

from lf_common import (
    add_common_input, duplicate_values, emit, failure, load_json, main_guard,
    parser, require_object, result_object, utc_now,
)

JUDGE = "J08_TOKENS_MESSAGES"
HEX = re.compile(r"#[0-9a-fA-F]{3,8}\b")
RGB = re.compile(r"\brgba?\s*\(")
SPACING = re.compile(r"\b\d+(?:\.\d+)?(?:px|rem|em)\b")


def run() -> int:
    started_at = utc_now()
    cli = parser(__doc__)
    add_common_input(cli, "Story Pack JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    cli.add_argument("--judge-version", required=True)
    cli.add_argument("--executor-identity", required=True)
    args = cli.parse_args()
    pack = require_object(load_json(args.input), "story_pack")
    section_raw = pack.get("tokens_messages")
    section = section_raw if isinstance(section_raw, dict) else {}
    tokens = [item for item in section.get("tokens", []) if isinstance(item, dict)]
    messages = [item for item in section.get("messages", []) if isinstance(item, dict)]
    interaction_blob = json.dumps(pack.get("interaction", {}), ensure_ascii=False)
    section_blob = json.dumps(section, ensure_ascii=False)
    blob = interaction_blob + section_blob

    colors = sorted(set(HEX.findall(blob) + RGB.findall(blob)))
    spacing = sorted(set(SPACING.findall(blob)))
    invalid_tokens = [
        item.get("token_code") for item in tokens
        if (item.get("registered") is False and item.get("status") != "CANDIDATO")
        or (item.get("registered") is True and item.get("status") != "REGISTERED")
    ]
    tokens_without_code = [
        f"tokens[{index}]" for index, item in enumerate(tokens) if not item.get("token_code")
    ]
    messages_without_code = [
        f"messages[{index}]" for index, item in enumerate(messages) if not item.get("message_code")
    ]
    no_severity = [item.get("message_code", "<missing>") for item in messages if not item.get("severity")]
    no_text_ref = [item.get("message_code", "<missing>") for item in messages if not item.get("text_ref")]
    duplicate_codes = duplicate_values(
        item.get("message_code") for item in messages if item.get("message_code")
    )
    duplicate_text_refs = duplicate_values(
        item.get("text_ref") for item in messages if item.get("text_ref")
    )

    checks = {
        "tokens_messages_section_missing": [] if isinstance(section_raw, dict) else ["tokens_messages"],
        "tokens_missing": [] if tokens else ["tokens"],
        "messages_missing": [] if messages else ["messages"],
        "tokens_without_code": tokens_without_code,
        "messages_without_code": messages_without_code,
        "hardcoded_color_count": colors,
        "hardcoded_spacing_count": spacing,
        "unregistered_component_tokens": invalid_tokens,
        "messages_without_severity": no_severity,
        "messages_without_text_ref": no_text_ref,
        "duplicate_message_codes": duplicate_codes,
    }
    failed = [f"{key}={len(values)}" for key, values in checks.items() if values]
    repairs = [
        failure(key, "tokens_messages", f"Repair findings: {values}")
        for key, values in checks.items() if values
    ]
    evidence = {
        "tokens_declared": len(tokens),
        "messages_declared": len(messages),
        "duplicate_text_refs": duplicate_text_refs,
        "checks": checks,
        "input_path": str(args.input),
    }
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"],
        repairs, retry_count=args.retry_count,
        judge_version=args.judge_version,
        executor_identity=args.executor_identity,
        started_at=started_at,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
