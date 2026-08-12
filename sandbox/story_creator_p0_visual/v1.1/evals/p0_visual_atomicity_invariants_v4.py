#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from p0_independent_omission_sweep_v4 import validate_sweep_receipt
from p0_visual_atomicity_v4 import (
    detect_compact_visuals,
    evidence_purity_issues,
    exclusive_partition_issues,
    repeated_control_cardinality_groups,
    segment_ocr_line_items,
)
from p0_visual_mutation_campaign_v4 import run_mutation_campaign


def region(x: int, y: int, width: int, height: int) -> dict:
    return {"x": x, "y": y, "width": width, "height": height}


def text_element(ordinal: int, x: int, text: str) -> dict:
    token_ids = [f"TOK-{ordinal}-{index}" for index, _token in enumerate(text.split(), 1)]
    return {
        "element_id": f"T-{ordinal:02d}",
        "element_type": "TEXT",
        "visible_text": text,
        "classification": "CONFIRMED",
        "region": region(x, 100 + ordinal * 30, max(30, len(text) * 8), 18),
        "crop_region": region(x, 100 + ordinal * 30, max(30, len(text) * 8), 18),
        "crop_sha256": f"CROP-{ordinal}",
        "parent_id": "V4-ROOT",
        "text_lineage": {
            "source_tokens": text.split(),
            "source_token_ids": token_ids,
            "source_line_keys": [f"11:{ordinal}:1:1"],
            "partition_boundary_before": None,
        },
    }


def synthetic_campaign_fixture() -> tuple[dict, dict]:
    elements = [
        {"element_id": "V4-ROOT", "element_type": "CONTAINER", "parent_id": None, "region": region(0, 0, 5000, 1500)}
    ]
    elements.extend(text_element(index, 50 + index * 300, f"material text {index}") for index in range(1, 13))
    for index in range(1, 7):
        elements.append(
            {
                "element_id": f"I-{index:02d}",
                "element_type": "ICON",
                "visible_text": None,
                "classification": "CONFIRMED",
                "region": region(200 + index * 400, 900, 24, 24),
                "crop_region": region(200 + index * 400, 900, 24, 24),
                "crop_sha256": f"ICON-CROP-{index}",
                "parent_id": "V4-ROOT",
            }
        )
    candidate = {"width": 5000, "height": 1500, "elements": elements}
    observations = []
    for index, element in enumerate(elements[1:], 1):
        compact = element["element_type"] == "ICON"
        observations.append(
            {
                "observation_id": f"OBS-{index:03d}",
                "kind": "COMPACT_VISUAL" if compact else "TEXT",
                "material": True,
                "text": None if compact else element["visible_text"],
                "region": copy.deepcopy(element["region"]),
                "match_status": "REPRESENTED",
                "matched_element_id": element["element_id"],
                "control_type": None,
                "repeated_control_group_id": None,
            }
        )
    return candidate, {"observations": observations}


