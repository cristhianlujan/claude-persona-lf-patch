#!/usr/bin/env python3
"""Isolated diagnostic: quantify human-observation reduction on the governed real screen.

This script is execution-only. It does not promote PaddleOCR, does not grant
real-corpus/P0-5 credit, and does not authorize production. It measures two
separate effects against the current source-bound review surface:

1. OCR disagreement emitted for elements already classified ICON_OR_GLYPH;
2. selective PaddleOCR PP-OCRv5 targeted-crop resolution on remaining text
   disagreements/grouping disagreements under conservative machine-checkable
   rules.

Cross-engine confidence values are recorded but never used to choose a winner.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SOURCE_SHA256 = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES = 1_384_686
SOURCE_EVIDENCE_OBJECT_ID = "be7fcf20-5f83-46d4-be0e-c80dc3ceed7c"
SOURCE_REVIEW_ID = "P0-HUMAN-REVIEW-B6D53598C062-20260814151954"
SOURCE_VISUAL_OBJECT_ID = "e63fd032-b625-4929-9adf-61b5058494f3"
EXEC_REF = "refs/heads/lf/p0-ocr-observation-reduction-exec"

BASELINE_UNCERTAINTY_COUNT = 30
ICON_FUNCTION_NOT_OBSERVABLE = 18
NON_TEXT_OCR_DISAGREEMENTS = 4
TEXT_OCR_DISAGREEMENTS = 6
TEXT_GROUPING_DISAGREEMENTS = 2

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

# Exact source-bound items from the durable visual-output object. These are not
# human adjudications. Bboxes/text/codes are copied from the persisted review
# surface solely to measure whether the candidate can safely remove uncertainty.
TARGETS = [
    {
        "element_id": "V4-T-0022",
        "kind": "document_placeholder",
        "bbox": [1093, 463, 85, 13],
        "baseline": "55 12345678",
        "codes": ["OCR_DISAGREEMENT"],
    },
    {
        "element_id": "V4-T-0028",
        "kind": "phone_bundle",
        "bbox": [626, 565, 221, 21],
        "baseline": "OD +5s1v 8j.987654321",
        "codes": ["OCR_DISAGREEMENT", "TEXT_GROUPING_DISAGREEMENT"],
    },
    {
        "element_id": "V4-T-0029",
        "kind": "email_placeholder",
        "bbox": [1046, 568, 196, 16],
        "baseline": "E Ej miguelecorreo.com",
        "codes": ["OCR_DISAGREEMENT"],
    },
    {
        "element_id": "V4-T-0037",
        "kind": "exact_text",
        "bbox": [661, 695, 458, 13],
        "baseline": "Autorizo el tratamiento de mis datos personales para validar mi identidad,",
        "codes": ["OCR_DISAGREEMENT"],
    },
    {
        "element_id": "V4-T-0039",
        "kind": "exact_text",
        "bbox": [661, 717, 430, 14],
        "baseline": "consultar información relacionada con mis obligaciones y mostrarme",
        "codes": ["OCR_DISAGREEMENT"],
    },
    {
        "element_id": "V4-T-0047",
        "kind": "button_text",
        "bbox": [926, 887, 166, 15],
        "baseline": "Verificar mi celular",
        "codes": ["OCR_DISAGREEMENT", "TEXT_GROUPING_DISAGREEMENT"],
    },
]

NON_TEXT_TARGETS = [
    {"element_id": "V4-T-0030", "bbox": [1046, 568, 21, 16], "element_type": "ICON_OR_GLYPH"},
    {"element_id": "V4-T-0040", "bbox": [467, 723, 23, 28], "element_type": "ICON_OR_GLYPH"},
    {"element_id": "V4-T-0043", "bbox": [437, 784, 15, 9], "element_type": "ICON_OR_GLYPH"},
    {"element_id": "V4-T-0046", "bbox": [116, 847, 38, 1], "element_type": "ICON_OR_GLYPH"},
]


def norm(value: str) -> str:
    return " ".join((value or "").casefold().split())


def _strip_example_prefix(value: str) -> str:
    text = (value or "").strip()
    return re.sub(r"^ej\.?\s*", "", text, flags=re.IGNORECASE)


def _document_valid(value: str) -> bool:
    text = _strip_example_prefix(value)
    if re.search(r"[A-Za-zÁÉÍÓÚáéíóúÑñ]", text):
        return False
    digits = "".join(ch for ch in text if ch.isdigit())
    return len(digits) == 8


def _phone_valid(value: str) -> bool:
    text = _strip_example_prefix(value)
    if re.search(r"[A-IK-ZA-ik-zÁÉÍÓÚáéíóúÑñ]", text):
        return False
    digits = "".join(ch for ch in text if ch.isdigit())
    return len(digits) == 9


def _email_valid(value: str) -> bool:
    candidate = _strip_example_prefix(value)
    return bool(EMAIL_RE.fullmatch(candidate))


def _phone_bundle_valid(texts: list[str]) -> tuple[bool, bool]:
    cleaned = [item.strip() for item in texts if item.strip()]
    prefix_indices = [i for i, value in enumerate(cleaned) if "+51" in value.replace(" ", "")]
    phone_indices = [i for i, value in enumerate(cleaned) if _phone_valid(value)]
    valid = bool(prefix_indices and phone_indices)
    separately_detected = any(left != right for left in prefix_indices for right in phone_indices)
    return valid, separately_detected


def _ensure_paddle() -> None:
    try:
        import paddle  # noqa:F401
        import paddleocr  # noqa:F401
        return
    except Exception:
        pass
    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "-q",
            "paddlepaddle==3.2.0",
            "-i",
            "https://www.paddlepaddle.org.cn/packages/stable/cpu/",
        ],
        check=True,
    )
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "-q", "paddleocr==3.5.0"],
        check=True,
    )


def _fetch_source() -> bytes:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import p0_exact_head_real_source_ci_v1 as legacy
    import p0_exact_head_real_source_ci_v2 as v2

    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        raise SystemExit("FAIL_OBSERVATION_REDUCTION_EVENT_NOT_PUSH")
    if os.environ.get("GITHUB_REF") != EXEC_REF:
        raise SystemExit(f"FAIL_OBSERVATION_REDUCTION_EXEC_REF:{os.environ.get('GITHUB_REF')}")
    config = v2.load_config()
    legacy.BROKER_URL = config["broker_url"]
    identity = {
        "repository": os.environ["GITHUB_REPOSITORY"],
        "ref": os.environ["GITHUB_REF"],
        "github_sha": os.environ["GITHUB_SHA"],
        "run_id": int(os.environ["GITHUB_RUN_ID"]),
        "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "event_name": os.environ["GITHUB_EVENT_NAME"],
        "action": "get_source",
    }
    delivered = legacy.broker(os.environ["GITHUB_TOKEN"], identity)
    if delivered.get("outcome") != "SOURCE_DELIVERED_TO_EXACT_GITHUB_RUN":
        raise SystemExit(f"FAIL_OBSERVATION_REDUCTION_SOURCE:{delivered}")
    source_info = delivered.get("source") or {}
    if source_info.get("evidence_object_id") != SOURCE_EVIDENCE_OBJECT_ID:
        raise SystemExit("FAIL_OBSERVATION_REDUCTION_SOURCE_OBJECT")
    raw = base64.b64decode(source_info["content_base64"])
    if len(raw) != SOURCE_BYTES or hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise SystemExit("FAIL_OBSERVATION_REDUCTION_SOURCE_INTEGRITY")
    return raw


def _make_ocr():
    _ensure_paddle()
    import paddle
    import paddleocr
    from paddleocr import PaddleOCR

    started = time.time()
    ocr = PaddleOCR(
        lang="es",
        ocr_version="PP-OCRv5",
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        device="cpu",
    )
    return ocr, {
        "paddle_version": paddle.__version__,
        "paddleocr_version": paddleocr.__version__,
        "init_seconds": round(time.time() - started, 4),
    }


def _predict(ocr, path: Path) -> dict:
    started = time.time()
    results = list(ocr.predict(str(path)))
    boxes: list[dict] = []
    for result in results:
        payload = result.json
        payload = payload.get("res", payload)
        texts = list(payload.get("rec_texts") or [])
        scores = list(payload.get("rec_scores") or [])
        rec_boxes = list(payload.get("rec_boxes") or [])
        for text, score, box in zip(texts, scores, rec_boxes):
            x1, y1, x2, y2 = [int(v) for v in box]
            boxes.append(
                {
                    "text": str(text).strip(),
                    "confidence": round(float(score), 6),
                    "bbox": [x1, y1, max(0, x2 - x1), max(0, y2 - y1)],
                }
            )
    boxes = [box for box in boxes if box["text"]]
    boxes.sort(key=lambda box: (box["bbox"][1], box["bbox"][0]))
    return {
        "boxes": boxes,
        "texts": [box["text"] for box in boxes],
        "joined": " ".join(box["text"] for box in boxes).strip(),
        "latency_seconds": round(time.time() - started, 4),
    }


def _crop(source, bbox: list[int], *, padding: int = 10, scale: int = 4):
    from PIL import Image

    x, y, width, height = bbox
    x0 = max(0, x - padding)
    y0 = max(0, y - padding)
    x1 = min(source.width, x + width + padding)
    y1 = min(source.height, y + height + padding)
    crop = source.crop((x0, y0, x1, y1)).convert("RGB")
    return crop.resize((max(1, crop.width * scale), max(1, crop.height * scale)), Image.Resampling.LANCZOS)


def _stable_prediction(ocr, source, bbox: list[int], temp_root: Path, name: str) -> dict:
    crop = _crop(source, bbox)
    path = temp_root / f"{name}.png"
    crop.save(path)
    runs = [_predict(ocr, path) for _ in range(3)]
    signatures = [(norm(run["joined"]), tuple(norm(text) for text in run["texts"])) for run in runs]
    stable = len(set(signatures)) == 1
    return {
        "stable": stable,
        "runs": runs,
        "joined": runs[0]["joined"] if stable else "",
        "texts": runs[0]["texts"] if stable else [],
        "box_count": len(runs[0]["boxes"]) if stable else 0,
        "median_latency_seconds": sorted(run["latency_seconds"] for run in runs)[1],
    }


def _evaluate(target: dict, prediction: dict) -> dict:
    stable = bool(prediction["stable"])
    joined = prediction["joined"] if stable else ""
    texts = prediction["texts"] if stable else []
    baseline = target["baseline"]
    kind = target["kind"]
    resolved_codes: list[str] = []
    reasons: list[str] = []

    if not stable:
        reasons.append("PADDLE_UNSTABLE_ACROSS_3_RUNS")
    elif kind == "document_placeholder":
        if _document_valid(joined) and not _document_valid(baseline):
            resolved_codes.append("OCR_DISAGREEMENT")
            reasons.append("STRUCTURAL_DOCUMENT_CORRECTION")
    elif kind == "phone_bundle":
        valid, separate = _phone_bundle_valid(texts)
        baseline_valid, _ = _phone_bundle_valid([baseline])
        if valid and not baseline_valid:
            resolved_codes.append("OCR_DISAGREEMENT")
            reasons.append("STRUCTURAL_PHONE_BUNDLE_CORRECTION")
        if valid and separate:
            resolved_codes.append("TEXT_GROUPING_DISAGREEMENT")
            reasons.append("INDEPENDENT_GROUPING_CORROBORATION")
    elif kind == "email_placeholder":
        candidate = next((text for text in texts if "@" in text), joined)
        if _email_valid(candidate) and not _email_valid(baseline):
            resolved_codes.append("OCR_DISAGREEMENT")
            reasons.append("STRUCTURAL_EMAIL_CORRECTION")
    elif kind == "exact_text":
        if norm(joined) == norm(baseline):
            resolved_codes.append("OCR_DISAGREEMENT")
            reasons.append("EXACT_CROSS_FAMILY_AGREEMENT")
    elif kind == "button_text":
        if norm(joined) == norm(baseline):
            resolved_codes.append("OCR_DISAGREEMENT")
            reasons.append("EXACT_CROSS_FAMILY_AGREEMENT")
            if prediction["box_count"] == 1:
                resolved_codes.append("TEXT_GROUPING_DISAGREEMENT")
                reasons.append("INDEPENDENT_SINGLE_LINE_GROUPING_CORROBORATION")

    resolved_codes = [code for code in target["codes"] if code in set(resolved_codes)]
    unresolved_codes = [code for code in target["codes"] if code not in set(resolved_codes)]
    return {
        "element_id": target["element_id"],
        "kind": kind,
        "bbox": target["bbox"],
        "baseline": baseline,
        "baseline_uncertainty_codes": target["codes"],
        "paddle": prediction,
        "resolved_codes": resolved_codes,
        "unresolved_codes": unresolved_codes,
        "reasons": reasons,
    }


def main() -> int:
    raw = _fetch_source()
    from PIL import Image

    with tempfile.TemporaryDirectory(prefix="lf-ocr-observation-reduction-") as temp_dir:
        root = Path(temp_dir)
        source_path = root / "source.png"
        source_path.write_bytes(raw)
        source = Image.open(source_path).convert("RGB")
        ocr, engine_meta = _make_ocr()

        evaluated = []
        for target in TARGETS:
            prediction = _stable_prediction(ocr, source, target["bbox"], root, target["element_id"])
            evaluated.append(_evaluate(target, prediction))

        non_text_probe = []
        for target in NON_TEXT_TARGETS:
            prediction = _stable_prediction(ocr, source, target["bbox"], root, target["element_id"])
            non_text_probe.append({**target, "paddle": prediction})

        paddle_resolved = sum(len(item["resolved_codes"]) for item in evaluated)
        candidate_resolved = NON_TEXT_OCR_DISAGREEMENTS + paddle_resolved
        projected_residual = BASELINE_UNCERTAINTY_COUNT - candidate_resolved
        reduction_pct = round(100.0 * candidate_resolved / BASELINE_UNCERTAINTY_COUNT, 2)
        residual_pct = round(100.0 * projected_residual / BASELINE_UNCERTAINTY_COUNT, 2)
        text_scope_total = TEXT_OCR_DISAGREEMENTS + TEXT_GROUPING_DISAGREEMENTS
        paddle_text_scope_pct = round(100.0 * paddle_resolved / text_scope_total, 2)

        result = {
            "schema_version": "p0-ocr-observation-reduction-diagnostic/v1",
            "github_sha": os.environ.get("GITHUB_SHA"),
            "source_sha256": SOURCE_SHA256,
            "source_evidence_object_id": SOURCE_EVIDENCE_OBJECT_ID,
            "source_review_id": SOURCE_REVIEW_ID,
            "source_visual_output_object_id": SOURCE_VISUAL_OBJECT_ID,
            "reference_class": "SOURCE_BOUND_DIAGNOSTIC_NOT_HUMAN_ADJUDICATION",
            "baseline": {
                "uncertainty_count": BASELINE_UNCERTAINTY_COUNT,
                "icon_function_not_observable": ICON_FUNCTION_NOT_OBSERVABLE,
                "ocr_disagreement_total": NON_TEXT_OCR_DISAGREEMENTS + TEXT_OCR_DISAGREEMENTS,
                "ocr_disagreement_on_icon_or_glyph": NON_TEXT_OCR_DISAGREEMENTS,
                "ocr_disagreement_on_text": TEXT_OCR_DISAGREEMENTS,
                "text_grouping_disagreement": TEXT_GROUPING_DISAGREEMENTS,
            },
            "engine": {"family": "PADDLEOCR", "ocr_version": "PP-OCRv5", "lang": "es", **engine_meta},
            "text_targets": evaluated,
            "non_text_probes": non_text_probe,
            "summary": {
                "invariant_nontext_ocr_resolved": NON_TEXT_OCR_DISAGREEMENTS,
                "paddle_text_scope_observations": text_scope_total,
                "paddle_text_scope_resolved": paddle_resolved,
                "paddle_text_scope_resolution_pct": paddle_text_scope_pct,
                "total_candidate_observations_resolved": candidate_resolved,
                "projected_residual_uncertainties": projected_residual,
                "total_uncertainty_reduction_pct": reduction_pct,
                "residual_uncertainty_pct": residual_pct,
                "theoretical_ocr_floor": ICON_FUNCTION_NOT_OBSERVABLE,
                "theoretical_max_ocr_reduction_pct": round(100.0 * (BASELINE_UNCERTAINTY_COUNT - ICON_FUNCTION_NOT_OBSERVABLE) / BASELINE_UNCERTAINTY_COUNT, 2),
            },
            "real_corpus_credit": 0,
            "p0_5_credit": 0,
            "holdout_accessed": False,
            "runtime_promoted": False,
            "production_authorized": False,
            "model_source_pinning_complete": False,
        }

        output = Path(".audit-output/creating-integral-user-stories/p0-ocr-observation-reduction-result.json")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print("OCR_OBSERVATION_REDUCTION_RESULT=" + json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        print(f"BASELINE_UNCERTAINTIES={BASELINE_UNCERTAINTY_COUNT}")
        print(f"INVARIANT_NON_TEXT_OCR_RESOLVED={NON_TEXT_OCR_DISAGREEMENTS}")
        print(f"PADDLE_TEXT_SCOPE_RESOLVED={paddle_resolved}/{text_scope_total}")
        print(f"PROJECTED_RESIDUAL_UNCERTAINTIES={projected_residual}")
        print(f"TOTAL_UNCERTAINTY_REDUCTION_PCT={reduction_pct}")
        print("REAL_CORPUS_CREDIT=0")
        print("P0_5_CREDIT=0")
        print("RUNTIME_PROMOTED=false")
        print("PRODUCTION_AUTHORIZED=false")
        print("PASS_P0_OCR_OBSERVATION_REDUCTION_DIAGNOSTIC=1/1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
