#!/usr/bin/env python3
"""Conservative icon-role reconciliation over governed reader + CLIP evidence.

The resolver never asserts click behavior. It only decides whether a compact
visual needs an *independent* function question or can be accounted for by an
already-visible parent/copy relationship. Technical source-bound evaluation
only; no authentic human adjudication or runtime promotion.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

PASSIVE_IDENTITIES = {"SHIELD", "LOCK", "LIGHTNING", "PERSON", "IDENTITY_CARD", "BRAND_MARK"}
TEXT_OVERLAP_MIN = 0.80
HORIZONTAL_GAP_MAX = 48
HORIZONTAL_CENTER_DY_MAX = 24
VERTICAL_GAP_MAX = 60
VERTICAL_CENTER_DX_MAX = 48
CHECKBOX_ROW_DY_MAX = 8


def region(item: dict) -> dict:
    r = item.get("region") or item.get("bbox") or {}
    return {k: float(r.get(k, 0)) for k in ("x", "y", "width", "height")}


def center(r: dict) -> tuple[float, float]:
    return r["x"] + r["width"] / 2, r["y"] + r["height"] / 2


def overlap_primary(a: dict, b: dict) -> float:
    x1, y1 = max(a["x"], b["x"]), max(a["y"], b["y"])
    x2 = min(a["x"] + a["width"], b["x"] + b["width"])
    y2 = min(a["y"] + a["height"], b["y"] + b["height"])
    inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    return inter / max(1.0, a["width"] * a["height"])


def center_inside(inner: dict, outer: dict) -> bool:
    cx, cy = center(inner)
    return outer["x"] <= cx <= outer["x"] + outer["width"] and outer["y"] <= cy <= outer["y"] + outer["height"]


def horizontal_copy(icon: dict, text: dict) -> bool:
    ix2 = icon["x"] + icon["width"]
    gap = text["x"] - ix2
    _, icy = center(icon)
    _, tcy = center(text)
    return 0 <= gap <= HORIZONTAL_GAP_MAX and abs(icy - tcy) <= HORIZONTAL_CENTER_DY_MAX


def vertical_label(icon: dict, text: dict) -> bool:
    iy2 = icon["y"] + icon["height"]
    gap = text["y"] - iy2
    icx, _ = center(icon)
    tcx, _ = center(text)
    return 0 <= gap <= VERTICAL_GAP_MAX and abs(icx - tcx) <= VERTICAL_CENTER_DX_MAX


def resolve_one(icon: dict, top1_identity: str, texts: list[dict], controls: list[dict], checkboxes: list[dict]) -> dict:
    ir = region(icon)
    overlapping = [t for t in texts if overlap_primary(ir, region(t)) >= TEXT_OVERLAP_MIN]
    if overlapping:
        return {"needs_independent_function_review": False, "disposition": "RECLASSIFY_TEXT_OVERLAP", "evidence_element_ids": [overlapping[0]["element_id"]]}

    containing = [c for c in controls if center_inside(ir, region(c))]
    if containing:
        containing.sort(key=lambda c: region(c)["width"] * region(c)["height"])
        return {"needs_independent_function_review": False, "disposition": "INHERIT_PARENT_CONTROL", "evidence_element_ids": [containing[0]["element_id"]]}

    if top1_identity == "HELP_QUESTION":
        return {"needs_independent_function_review": True, "disposition": "INDEPENDENT_INTERACTION_NOT_PROVEN", "evidence_element_ids": []}

    if top1_identity in PASSIVE_IDENTITIES:
        paired = [t for t in texts if horizontal_copy(ir, region(t))]
        if paired:
            paired.sort(key=lambda t: region(t)["x"] - (ir["x"] + ir["width"]))
            return {"needs_independent_function_review": False, "disposition": "SUPPORTS_ADJACENT_COPY", "evidence_element_ids": [paired[0]["element_id"]]}

        below = [t for t in texts if vertical_label(ir, region(t))]
        if below:
            below.sort(key=lambda t: region(t)["y"] - (ir["y"] + ir["height"]))
            return {"needs_independent_function_review": False, "disposition": "SUPPORTS_STACKED_COPY", "evidence_element_ids": [below[0]["element_id"]]}

        if top1_identity == "SHIELD":
            _, icy = center(ir)
            same_row = [c for c in checkboxes if abs(center(region(c))[1] - icy) <= CHECKBOX_ROW_DY_MAX]
            if same_row:
                return {"needs_independent_function_review": False, "disposition": "ROW_ASSURANCE_MARK", "evidence_element_ids": [same_row[0]["element_id"]]}

    return {"needs_independent_function_review": True, "disposition": "ABSTAIN_ROLE_NOT_PROVEN", "evidence_element_ids": []}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--packet", required=True)
    ap.add_argument("--clip", required=True)
    ap.add_argument("--targets", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        a = {"x": 10, "y": 10, "width": 20, "height": 20}
        assert overlap_primary(a, {"x": 10, "y": 10, "width": 20, "height": 20}) == 1.0
        assert horizontal_copy(a, {"x": 35, "y": 12, "width": 80, "height": 15})
        assert vertical_label(a, {"x": 8, "y": 35, "width": 30, "height": 12})
        print(json.dumps({"gate":"PASS_ICON_ROLE_RECONCILIATION_SELF_TEST"}, sort_keys=True))
        return 0

    packet = json.loads(Path(args.packet).read_text(encoding="utf-8"))
    clip = json.loads(Path(args.clip).read_text(encoding="utf-8"))
    targets = json.loads(Path(args.targets).read_text(encoding="utf-8"))
    if targets.get("reference_class") != "TECHNICAL_OBSERVABLE_REFERENCE_NOT_HUMAN_ADJUDICATION":
        raise SystemExit("FAIL_ROLE_REFERENCE_CLASS")
    if targets.get("real_corpus_credit") != 0 or targets.get("p0_5_credit") != 0:
        raise SystemExit("FAIL_ROLE_CREDIT_BOUNDARY")
    if clip.get("source_sha256") != targets.get("source_sha256"):
        raise SystemExit("FAIL_ROLE_SOURCE_CLIP_BINDING")

    readers = packet.get("reader_outputs") or []
    if len(readers) < 3:
        raise SystemExit("FAIL_ROLE_PACKET_READERS")
    strict = readers[2]
    elements = strict.get("elements") or []
    by_id = {e.get("element_id"): e for e in elements}
    texts = [e for e in elements if e.get("element_type") == "TEXT" and e.get("visible_text")]
    controls = [e for e in elements if e.get("element_type") == "CONTROL_REGION"]
    checkboxes = [e for e in elements if e.get("element_type") == "CHECKBOX"]
    icon_ids = [u.get("element_id") for u in strict.get("reader_uncertainties") or [] if u.get("code") == "ICON_FUNCTION_NOT_OBSERVABLE"]
    expected_ids = [t["element_id"] for t in targets["targets"]]
    if icon_ids != expected_ids:
        raise SystemExit(f"FAIL_ROLE_ICON_SET_BINDING:{icon_ids!r}")

    clip_by_id = {r["element_id"]: r for r in clip["targets"]}
    target_by_id = {t["element_id"]: t for t in targets["targets"]}
    rows = []
    resolved = 0
    tp = fp = fn = tn = 0
    for icon_id in icon_ids:
        icon = by_id.get(icon_id)
        if not icon:
            raise SystemExit(f"FAIL_ROLE_ICON_MISSING:{icon_id}")
        clip_row = clip_by_id[icon_id]
        decision = resolve_one(icon, clip_row["top1_identity"], texts, controls, checkboxes)
        safe = not decision["needs_independent_function_review"]
        expected_safe = bool(target_by_id[icon_id]["policy_resolvable"])
        resolved += int(safe)
        tp += int(safe and expected_safe)
        fp += int(safe and not expected_safe)
        fn += int((not safe) and expected_safe)
        tn += int((not safe) and (not expected_safe))
        rows.append({
            "element_id": icon_id,
            "clip_top1_identity": clip_row["top1_identity"],
            "clip_top1_correct_against_technical_reference": clip_row["top1_correct"],
            **decision,
            "technical_reference_policy_resolvable": expected_safe,
        })

    if fp != 0:
        raise SystemExit(f"FAIL_ROLE_FALSE_POSITIVE:{fp}")
    metrics = {
        "icon_uncertainties_before": len(icon_ids),
        "candidate_resolved_without_independent_function_review": resolved,
        "candidate_icon_uncertainties_remaining": len(icon_ids) - resolved,
        "candidate_reduction_rate": resolved / len(icon_ids),
        "technical_reference_true_positive": tp,
        "technical_reference_false_positive": fp,
        "technical_reference_false_negative": fn,
        "technical_reference_true_negative": tn,
        "technical_reference_precision": tp / max(1, tp + fp),
        "technical_reference_recall": tp / max(1, tp + fn),
        "interaction_functions_confirmed": 0,
    }
    out = {
        "schema_version":"p0-icon-role-reconciliation/v1",
        "source_sha256":targets["source_sha256"],
        "reference_class":targets["reference_class"],
        "decision_policy":{
            "text_overlap_min":TEXT_OVERLAP_MIN,
            "horizontal_gap_max":HORIZONTAL_GAP_MAX,
            "horizontal_center_dy_max":HORIZONTAL_CENTER_DY_MAX,
            "vertical_gap_max":VERTICAL_GAP_MAX,
            "vertical_center_dx_max":VERTICAL_CENTER_DX_MAX,
            "checkbox_row_dy_max":CHECKBOX_ROW_DY_MAX,
            "passive_identities":sorted(PASSIVE_IDENTITIES),
            "help_identity_abstains":True,
            "clip_similarity_threshold_used":False,
        },
        "metrics":metrics,
        "targets":rows,
        "real_corpus_credit":0,
        "p0_5_credit":0,
        "holdout_accessed":False,
        "runtime_promoted":False,
        "production_authorized":False,
    }
    path=Path(args.output); path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(out,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(json.dumps({"gate":"PASS_P0_ICON_ROLE_RECONCILIATION","resolved":resolved,"remaining":len(icon_ids)-resolved,"false_positive":fp},sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
