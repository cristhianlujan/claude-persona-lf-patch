#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from difflib import SequenceMatcher
from pathlib import Path

SOURCE_SHA256 = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES = 1_384_686
SOURCE_EVIDENCE_OBJECT_ID = "be7fcf20-5f83-46d4-be0e-c80dc3ceed7c"
EXEC_REF = "refs/heads/lf/p0-dual-ocr-microbenchmark-exec"

# Technical reference slices for this experiment only. They are NOT human-adjudicated
# ground truth and grant zero real-corpus or P0-5 credit.
SLICES = [
    {"id":"name_placeholder","kind":"text","bbox":[645,345,310,40],"expected":"Ej. Miguel Pérez García"},
    {"id":"document_number","kind":"number","bbox":[1075,448,225,42],"expected":"Ej. 12345678"},
    {"id":"phone_prefix","kind":"phone_prefix","bbox":[660,555,80,38],"expected":"+51"},
    {"id":"phone_placeholder","kind":"phone","bbox":[735,555,210,40],"expected":"Ej. 987 654 321"},
    {"id":"email_label","kind":"text","bbox":[1025,518,190,34],"expected":"Correo electrónico"},
    {"id":"email_placeholder","kind":"email","bbox":[1075,555,265,42],"expected":"Ej. miguel@correo.com"},
    {"id":"privacy_link","kind":"text","bbox":[780,635,345,35],"expected":"Términos y Condiciones y la Política de Privacidad."},
    {"id":"small_footer","kind":"small_text","bbox":[630,930,690,34],"expected":"Tus datos se utilizan únicamente para verificar tu identidad y mostrarte alternativas disponibles."},
]


def norm(s: str) -> str:
    return " ".join((s or "").casefold().split())


def sim(a: str, b: str) -> float:
    return SequenceMatcher(None, norm(a), norm(b)).ratio()


def bbox_intersection_fraction(a, b) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x1, y1 = max(ax,bx), max(ay,by)
    x2, y2 = min(ax+aw,bx+bw), min(ay+ah,by+bh)
    inter = max(0,x2-x1)*max(0,y2-y1)
    return inter / max(1, aw*ah)


def _ensure_paddle() -> None:
    try:
        import paddle  # noqa:F401
        import paddleocr  # noqa:F401
        return
    except Exception:
        pass
    subprocess.run([
        sys.executable,"-m","pip","install","--disable-pip-version-check","-q",
        "paddlepaddle==3.2.0","-i","https://www.paddlepaddle.org.cn/packages/stable/cpu/"
    ], check=True)
    subprocess.run([
        sys.executable,"-m","pip","install","--disable-pip-version-check","-q","paddleocr==3.5.0"
    ], check=True)


def _fetch_source() -> bytes:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import p0_exact_head_real_source_ci_v1 as legacy
    import p0_exact_head_real_source_ci_v2 as v2
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        raise SystemExit("FAIL_DUAL_OCR_EVENT_NOT_PUSH")
    if os.environ.get("GITHUB_REF") != EXEC_REF:
        raise SystemExit(f"FAIL_DUAL_OCR_EXEC_REF:{os.environ.get('GITHUB_REF')}")
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
        raise SystemExit(f"FAIL_DUAL_OCR_SOURCE:{delivered}")
    src = delivered.get("source") or {}
    if src.get("evidence_object_id") != SOURCE_EVIDENCE_OBJECT_ID:
        raise SystemExit("FAIL_DUAL_OCR_SOURCE_OBJECT")
    raw = base64.b64decode(src["content_base64"])
    if len(raw) != SOURCE_BYTES or hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise SystemExit("FAIL_DUAL_OCR_SOURCE_INTEGRITY")
    return raw


def _tesseract(path: str) -> list[dict]:
    from PIL import Image
    import pytesseract
    from pytesseract import Output
    image = Image.open(path)
    data = pytesseract.image_to_data(image, lang="spa", config="--psm 11", output_type=Output.DICT)
    out=[]
    for i,t in enumerate(data["text"]):
        text=(t or "").strip()
        if not text: continue
        try: conf=float(data["conf"][i])
        except Exception: conf=-1
        if conf < 0: continue
        out.append({"text":text,"confidence":conf/100.0,"bbox":[int(data["left"][i]),int(data["top"][i]),int(data["width"][i]),int(data["height"][i])]})
    return out


