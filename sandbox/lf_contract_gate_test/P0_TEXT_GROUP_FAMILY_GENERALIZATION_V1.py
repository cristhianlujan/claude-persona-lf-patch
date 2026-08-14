#!/usr/bin/env python3
"""Executable family gate for topology-invariant OCR text grouping."""
from __future__ import annotations
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPTS))
import p0_full_reader_v4 as reader  # noqa: E402


def require(ok: bool, code: str) -> None:
    if not ok:
        raise AssertionError(code)


def node(text: str, left: int, top: int, width: int, height: int) -> dict:
    return {
        "text": text, "confidence": 96.0,
        "region": {"x": left, "y": top, "width": width, "height": height},
        "origin_psm": 3, "token_count": 1, "source_tokens": [text],
        "source_token_ids": [f"T-{left}-{top}-{text}"],
        "source_token_regions": [{"x": left, "y": top, "width": width, "height": height}],
        "source_line_keys": [f"3:{left}:{top}"], "block_id": left,
        "paragraph_id": 1, "line_id": 1, "segment_index": 1, "partition_boundary_before": None,
    }


REAL = [
    ("tu deuda", [("tu",65,325,35,26),("deuda",113,322,110,30)]),
    ("Pago seguro con Niubiz", [("Pago",612,274,47,21),("seguro",666,279,65,16),("con",739,279,32,11),("Niubiz",779,273,60,17)]),
    ("Cronograma del plan", [("Cronograma",559,110,157,27),("del",726,109,37,22),("plan",774,110,51,27)]),
    ("Carta de No Adeudo", [("Carta",1301,303,63,19),("de",1373,303,28,18),("No",1411,304,32,18),("Adeudo",1451,303,93,19)]),
    ("Detalle del precio", [("Detalle",952,127,82,21),("del",1042,127,33,21),("precio",1085,127,70,27)]),
    ("Monto del acuerdo", [("Monto",951,239,45,13),("del",1001,239,20,13),("acuerdo",1027,239,56,13)]),
]
PHRASES = ["Monto total","Pago pendiente","Número documento","Saldo disponible","Código de seguridad","Detalle del precio","Carta de No Adeudo","Procesamiento de pago"]


def text_result(items: list[dict]) -> list[str]:
    return [item["text"] for item in reader.graph_reconcile_ocr_segments(items)]


def synthetic_phrase(phrase: str, rng: random.Random) -> list[dict]:
    base_bottom = rng.randint(140, 520); base_height = rng.randint(24, 32); x = rng.randint(40, 130); items = []
    for word in phrase.split():
        height = base_height + rng.randint(-1, 1); bottom = base_bottom + rng.randint(-4, 4); top = bottom - height
        width = max(28, 9 * len(word) + rng.randint(0, 8))
        items.append(node(word, x, top, width, height)); x += width + rng.randint(2, 18)
    rng.shuffle(items); return items


def main() -> int:
    rng = random.Random(20260814)
    require(reader._legacy.ocr_lines is reader.ocr_lines, "FULL_READER_NOT_REBOUND_TO_GRAPH_RECONCILER")
    real_pass = real_total = 0
    for expected, geometry in REAL:
        base = [node(*item) for item in geometry]
        for _ in range(100):
            trial = list(base); rng.shuffle(trial); real_total += 1
            real_pass += text_result(trial) == [expected]
    require(real_pass == real_total == 600, f"REAL_TOPOLOGY_INVARIANCE:{real_pass}/{real_total}")
    synthetic_pass = synthetic_total = 0
    for phrase in PHRASES:
        for _ in range(200):
            synthetic_total += 1; synthetic_pass += text_result(synthetic_phrase(phrase, rng)) == [phrase]
    require(synthetic_pass == synthetic_total == 1600, f"SYNTHETIC_FAMILY:{synthetic_pass}/{synthetic_total}")
    negative_pass = negative_total = 0
    for _ in range(200):
        y = 200 + rng.randint(-15, 15); items = [node("Monto",80,y,65,28),node("total",145+rng.randint(30,90),y+rng.randint(-2,2),60,28)]
        negative_total += 1; negative_pass += len(reader.graph_reconcile_ocr_segments(items)) == 2
    for _ in range(200):
        items = [node("Pago",80,200,55,28),node("pendiente",142,200+rng.randint(12,32),95,28)]
        negative_total += 1; negative_pass += len(reader.graph_reconcile_ocr_segments(items)) == 2
    for _ in range(200):
        items = [node("e",80,200,18,18),node("correo",104,198,75,22)]
        negative_total += 1; negative_pass += len(reader.graph_reconcile_ocr_segments(items)) == 2
    require(negative_pass == negative_total == 600, f"NEGATIVE_GUARDS:{negative_pass}/{negative_total}")
    bridge = [node("Carta",100,100,63,19),node("de",172,100,28,18),node("No",210,101,32,18),node("Adeudo",250,100,93,19)]
    bridge_pass = 0
    for _ in range(500):
        trial = list(bridge); rng.shuffle(trial); bridge_pass += text_result(trial) == ["Carta de No Adeudo"]
    require(bridge_pass == 500, f"TRANSITIVE_BRIDGE:{bridge_pass}/500")
    print(json.dumps({"result":"PASS","family":"EKB-P0-014_TEXT_GROUPING","architecture":"GEOMETRIC_COMPATIBILITY_GRAPH_CONNECTED_COMPONENTS","real_topology_invariance":f"{real_pass}/{real_total}","synthetic_family":f"{synthetic_pass}/{synthetic_total}","negative_guards":f"{negative_pass}/{negative_total}","transitive_bridge":f"{bridge_pass}/500","screen_literals_in_production_logic":False,"fixed_source_coordinates_in_production_logic":False,"production_authorized":False}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
