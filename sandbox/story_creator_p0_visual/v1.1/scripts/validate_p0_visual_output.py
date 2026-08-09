#!/usr/bin/env python3
"""Validate P0 visual-reader output without claiming model quality."""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import struct
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps, UnidentifiedImageError

from p0_schema import validate_instance
from validate_p0_j02_handoff import load

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
FIXTURE = ROOT / "evals" / "p0-visual-reader-fixture.json"
LOW_CONFIDENCE_THRESHOLD = 0.70


def schema_errors(name: str, value: Any) -> list[str]:
    schema = load(SCHEMAS / name)
    return validate_instance(schema, value)


def ui_semantic_checks(ui_structure: dict[str, Any], observations: list[Any], source_refs: set[Any]) -> dict[str, int]:
    obs_by_id = {
        item.get("observation_id"): item
        for item in observations
        if isinstance(item, dict) and isinstance(item.get("observation_id"), str)
    }
    obs_ids = set(obs_by_id)
    tree = ui_structure.get("visual_containment_tree") if isinstance(ui_structure.get("visual_containment_tree"), dict) else {}
    roots_list = tree.get("roots") if isinstance(tree.get("roots"), list) else []
    roots = {item for item in roots_list if isinstance(item, str)}
    edges = tree.get("edges") if isinstance(tree.get("edges"), list) else []
    known_nodes = roots | obs_ids
    parent_count: dict[str, int] = {}
    adjacency: dict[str, list[str]] = {}
    unknown_endpoints = 0
    invalid_sources = 0
    source_mismatches = 0
    root_as_child = 0
    geometry_violations = 0
    root_sources: dict[str, set[Any]] = {root: set() for root in roots}
    for edge in edges:
        if not isinstance(edge, dict):
            continue
        parent, child, source_ref = edge.get("parent"), edge.get("child"), edge.get("source_ref")
        if parent not in known_nodes or child not in obs_ids:
            unknown_endpoints += 1
        if child in roots:
            root_as_child += 1
        if isinstance(child, str):
            parent_count[child] = parent_count.get(child, 0) + 1
        if isinstance(parent, str) and isinstance(child, str):
            adjacency.setdefault(parent, []).append(child)
        if source_ref not in source_refs:
            invalid_sources += 1
        if parent in roots:
            root_sources.setdefault(parent, set()).add(source_ref)
        child_source = obs_by_id.get(child, {}).get("source_image_ref") if isinstance(child, str) else None
        if child_source is not None and source_ref != child_source:
            source_mismatches += 1
        parent_source = obs_by_id.get(parent, {}).get("source_image_ref") if isinstance(parent, str) else None
        if parent_source is not None and source_ref != parent_source:
            source_mismatches += 1
        if parent in obs_by_id and child in obs_by_id:
            parent_region = obs_by_id[parent].get("region")
            child_region = obs_by_id[child].get("region")
            if isinstance(parent_region, dict) and isinstance(child_region, dict):
                try:
                    contains = (
                        float(parent_region["x"]) <= float(child_region["x"])
                        and float(parent_region["y"]) <= float(child_region["y"])
                        and float(parent_region["x"]) + float(parent_region["width"]) >= float(child_region["x"]) + float(child_region["width"])
                        and float(parent_region["y"]) + float(parent_region["height"]) >= float(child_region["y"]) + float(child_region["height"])
                    )
                except (KeyError, TypeError, ValueError):
                    contains = False
                if not contains:
                    geometry_violations += 1

    cycle = 0
    state: dict[str, int] = {}

    def visit(node: str) -> None:
        nonlocal cycle
        if cycle:
            return
        marker = state.get(node, 0)
        if marker == 1:
            cycle = 1
            return
        if marker == 2:
            return
        state[node] = 1
        for child in adjacency.get(node, []):
            if child in known_nodes:
                visit(child)
        state[node] = 2

    for node in sorted(known_nodes):
        visit(node)

    reading_orders = ui_structure.get("candidate_reading_orders") if isinstance(ui_structure.get("candidate_reading_orders"), list) else []
    reading_unknown = 0
    reading_duplicates = 0
    reading_source_mismatches = 0
    covered: set[str] = set()
    for order in reading_orders:
        if not isinstance(order, dict):
            continue
        ids = order.get("element_ids") if isinstance(order.get("element_ids"), list) else []
        reading_duplicates += len(ids) - len(set(ids))
        for element_id in ids:
            if element_id not in obs_ids:
                reading_unknown += 1
                continue
            covered.add(element_id)
            if obs_by_id[element_id].get("source_image_ref") != order.get("source_ref"):
                reading_source_mismatches += 1

    layer_graph = ui_structure.get("visual_layer_graph") if isinstance(ui_structure.get("visual_layer_graph"), list) else []
    layer_unknown = 0
    layer_invalid_sources = 0
    for relation in layer_graph:
        if not isinstance(relation, dict):
            continue
        if relation.get("from") not in obs_ids or relation.get("to") not in obs_ids:
            layer_unknown += 1
        if relation.get("source_ref") not in source_refs:
            layer_invalid_sources += 1

    return {
        "containment_unknown_endpoint": unknown_endpoints,
        "containment_invalid_source": invalid_sources,
        "containment_source_mismatch": source_mismatches,
        "containment_root_as_child": root_as_child,
        "containment_missing_parent": sum(1 for observation_id in obs_ids if parent_count.get(observation_id, 0) == 0),
        "containment_multiple_parents": sum(1 for observation_id in obs_ids if parent_count.get(observation_id, 0) > 1),
        "containment_cycle": cycle,
        "containment_geometry_violation": geometry_violations,
        "containment_root_without_child": sum(1 for root in roots if not adjacency.get(root)),
        "containment_root_source_ambiguity": sum(1 for refs in root_sources.values() if len(refs) > 1),
        "container_without_children": sum(1 for observation_id, item in obs_by_id.items() if item.get("element_type") == "CONTAINER" and not adjacency.get(observation_id)),
        "reading_order_unknown_element": reading_unknown,
        "reading_order_duplicate_element": reading_duplicates,
        "reading_order_source_mismatch": reading_source_mismatches,
        "reading_order_missing_observation": len(obs_ids - covered),
        "layer_graph_unknown_endpoint": layer_unknown,
        "layer_graph_invalid_source": layer_invalid_sources,
    }