def _paddle(path: str) -> tuple[list[dict],dict]:
    _ensure_paddle()
    import paddle, paddleocr
    from paddleocr import PaddleOCR
    started=time.time()
    ocr=PaddleOCR(
        lang="es",
        ocr_version="PP-OCRv5",
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        device="cpu",
    )
    results=list(ocr.predict(path))
    out=[]
    for res in results:
        payload=res.json
        payload=payload.get("res", payload)
        texts=list(payload.get("rec_texts") or [])
        scores=list(payload.get("rec_scores") or [])
        boxes=list(payload.get("rec_boxes") or [])
        for text,score,box in zip(texts,scores,boxes):
            x1,y1,x2,y2=[int(v) for v in box]
            out.append({"text":str(text),"confidence":float(score),"bbox":[x1,y1,max(0,x2-x1),max(0,y2-y1)]})
    return out,{"paddle_version":paddle.__version__,"paddleocr_version":paddleocr.__version__,"latency_seconds":round(time.time()-started,3)}


def _slice_text(obs: list[dict], roi: list[int]) -> tuple[str,float]:
    hits=[o for o in obs if bbox_intersection_fraction(o["bbox"],roi) >= 0.10 or bbox_intersection_fraction(roi,o["bbox"]) >= 0.10]
    hits.sort(key=lambda o:(o["bbox"][1],o["bbox"][0]))
    return " ".join(o["text"] for o in hits).strip(), (sum(o["confidence"] for o in hits)/len(hits) if hits else 0.0)


def _valid(kind: str, text: str) -> bool:
    t=norm(text)
    if kind=="email": return "@" in text and "." in text.split("@")[-1]
    if kind=="phone_prefix": return "+51" in text.replace(" ","")
    if kind in {"number","phone"}: return sum(ch.isdigit() for ch in text) >= 6
    return bool(t)


def _reconcile(kind: str, a: str, ac: float, b: str, bc: float) -> tuple[str,str]:
    if a and b and sim(a,b)>=0.92:
        return (a if ac>=bc else b),"AGREEMENT"
    av,bv=_valid(kind,a),_valid(kind,b)
    if av and not bv: return a,"TESSERACT_VALIDATED"
    if bv and not av: return b,"PADDLE_VALIDATED"
    if a and not b: return a,"TESSERACT_ONLY"
    if b and not a: return b,"PADDLE_ONLY"
    return "","NEEDS_REVIEW"


def main() -> int:
    raw=_fetch_source()
    with tempfile.TemporaryDirectory(prefix="lf-dual-ocr-") as td:
        src=Path(td)/"source.png"; src.write_bytes(raw)
        t0=time.time(); tess=_tesseract(str(src)); tess_latency=round(time.time()-t0,3)
        paddle,pmeta=_paddle(str(src))
        rows=[]
        for s in SLICES:
            ta,tc=_slice_text(tess,s["bbox"]); pb,pc=_slice_text(paddle,s["bbox"])
            rec,decision=_reconcile(s["kind"],ta,tc,pb,pc)
            rows.append({
                "id":s["id"],"kind":s["kind"],"expected":s["expected"],
                "tesseract":ta,"tesseract_confidence":round(tc,4),"tesseract_similarity":round(sim(ta,s["expected"]),4),
                "paddle":pb,"paddle_confidence":round(pc,4),"paddle_similarity":round(sim(pb,s["expected"]),4),
                "reconciled":rec,"decision":decision,"reconciled_similarity":round(sim(rec,s["expected"]),4),
            })
        def exact_count(key): return sum(sim(r[key],r["expected"])>=0.98 for r in rows)
        result={
            "schema_version":"p0-dual-ocr-microbenchmark/v1",
            "source_sha256":SOURCE_SHA256,
            "github_sha":os.environ.get("GITHUB_SHA"),
            "reference_class":"CURATED_TECHNICAL_TARGET_SLICES_NOT_HUMAN_ADJUDICATION",
            "real_corpus_credit":0,
            "p0_5_credit":0,
            "engines":{
                "tesseract":{"family":"TESSERACT","psm":11,"lang":"spa","latency_seconds":tess_latency,"observation_count":len(tess)},
                "paddle":{"family":"PADDLEOCR","ocr_version":"PP-OCRv5","lang":"es","observation_count":len(paddle),**pmeta},
            },
            "slices":rows,
            "summary":{
                "slice_count":len(rows),
                "tesseract_exact_or_near":exact_count("tesseract"),
                "paddle_exact_or_near":exact_count("paddle"),
                "reconciled_exact_or_near":exact_count("reconciled"),
                "needs_review":sum(r["decision"]=="NEEDS_REVIEW" for r in rows),
                "email_tesseract":next(r["tesseract"] for r in rows if r["id"]=="email_placeholder"),
                "email_paddle":next(r["paddle"] for r in rows if r["id"]=="email_placeholder"),
                "email_reconciled":next(r["reconciled"] for r in rows if r["id"]=="email_placeholder"),
            },
            "adoption_grade":False,
            "runtime_promoted":False,
            "production_authorized":False,
            "holdout_accessed":False,
        }
        print("DUAL_OCR_RESULT="+json.dumps(result,ensure_ascii=False,sort_keys=True,separators=(",",":")))
        print("PASS_DUAL_OCR_MICROBENCHMARK_EXEC=1/1")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
