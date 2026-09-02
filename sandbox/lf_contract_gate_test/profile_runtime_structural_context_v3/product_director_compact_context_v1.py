#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[3]
PROFILE_PATH = Path("profiles/product_director_lf/SKILL.md")
CONTEXT_PATH = Path("cards/marketplace_lf/decision_product_experience/context_pack.md")
KEEP_SECTIONS = (
    "RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES",
    "Purpose",
    "Required inputs",
    "Context-resolution and materiality ladder",
    "Required output modes",
    "Mandatory decision trajectory",
    "Scoring",
    "Automatic block / needs-input",
    "Compact handoff rule",
    "Handoff",
)
REQUIRED_AUTHORITY_MARKERS = (
    "AUTHORITY RESOLUTION FIRST",
    "MATERIALITY BEFORE BLOCKING",
    "NO INVENTED BUSINESS TRUTH",
    "SELF-REPAIR ONCE BEFORE OUTPUT",
    "authority_resolved=true",
    "PRODUCT_DIRECTION_SPEC",
    "PRODUCT_MISSING_INPUT_STATE",
    "BLOCKED_PRODUCT_RISK",
    "source_refs[]",
    "qualifiers_to_preserve",
    "PROPOSED_NOT_CANONICAL",
    "RETURN_TO_ORCHESTRATOR",
    "score.evidence_by_criterion",
    "never invented business truth",
)


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def split_sections(markdown: str) -> dict[str, str]:
    matches = list(re.finditer(r"^## (.+?)\s*$", markdown, flags=re.MULTILINE))
    out: dict[str, str] = {}
    for index, match in enumerate(matches):
        title = match.group(1)
        end = matches[index + 1].start() if index + 1 < len(matches) else len(markdown)
        out[title] = markdown[match.start():end].strip() + "\n"
    return out


def build_candidate() -> dict[str, Any]:
    profile = (REPO / PROFILE_PATH).read_text(encoding="utf-8")
    shared = (REPO / CONTEXT_PATH).read_text(encoding="utf-8")
    sections = split_sections(profile)
    missing_sections = [title for title in KEEP_SECTIONS if title not in sections]
    if missing_sections:
        raise RuntimeError(f"COMPACT_CONTEXT_SECTION_MISSING:{','.join(missing_sections)}")
    compact_profile = "\n".join(sections[title].rstrip() for title in KEEP_SECTIONS).strip() + "\n"
    missing_markers = [marker for marker in REQUIRED_AUTHORITY_MARKERS if marker not in compact_profile]
    if missing_markers:
        raise RuntimeError(f"COMPACT_CONTEXT_AUTHORITY_MARKER_MISSING:{','.join(missing_markers)}")
    original_chars = len(profile) + len(shared)
    candidate_chars = len(compact_profile) + len(shared)
    return {
        "schema": "lf-product-director-compact-context/v1",
        "profile_path": str(PROFILE_PATH),
        "shared_context_path": str(CONTEXT_PATH),
        "kept_sections": list(KEEP_SECTIONS),
        "required_authority_markers": list(REQUIRED_AUTHORITY_MARKERS),
        "profile_original_sha256": _sha(profile),
        "profile_compact_sha256": _sha(compact_profile),
        "shared_context_sha256": _sha(shared),
        "original_source_chars": original_chars,
        "candidate_source_chars": candidate_chars,
        "reduction_chars": original_chars - candidate_chars,
        "reduction_pct": round((original_chars - candidate_chars) * 100 / original_chars, 2),
        "original_token_proxy_chars_div_4": round(original_chars / 4, 2),
        "candidate_token_proxy_chars_div_4": round(candidate_chars / 4, 2),
        "requirement_retention": "PASS_MARKER_AND_SECTION_BOUND",
        "authority_retention": "PASS_MARKER_AND_SECTION_BOUND",
        "activation_status": "CANDIDATE_NOT_ACTIVE",
        "compact_profile": compact_profile,
    }


if __name__ == "__main__":
    report = build_candidate()
    printable = {key: value for key, value in report.items() if key != "compact_profile"}
    print(json.dumps(printable, sort_keys=True, separators=(",", ":")))