def recompute_crop_sha(raw: bytes, region: dict[str, Any]) -> str:
    with Image.open(io.BytesIO(raw)) as opened:
        opened.load()
        image = ImageOps.exif_transpose(opened).convert("RGBA")
    x = float(region["x"]); y = float(region["y"]); width = float(region["width"]); height = float(region["height"])
    x1 = max(0, min(image.width - 1, int(x)))
    y1 = max(0, min(image.height - 1, int(y)))
    x2 = max(x1 + 1, min(image.width, int(round(x + width))))
    y2 = max(y1 + 1, min(image.height, int(round(y + height))))
    crop = image.crop((x1, y1, x2, y2)).convert("RGBA")
    material = struct.pack(">II", crop.width, crop.height) + crop.tobytes()
    return hashlib.sha256(material).hexdigest()


def validate(payload: Any, trusted_admissions: Any = None, trusted_source_bytes: Any = None, *, require_crop_recompute: bool = False) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"result": "BLOCKED", "blocking_assertions": ["visual_output_invalid"]}
    bundle = payload.get("blind_bundle") if isinstance(payload.get("blind_bundle"), dict) else {}
    observations = payload.get("observations") if isinstance(payload.get("observations"), list) else []
    evidence = payload.get("evidence") if isinstance(payload.get("evidence"), list) else []
    ui_structure = payload.get("ui_structure") if isinstance(payload.get("ui_structure"), dict) else {}
    source_images = bundle.get("source_images", []) if isinstance(bundle.get("source_images"), list) else []
    dimensions = bundle.get("dimensions", []) if isinstance(bundle.get("dimensions"), list) else []
    source_refs = {item.get("ref") for item in source_images if isinstance(item, dict)}
    source_sha_by_ref = {
        item.get("ref"): item.get("sha256")
        for item in bundle.get("source_images", [])
        if isinstance(item, dict) and isinstance(item.get("ref"), str)
    }
    bundle_hashes = set(bundle.get("hashes", [])) if isinstance(bundle.get("hashes"), list) else set()
    evidence_refs = {item.get("evidence_ref") for item in evidence if isinstance(item, dict)}
    evidence_by_ref = {
        item.get("evidence_ref"): item
        for item in evidence
        if isinstance(item, dict) and isinstance(item.get("evidence_ref"), str)
    }
    observation_ids = [item.get("observation_id") for item in observations if isinstance(item, dict)]
    evidence_ref_list = [item.get("evidence_ref") for item in evidence if isinstance(item, dict)]
    admissions = trusted_admissions if isinstance(trusted_admissions, list) else []
    admission_schema_errors = sum((schema_errors("image-admission-record.schema.json", item) for item in admissions), [])
    admission_ref_list = [item.get("source_ref") for item in admissions if isinstance(item, dict)]
    admissions_by_ref = {
        item.get("source_ref"): item
        for item in admissions
        if isinstance(item, dict) and isinstance(item.get("source_ref"), str)
    }
    source_bytes_by_ref = trusted_source_bytes if isinstance(trusted_source_bytes, dict) else {}
    crop_pixel_hash_mismatches = 0
    crop_recompute_missing_sources = 0
    crop_recompute_decode_failures = 0
    if require_crop_recompute:
        for item in evidence:
            if not isinstance(item, dict) or item.get("kind") != "CROP":
                continue
            ref = item.get("source_ref")
            raw = source_bytes_by_ref.get(ref)
            if not isinstance(raw, bytes):
                crop_recompute_missing_sources += 1
                continue
            if hashlib.sha256(raw).hexdigest() != source_sha_by_ref.get(ref):
                crop_pixel_hash_mismatches += 1
                continue
            try:
                observed = recompute_crop_sha(raw, item.get("region", {}))
            except (UnidentifiedImageError, OSError, KeyError, TypeError, ValueError):
                crop_recompute_decode_failures += 1
                continue
            if observed != item.get("sha256"):
                crop_pixel_hash_mismatches += 1
    observation_schema_errors = sum((schema_errors("visual-observation.schema.json", item) for item in observations), [])
    evidence_schema_errors = sum((schema_errors("evidence.schema.json", item) for item in evidence), [])
    checks = {
        "blind_bundle_schema_invalid": len(schema_errors("blind-input-bundle.schema.json", bundle)),
        "observations_empty": 0 if observations else 1,
        "visual_observation_schema_invalid": len(observation_schema_errors),
        "ui_structure_schema_invalid": len(schema_errors("ui-structure.schema.json", ui_structure)),
        "evidence_schema_invalid": len(evidence_schema_errors),
        "duplicate_observation_ids": len(observation_ids) - len(set(observation_ids)),
        "duplicate_evidence_refs": len(evidence_ref_list) - len(set(evidence_ref_list)),
        "trusted_admission_missing": sum(1 for ref in source_refs if ref not in admissions_by_ref),
        "trusted_admission_unexpected": sum(1 for ref in admissions_by_ref if ref not in source_refs),
        "trusted_admission_duplicate_refs": len(admission_ref_list) - len(set(admission_ref_list)),
        "trusted_admission_schema_invalid": len(admission_schema_errors),
        "source_dimension_count_mismatch": abs(len(source_images) - len(dimensions)),
        "source_sha_mismatch_admission": sum(
            1
            for ref, sha in source_sha_by_ref.items()
            if ref in admissions_by_ref and admissions_by_ref[ref].get("raw_bytes_sha256") != sha
        ),
        "source_format_mismatch_admission": sum(
            1
            for ref in source_refs
            if ref in admissions_by_ref and admissions_by_ref[ref].get("input_format") != bundle.get("format")
        ),
        "source_dimension_mismatch_admission": sum(
            1
            for index, item in enumerate(source_images)
            if isinstance(item, dict)
            and index < len(dimensions)
            and isinstance(dimensions[index], dict)
            and item.get("ref") in admissions_by_ref
            and (
                admissions_by_ref[item["ref"]].get("width") != dimensions[index].get("width")
                or admissions_by_ref[item["ref"]].get("height") != dimensions[index].get("height")
            )
        ),
        "source_hash_missing_from_bundle_hashes": sum(
            1 for sha in source_sha_by_ref.values() if sha not in bundle_hashes
        ),
        "observation_source_unknown": sum(1 for item in observations if isinstance(item, dict) and item.get("source_image_ref") not in source_refs),
        "observation_without_evidence": sum(1 for item in observations if isinstance(item, dict) and item.get("evidence_ref") not in evidence_refs),
        "observation_evidence_source_mismatch": sum(
            1
            for item in observations
            if isinstance(item, dict)
            and item.get("evidence_ref") in evidence_by_ref
            and evidence_by_ref[item["evidence_ref"]].get("source_ref") != item.get("source_image_ref")
        ),
        "crop_source_hash_mismatch": sum(
            1
            for item in evidence
            if isinstance(item, dict)
            and item.get("kind") == "CROP"
            and (
                item.get("source_ref") not in admissions_by_ref
                or item.get("source_raw_sha256") != admissions_by_ref[item.get("source_ref")].get("raw_bytes_sha256")
            )
        ),
        "observation_crop_region_mismatch": sum(
            1
            for item in observations
            if isinstance(item, dict)
            and item.get("evidence_ref") in evidence_by_ref
            and evidence_by_ref[item.get("evidence_ref")].get("kind") == "CROP"
            and evidence_by_ref[item.get("evidence_ref")].get("region") != item.get("region")
        ),
        "crop_pixel_hash_mismatch": crop_pixel_hash_mismatches,
        "crop_recompute_missing_source": crop_recompute_missing_sources,
        "crop_recompute_decode_failure": crop_recompute_decode_failures,
        "evidence_source_unknown": sum(
            1
            for item in evidence
            if isinstance(item, dict)
            and item.get("kind") in {"SOURCE_IMAGE", "CROP"}
            and item.get("source_ref") not in source_refs
        ),
        "source_image_evidence_hash_mismatch": sum(
            1
            for item in evidence
            if isinstance(item, dict)
            and item.get("kind") == "SOURCE_IMAGE"
            and (
                item.get("source_ref") not in admissions_by_ref
                or admissions_by_ref[item.get("source_ref")].get("raw_bytes_sha256") != item.get("sha256")
            )
        ),
        "low_confidence_without_abstention": sum(1 for item in observations if isinstance(item, dict) and isinstance(item.get("confidence"), (int, float)) and item["confidence"] < LOW_CONFIDENCE_THRESHOLD and item.get("abstained") is not True),
        "sensitive_retained_evidence_unredacted": sum(1 for item in evidence if isinstance(item, dict) and item.get("data_classification") == "SENSITIVE" and item.get("kind") in {"CROP", "AUXILIARY_SOURCE", "ADJUDICATION"} and item.get("redacted") is not True),
    }
    checks.update(ui_semantic_checks(ui_structure, observations, source_refs))
    failed = sorted(key for key, value in checks.items() if value)
    return {"result": "PASS_WITH_EVIDENCE" if not failed else "BLOCKED", "blocking_assertions": failed, "checks": checks, "observation_count": len(observations), "evidence_count": len(evidence), "empirical_visual_quality_claimed": False}


