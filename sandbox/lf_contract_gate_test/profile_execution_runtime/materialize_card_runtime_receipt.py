#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable

REQUIRED_FIELDS = (
    "request_id",
    "card_ref",
    "card_version_or_hash",
    "sections_consumed",
    "budget",
    "decision",
)


def _sections(markdown: str) -> list[str]:
    return [line[3:].strip() for line in markdown.splitlines() if line.startswith("## ")]


def materialize_card_receipt(
    *,
    request_id: str,
    card_path: str,
    selected_sections: Iterable[str],
    budget: int,
) -> dict[str, object]:
    if not request_id.strip():
        raise ValueError("CARD_RECEIPT_REQUEST_ID_REQUIRED")
    if budget <= 0:
        raise ValueError("CARD_RECEIPT_BUDGET_MUST_BE_POSITIVE")

    path = Path(card_path)
    if not path.is_file():
        raise ValueError("CARD_RECEIPT_SOURCE_NOT_FOUND")

    raw = path.read_bytes()
    markdown = raw.decode("utf-8")
    available = set(_sections(markdown))
    selected = [section.strip() for section in selected_sections if section.strip()]
    if not selected:
        raise ValueError("CARD_RECEIPT_SELECTED_SECTIONS_REQUIRED")
    missing = sorted(set(selected) - available)
    if missing:
        raise ValueError(f"CARD_RECEIPT_UNKNOWN_SECTION:{','.join(missing)}")

    digest = hashlib.sha256(raw).hexdigest()
    receipt: dict[str, object] = {
        "request_id": request_id,
        "card_ref": card_path,
        "card_version_or_hash": f"sha256:{digest}",
        "sections_consumed": selected,
        "budget": budget,
        "decision": "MATERIALIZED_READ_ONLY",
    }
    assert all(field in receipt for field in REQUIRED_FIELDS)
    return receipt


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--card-path", required=True)
    parser.add_argument("--section", action="append", dest="sections", required=True)
    parser.add_argument("--budget", type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(materialize_card_receipt(
        request_id=args.request_id,
        card_path=args.card_path,
        selected_sections=args.sections,
        budget=args.budget,
    ), sort_keys=True))


if __name__ == "__main__":
    main()
