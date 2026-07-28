"""Detect hardcoded visual values instead of registered tokens. J08 support."""
import re
import sys

from lf_common import argv_path, emit, load

HEX = re.compile(r"#[0-9a-fA-F]{3,8}\b")
RGB = re.compile(r"rgba?\s*\(")
SPACING = re.compile(r"\b\d+(px|rem|em)\b")


def main():
    pack = load(argv_path(1))
    blob = str(pack.get("tokens_messages", {})) + str(pack.get("interaction", {}))
    colors = HEX.findall(blob) + RGB.findall(blob)
    spacing = SPACING.findall(blob)
    tokens = pack.get("tokens_messages", {}).get("tokens", [])
    unregistered = [t.get("token_code") for t in tokens if not t.get("registered")
                    and t.get("status") != "CANDIDATO"]
    messages = pack.get("tokens_messages", {}).get("messages", [])
    no_severity = [m.get("message_code") for m in messages if not m.get("severity")]
    seen, duplicates = {}, []
    for m in messages:
        text = m.get("text")
        if text and text in seen:
            duplicates.append(text)
        seen[text] = True
    failed = []
    if colors:
        failed.append("hardcoded_color_count=%d" % len(colors))
    if spacing:
        failed.append("hardcoded_spacing_count=%d" % len(spacing))
    if unregistered:
        failed.append("unregistered_component_tokens=%d" % len(unregistered))
    if no_severity:
        failed.append("messages_without_severity=%d" % len(no_severity))
    if duplicates:
        failed.append("duplicate_message_text_without_token=%d" % len(duplicates))
    evidence = {
        "tokens_declared": len(tokens),
        "messages_declared": len(messages),
        "hardcoded_colors": colors,
        "hardcoded_spacing": spacing,
    }
    return emit("J08_TOKENS_MESSAGES", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