def self_test() -> int:
    good = load(FIXTURE)
    source = good["blind_bundle"]["source_images"][0]
    dims = good["blind_bundle"]["dimensions"][0]
    trusted = [{
        "schema_version": "p0-image-admission/v1",
        "source_ref": source["ref"],
        "raw_bytes_sha256": source["sha256"],
        "normalized_pixel_sha256": "9" * 64,
        "processing_manifest_sha256": "8" * 64,
        "input_format": good["blind_bundle"]["format"],
        "width": dims["width"],
        "height": dims["height"],
        "normalized_mode": "RGBA",
        "decoder_name": "Pillow",
        "decoder_version": "fixture",
    }]
    positive = validate(good, trusted)
    cases = []
    x = copy.deepcopy(good); x["observations"].append(copy.deepcopy(x["observations"][0])); cases.append(("duplicate_observation", x, "duplicate_observation_ids"))
    x = copy.deepcopy(good); x["observations"][0]["confidence"] = 0.4; x["observations"][0]["abstained"] = False; cases.append(("low_confidence_without_abstention", x, "low_confidence_without_abstention"))
    x = copy.deepcopy(good); x["evidence"] = x["evidence"][1:]; cases.append(("missing_crop_evidence", x, "observation_without_evidence"))
    x = copy.deepcopy(good); x["observations"][0]["source_image_ref"] = "image://unknown"; cases.append(("unknown_source_image", x, "observation_source_unknown"))
    x = copy.deepcopy(good); x["blind_bundle"]["hashes"] = ["f" * 64]; cases.append(("source_hash_not_in_bundle_hashes", x, "source_hash_missing_from_bundle_hashes"))
    x = copy.deepcopy(good); x["evidence"][0]["kind"] = "SOURCE_IMAGE"; x["evidence"][0]["sha256"] = "f" * 64; cases.append(("source_image_evidence_hash_mismatch", x, "source_image_evidence_hash_mismatch"))
    x = copy.deepcopy(good); x["evidence"][0]["source_ref"] = "image://unknown"; cases.append(("evidence_source_mismatch", x, "observation_evidence_source_mismatch"))
    x = copy.deepcopy(good); x["blind_bundle"]["source_images"][0]["sha256"] = "f" * 64; x["blind_bundle"]["hashes"] = ["f" * 64]; cases.append(("source_sha_mismatch_trusted_admission", x, "source_sha_mismatch_admission"))
    x = copy.deepcopy(good); x["evidence"][0]["source_raw_sha256"] = "f" * 64; cases.append(("crop_source_hash_mismatch", x, "crop_source_hash_mismatch"))
    x = copy.deepcopy(good); x["evidence"][0]["region"]["x"] += 1; cases.append(("crop_region_mismatch", x, "observation_crop_region_mismatch"))
    x = copy.deepcopy(good); ids = [item["observation_id"] for item in x["observations"]]; source_ref = x["blind_bundle"]["source_images"][0]["ref"]; x["ui_structure"]["visual_containment_tree"]["edges"] = [{"parent": ids[2], "child": ids[0], "source_ref": source_ref}, {"parent": ids[0], "child": ids[1], "source_ref": source_ref}, {"parent": ids[1], "child": ids[2], "source_ref": source_ref}]; cases.append(("containment_cycle", x, "containment_cycle"))
    x = copy.deepcopy(good); x["ui_structure"]["visual_containment_tree"]["edges"][0]["child"] = "OBS-UNKNOWN"; cases.append(("containment_unknown_child", x, "containment_unknown_endpoint"))
    x = copy.deepcopy(good); x["ui_structure"]["visual_containment_tree"]["edges"].append({"parent": "OBS-DNI", "child": "OBS-PASSWORD", "source_ref": "image://login"}); cases.append(("containment_multiple_parents", x, "containment_multiple_parents"))
    x = copy.deepcopy(good); x["ui_structure"]["candidate_reading_orders"][0]["element_ids"].append("OBS-UNKNOWN"); cases.append(("reading_order_unknown", x, "reading_order_unknown_element"))
    x = copy.deepcopy(good); x["ui_structure"]["visual_containment_tree"]["edges"][1]["parent"] = "OBS-DNI"; cases.append(("containment_geometry", x, "containment_geometry_violation"))
    outcomes = []
    for name, payload, expected in cases:
        result = validate(payload, trusted)
        outcomes.append({"name": name, "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})
    passed = positive["result"] == "PASS_WITH_EVIDENCE" and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_pass": positive["result"] == "PASS_WITH_EVIDENCE", "positive_observations": positive.get("observation_count"), "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "empirical_visual_quality_claimed": False, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--admission-record", action="append", type=Path, default=[])
    parser.add_argument("--source-image", action="append", default=[], metavar="REF=PATH")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    if not args.admission_record:
        parser.error("--admission-record is required for trusted source binding")
    if not args.source_image:
        parser.error("--source-image REF=PATH is required for independent crop recomputation")
    source_bytes: dict[str, bytes] = {}
    for spec in args.source_image:
        if "=" not in spec:
            parser.error("--source-image must be REF=PATH")
        ref, source_path = spec.split("=", 1)
        if not ref or not source_path or ref in source_bytes:
            parser.error("--source-image must use unique non-empty REF=PATH values")
        source_bytes[ref] = Path(source_path).read_bytes()
    result = validate(load(args.input), [load(path) for path in args.admission_record], source_bytes, require_crop_recompute=True)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
