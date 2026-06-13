#!/usr/bin/env python3
"""Render and audit a PDF for visual QA.

Usage:
  python render_and_audit_pdf.py input.pdf output_dir

Checks are intentionally conservative. The script does not validate business content;
it creates page images and a JSON audit shell for human visual bug-hunt.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: render_and_audit_pdf.py input.pdf output_dir", file=sys.stderr)
        return 2

    pdf_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    if not pdf_path.exists():
        print(f"missing pdf: {pdf_path}", file=sys.stderr)
        return 1

    audit = {
        "pdf": str(pdf_path),
        "output_dir": str(out_dir),
        "rendered_pages": [],
        "manual_visual_qa_required": True,
        "required_bug_hunt": [
            "margins",
            "hierarchy",
            "density",
            "contrast",
            "overflow",
            "overlap",
            "tables",
            "flow_legibility",
            "footer_collision",
        ],
        "verdict_rule": "Do not pass without screenshots and issue list.",
    }

    try:
        import fitz  # PyMuPDF
    except Exception as exc:
        audit["render_error"] = f"PyMuPDF unavailable: {exc}"
        (out_dir / "audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
        return 0

    doc = fitz.open(pdf_path)
    for idx, page in enumerate(doc, start=1):
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        image_path = out_dir / f"page_{idx:02d}.png"
        pix.save(image_path)
        audit["rendered_pages"].append(str(image_path))

    audit["page_count"] = len(doc)
    (out_dir / "audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
