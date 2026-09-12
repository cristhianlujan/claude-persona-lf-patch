#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[3]
CURRENT_MARKETPLACE_CONTEXT = Path("cards/marketplace_lf/decision_product_experience/context_pack.md")
STALE_MARKETPLACE_CONTEXT = Path("profiles/shared_context/marketplace_context_pack.md")
PROFILE_SOURCES = {
    "product_director_lf": Path("profiles/product_director_lf/SKILL.md"),
    "ui_architect": Path("profiles/ui_architect/SKILL.md"),
    "quality_pack": Path("profiles/quality_pack/SKILL.md"),
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def measure(path: Path) -> dict[str, Any]:
    absolute = REPO / path
    data = absolute.read_bytes()
    text = data.decode("utf-8")
    return {
        "path": str(path),
        "bytes": len(data),
        "chars": len(text),
        "sha256": sha256_bytes(data),
        "token_proxy_chars_div_4": round(len(text) / 4, 2),
    }


def build_report() -> dict[str, Any]:
    current = measure(CURRENT_MARKETPLACE_CONTEXT)
    profiles: dict[str, Any] = {}
    for slug, path in PROFILE_SOURCES.items():
        profile = measure(path)
        profiles[slug] = {
            "profile": profile,
            "shared_context": current,
            "combined_source_chars": profile["chars"] + current["chars"],
            "combined_source_bytes": profile["bytes"] + current["bytes"],
            "combined_token_proxy_chars_div_4": round((profile["chars"] + current["chars"]) / 4, 2),
        }
    return {
        "schema": "lf-profile-runtime-context-budget/v1",
        "current_marketplace_context": current,
        "stale_marketplace_context_path": str(STALE_MARKETPLACE_CONTEXT),
        "stale_marketplace_context_exists": (REPO / STALE_MARKETPLACE_CONTEXT).exists(),
        "profiles": profiles,
        "token_proxy_warning": "chars/4 is a deterministic sizing proxy, not observed tokenizer usage",
    }


if __name__ == "__main__":
    print(json.dumps(build_report(), sort_keys=True, separators=(",", ":")))
