#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import human_review_packet
from p0_human_review_shell_v4 import (
    build_human_review_shell_from_rerun_receipt_v4,
    build_human_review_shell_v4,
    validate_human_review_shell_v4,
)


def load_json(path: str | None, default=None):
    if not path:
        return default
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    p = argparse.ArgumentParser()
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--rerun-receipt", help="Fresh P0 V4 real-source rerun receipt JSON")
    mode.add_argument("--candidate", help="Legacy V3 candidate JSON")
    p.add_argument("--report", help="Required with --candidate")
    p.add_argument("--reconciliation")
    p.add_argument("--remediation-history")
    p.add_argument("--image", required=True)
    p.add_argument("--challenge")
    p.add_argument("--screen-name", default="01_onboarding paso 1.png")
    p.add_argument("--packet-output")
    p.add_argument("--html-output", required=True)
    a = p.parse_args()

    challenge = load_json(a.challenge)
    image = Path(a.image)
    if a.rerun_receipt:
        receipt = load_json(a.rerun_receipt)
        doc = build_human_review_shell_from_rerun_receipt_v4(
            receipt, image, challenge, screen_name=a.screen_name
        )
        if a.packet_output:
            Path(a.packet_output).write_text(
                json.dumps(receipt.get("human_review_packet", {}), ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        human_ready = bool((receipt.get("result") or {}).get("human_review_ready"))
        exceptions = 0
        mode_name = "REAL_RERUN_RECEIPT_V4"
    else:
        if not a.report:
            raise SystemExit("--report is required with --candidate")
        c = load_json(a.candidate)
        r = load_json(a.report)
        rec = load_json(a.reconciliation)
        hist = load_json(a.remediation_history, [])
        packet = human_review_packet(c, r, rec, hist)
        if a.packet_output:
            Path(a.packet_output).write_text(
                json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
        doc = build_human_review_shell_v4(packet, c, image, challenge)
        human_ready = bool(packet.get("human_review_ready"))
        exceptions = len(packet.get("human_attention_required", []))
        mode_name = "LEGACY_V3_PACKET"

    validation = validate_human_review_shell_v4(doc)
    Path(a.html_output).write_text(doc, encoding="utf-8")
    print(
        json.dumps(
            {
                "mode": mode_name,
                "human_review_ready": human_ready,
                "human_exceptions": exceptions,
                "responsive_shell_v4": validation["pass"],
                "missing_markers": validation["missing"],
                "forbidden": validation["forbidden"],
            },
            ensure_ascii=False,
        )
    )
    return 0 if validation["pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
