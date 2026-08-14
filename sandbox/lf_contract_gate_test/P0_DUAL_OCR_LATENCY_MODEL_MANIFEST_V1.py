#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import statistics
import tempfile
import time
from pathlib import Path

from PIL import Image

import P0_DUAL_OCR_MICROBENCHMARK_EXEC_V1 as base

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / ".audit-output" / "creating-integral-user-stories" / "p0-dual-ocr-latency-model-manifest.json"
EMAIL_CROP = (1035, 535, 1370, 610)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def texts_from_result(results) -> list[str]:
    texts: list[str] = []
    for res in results:
        payload = res.json
        payload = payload.get("res", payload)
        texts.extend(str(x) for x in (payload.get("rec_texts") or []))
    return texts


def timed_predict(ocr, path: str) -> tuple[float, list[str]]:
    started = time.perf_counter()
    results = list(ocr.predict(path))
    return time.perf_counter() - started, texts_from_result(results)


def main() -> int:
    raw = base._fetch_source()
    base._ensure_paddle()
    import paddle
    import paddleocr
    from paddleocr import PaddleOCR

    with tempfile.TemporaryDirectory(prefix="lf-p0-dual-latency-") as td:
        source = Path(td) / "source.png"
        source.write_bytes(raw)
        crop = Path(td) / "email-crop.png"
        image = Image.open(source)
        image.crop(EMAIL_CROP).save(crop)

        before = time.perf_counter()
        ocr = PaddleOCR(
            lang="es",
            ocr_version="PP-OCRv5",
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
            device="cpu",
        )
        init_seconds = time.perf_counter() - before

        full_times: list[float] = []
        full_texts: list[list[str]] = []
        for _ in range(2):
            elapsed, texts = timed_predict(ocr, str(source))
            full_times.append(elapsed)
            full_texts.append(texts)

        crop_times: list[float] = []
        crop_texts: list[list[str]] = []
        for _ in range(5):
            elapsed, texts = timed_predict(ocr, str(crop))
            crop_times.append(elapsed)
            crop_texts.append(texts)

        models_root = Path.home() / ".paddlex" / "official_models"
        files = []
        if models_root.is_dir():
            for path in sorted(p for p in models_root.rglob("*") if p.is_file()):
                files.append({
                    "path": str(path.relative_to(models_root)),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                })
        model_dirs = sorted({entry["path"].split("/", 1)[0] for entry in files})
        manifest_digest = hashlib.sha256(
            json.dumps(files, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

        payload = {
            "schema_version": "p0-dual-ocr-latency-model-manifest/v1",
            "github_sha": os.environ.get("GITHUB_SHA"),
            "source_sha256": base.SOURCE_SHA256,
            "engine": {
                "family": "PADDLEOCR",
                "ocr_version": "PP-OCRv5",
                "paddle_version": paddle.__version__,
                "paddleocr_version": paddleocr.__version__,
                "lang": "es",
                "device": "cpu",
            },
            "latency": {
                "init_seconds": round(init_seconds, 4),
                "full_screen_seconds": [round(x, 4) for x in full_times],
                "full_screen_warm_median_seconds": round(statistics.median(full_times), 4),
                "email_crop_seconds": [round(x, 4) for x in crop_times],
                "email_crop_warm_median_seconds": round(statistics.median(crop_times), 4),
                "crop_vs_full_ratio": round(statistics.median(crop_times) / max(statistics.median(full_times), 1e-9), 4),
            },
            "email_crop_bbox": list(EMAIL_CROP),
            "email_crop_outputs": crop_texts,
            "full_screen_output_counts": [len(x) for x in full_texts],
            "model_manifest": {
                "root": "~/.paddlex/official_models",
                "directories": model_dirs,
                "file_count": len(files),
                "total_bytes": sum(x["bytes"] for x in files),
                "files": files,
                "manifest_sha256": manifest_digest,
            },
            "governance": {
                "model_hashes_captured": bool(files),
                "model_source_pinning_complete": False,
                "runtime_promoted": False,
                "production_authorized": False,
                "holdout_accessed": False,
                "real_corpus_credit": 0,
                "p0_5_credit": 0,
            },
        }
        normalized_crop = [base.norm(t) for batch in crop_texts for t in batch]
        if not any("miguel@correo.com" in t for t in normalized_crop):
            raise SystemExit("FAIL_DUAL_OCR_CROP_DID_NOT_RECOVER_EMAIL")
        if not files:
            raise SystemExit("FAIL_DUAL_OCR_MODEL_MANIFEST_EMPTY")
        if payload["governance"]["runtime_promoted"] or payload["governance"]["holdout_accessed"]:
            raise SystemExit("FAIL_DUAL_OCR_GOVERNANCE")

        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print("DUAL_OCR_LATENCY_RESULT=" + json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        print(f"PASS_DUAL_OCR_LATENCY_MODEL_MANIFEST=1/1 output={OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