def main() -> int:
    checks: dict[str, bool] = {}

    tokens = [
        {"text": "Celular", "x": 10, "y": 10, "width": 50, "height": 14},
        {"text": "Correo", "x": 310, "y": 10, "width": 55, "height": 14},
    ]
    checks["C01_R01_SIBLING_LABELS_SPLIT"] = len(segment_ocr_line_items(tokens)) == 2
    phrase = [
        {"text": "tú", "x": 10, "y": 10, "width": 16, "height": 14},
        {"text": "debes", "x": 32, "y": 10, "width": 42, "height": 14},
    ]
    checks["C03_R03_CONTIGUOUS_PHRASE_ATOMIC"] = len(segment_ocr_line_items(phrase)) == 1

    contaminated = [text_element(1, 10, "Celular"), text_element(2, 220, "Correo electrónico")]
    contaminated[1]["region"] = region(220, 130, 140, 18)
    contaminated[1]["crop_region"] = copy.deepcopy(contaminated[1]["region"])
    contaminated[0]["ocr_variants"] = ["Celular Correo electrónico"]
    contaminated[0]["crop_region"] = region(10, 130, 400, 18)
    checks["C01_C02_SHARED_SIBLING_EVIDENCE_BLOCKS"] = bool(evidence_purity_issues(contaminated))

    shared = copy.deepcopy(contaminated)
    shared[1]["text_lineage"]["source_token_ids"].append(shared[0]["text_lineage"]["source_token_ids"][0])
    checks["INV2_SHARED_TOKEN_BLOCKS"] = any(
        issue["code"] == "SHARED_EVIDENCE_VIOLATION" for issue in exclusive_partition_issues(shared)
    )
    split = copy.deepcopy(contaminated)
    split[1]["text_lineage"]["source_line_keys"] = split[0]["text_lineage"]["source_line_keys"]
    split[1]["text_lineage"]["partition_boundary_before"] = None
    checks["INV2_UNJUSTIFIED_PARTITION_BLOCKS"] = any(
        issue["code"] == "UNJUSTIFIED_PARTITION" for issue in exclusive_partition_issues(split)
    )

    image = np.full((220, 500, 3), 255, np.uint8)
    for y in (40, 90, 150):
        cv2.rectangle(image, (40, y), (62, y + 22), (0, 0, 0), 2)
    cv2.circle(image, (320, 105), 16, (0, 0, 0), 2)
    cv2.circle(image, (320, 105), 8, (0, 0, 0), 2)
    cv2.circle(image, (320, 105), 3, (0, 0, 0), 1)
    source_text = [
        {"text": "choice", "region": region(75, y, 80, 20)} for y in (40, 90, 150)
    ] + [{"text": "status", "region": region(350, 95, 80, 20)}]
    compact = detect_compact_visuals(image, source_text)
    controls = [item for item in compact if item["kind"] == "CONTROL"]
    icons = [item for item in compact if item["kind"] == "ICON"]
    checks["C04_R04_THREE_REPEATED_CONTROLS"] = len(controls) == 3 and len({item["repeated_control_group_id"] for item in controls}) == 1
    checks["C05_R05_NON_TEXT_COMPACT_MATERIAL"] = len(icons) >= 1

    observations = []
    for index, item in enumerate(controls, 1):
        observations.append(
            {
                "observation_id": f"CONTROL-{index}",
                "material": True,
                "control_type": "CHECKBOX",
                "repeated_control_group_id": "GROUP-1",
                "match_status": "REPRESENTED" if index < 3 else "UNREPRESENTED",
                "matched_element_id": f"BOX-{index}" if index < 3 else None,
            }
        )
    groups = repeated_control_cardinality_groups(observations)
    checks["R06_CARDINALITY_MISMATCH_BLOCKS"] = len(groups) == 1 and groups[0]["status"] == "MISMATCH"

    candidate, sweep = synthetic_campaign_fixture()
    campaign = run_mutation_campaign(candidate, sweep)
    checks["F02_R07_100_OF_100_MUTATIONS"] = campaign["status"] == "PASS" and campaign["detected_count"] == 100

    config = json.loads((ROOT / "evals/p0-closed-loop-runtime-config-v4.json").read_text())
    checks["F04_RETROACTIVE_INVALIDATION_VERSIONED"] = (
        config["retroactive_invalidation"]["policy"] == "REJECT_PASS_FROM_INVALIDATED_LOOP_VERSION"
        and len(config["retroactive_invalidation"]["invalidated_loop_versions"]) >= 2
    )
    checks["F01_F05_AUTONOMY_REMAINS_BLOCKED"] = (
        config["empirical_readiness"]["available_labeled_screens"] < config["empirical_readiness"]["minimum_versioned_labeled_screens"]
        and config["empirical_readiness"]["human_review_required"] is True
    )

    failed = [name for name, passed in checks.items() if not passed]
    print(json.dumps({"gate": "PASS_V4_ATOMICITY_INVARIANTS" if not failed else "FAIL_V4_ATOMICITY_INVARIANTS", "checks": checks, "failed": failed, "mutation_summary": {key: value for key, value in campaign.items() if key != "mutations"}}, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
