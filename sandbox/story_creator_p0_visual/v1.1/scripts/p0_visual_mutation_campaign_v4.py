#!/usr/bin/env python3
"""Deterministic F-02 invariant mutation campaign."""
from __future__ import annotations

import copy
import hashlib
import random

from p0_independent_omission_sweep_v4 import _best_match
from p0_visual_atomicity_v4 import exclusive_partition_issues


def _id(kind: str, ordinal: int, seed: str) -> str:
    return f"MUT-{ordinal:03d}-" + hashlib.sha256(f"{kind}:{ordinal}:{seed}".encode()).hexdigest()[:10]


def _candidate_elements(candidate: dict) -> list[dict]:
    return [element for element in candidate.get("elements") or [] if element.get("element_id") not in {"ROOT", "V4-ROOT"}]


def _deletion_detected(candidate: dict, sweep: dict, target_id: str) -> tuple[bool, list[str]]:
    remaining = [element for element in _candidate_elements(candidate) if element.get("element_id") != target_id]
    affected = [
        observation
        for observation in sweep.get("observations") or []
        if observation.get("material") is True and observation.get("matched_element_id") == target_id
    ]
    missed: list[str] = []
    for observation in affected:
        replacement, _score = _best_match(observation, remaining)
        if replacement is None:
            missed.append(str(observation.get("observation_id")))
    return bool(affected and missed), missed


def _shared_evidence_mutation(candidate: dict, left: dict, right: dict) -> tuple[dict, bool]:
    mutated = copy.deepcopy(candidate)
    by_id = {element.get("element_id"): element for element in mutated.get("elements") or []}
    source = by_id[left["element_id"]]
    target = by_id[right["element_id"]]
    source_tokens = list((source.get("text_lineage") or {}).get("source_token_ids") or [])
    if not source_tokens:
        return mutated, False
    target.setdefault("text_lineage", {}).setdefault("source_token_ids", []).append(source_tokens[0])
    return mutated, any(issue["code"] == "SHARED_EVIDENCE_VIOLATION" for issue in exclusive_partition_issues(mutated["elements"]))


def _unjustified_split_mutation(candidate: dict, source: dict, ordinal: int) -> tuple[dict, bool]:
    mutated = copy.deepcopy(candidate)
    elements = mutated.get("elements") or []
    index = next(i for i, element in enumerate(elements) if element.get("element_id") == source.get("element_id"))
    original = elements.pop(index)
    tokens = list((original.get("text_lineage") or {}).get("source_tokens") or [])
    token_ids = list((original.get("text_lineage") or {}).get("source_token_ids") or [])
    if len(tokens) < 2 or len(token_ids) < 2:
        return mutated, False
    cut = max(1, min(len(tokens) - 1, len(tokens) // 2))
    clones: list[dict] = []
    for suffix, selected_tokens, selected_ids in (
        ("A", tokens[:cut], token_ids[:cut]),
        ("B", tokens[cut:], token_ids[cut:]),
    ):
        clone = copy.deepcopy(original)
        clone["element_id"] = f"{original['element_id']}-S{ordinal:03d}{suffix}"
        clone["visible_text"] = " ".join(selected_tokens)
        clone["text_lineage"]["source_tokens"] = selected_tokens
        clone["text_lineage"]["source_token_ids"] = selected_ids
        clone["text_lineage"]["partition_boundary_before"] = None
        clones.append(clone)
    elements[index:index] = clones
    return mutated, any(issue["code"] == "UNJUSTIFIED_PARTITION" for issue in exclusive_partition_issues(elements))


def run_mutation_campaign(candidate: dict, sweep: dict, *, mutation_count: int = 100, seed: int = 20260812) -> dict:
    if mutation_count != 100:
        raise ValueError("F02_REQUIRES_EXACTLY_100_MUTATIONS")
    rng = random.Random(seed)
    elements = _candidate_elements(candidate)
    by_id = {str(element.get("element_id")): element for element in elements}
    material_targets = sorted(
        {
            str(observation.get("matched_element_id"))
            for observation in sweep.get("observations") or []
            if observation.get("material") is True and observation.get("matched_element_id") in by_id
        }
    )
    compact_targets = sorted(
        {
            str(observation.get("matched_element_id"))
            for observation in sweep.get("observations") or []
            if observation.get("material") is True
            and observation.get("kind") == "COMPACT_VISUAL"
            and observation.get("matched_element_id") in by_id
        }
    )
    text_elements = [
        element
        for element in elements
        if len((element.get("text_lineage") or {}).get("source_token_ids") or []) >= 2
    ]
    if not material_targets or not compact_targets or len(text_elements) < 2:
        return {
            "schema_version": "p0-mutation-campaign-v4/v1",
            "status": "BLOCKED",
            "mutation_count": 0,
            "detected_count": 0,
            "detection_rate": 0.0,
            "errors": ["INSUFFICIENT_SOURCE_BOUND_MUTATION_TARGETS"],
            "mutations": [],
        }

    mutations: list[dict] = []
    ordinal = 0
    for family, count, targets in (
        ("DELETE_MATERIAL_ELEMENT", 40, material_targets),
        ("DELETE_NON_TEXT_COMPACT", 20, compact_targets),
    ):
        shuffled = list(targets)
        rng.shuffle(shuffled)
        for index in range(count):
            ordinal += 1
            target_id = shuffled[index % len(shuffled)]
            detected, observation_ids = _deletion_detected(candidate, sweep, target_id)
            mutations.append(
                {
                    "mutation_id": _id(family, ordinal, target_id),
                    "family": family,
                    "target_element_ids": [target_id],
                    "detected": detected,
                    "detector_codes": ["MATERIAL_OMISSION"] if detected else [],
                    "affected_observation_ids": observation_ids,
                }
            )

    pairs = [(left, right) for index, left in enumerate(text_elements) for right in text_elements[index + 1 :]]
    rng.shuffle(pairs)
    for index in range(20):
        ordinal += 1
        left, right = pairs[index % len(pairs)]
        _mutated, detected = _shared_evidence_mutation(candidate, left, right)
        mutations.append(
            {
                "mutation_id": _id("MERGE_SIBLING_EVIDENCE", ordinal, left["element_id"] + right["element_id"]),
                "family": "MERGE_SIBLING_EVIDENCE",
                "target_element_ids": [left["element_id"], right["element_id"]],
                "detected": detected,
                "detector_codes": ["SHARED_EVIDENCE_VIOLATION"] if detected else [],
            }
        )

    shuffled_text = list(text_elements)
    rng.shuffle(shuffled_text)
    for index in range(20):
        ordinal += 1
        source = shuffled_text[index % len(shuffled_text)]
        _mutated, detected = _unjustified_split_mutation(candidate, source, ordinal)
        mutations.append(
            {
                "mutation_id": _id("UNJUSTIFIED_TEXT_SPLIT", ordinal, source["element_id"]),
                "family": "UNJUSTIFIED_TEXT_SPLIT",
                "target_element_ids": [source["element_id"]],
                "detected": detected,
                "detector_codes": ["UNJUSTIFIED_PARTITION"] if detected else [],
            }
        )

    detected_count = sum(mutation["detected"] is True for mutation in mutations)
    detection_rate = detected_count / max(1, len(mutations))
    return {
        "schema_version": "p0-mutation-campaign-v4/v1",
        "campaign_seed": seed,
        "status": "PASS" if len(mutations) == mutation_count and detection_rate == 1.0 else "BLOCKED",
        "mutation_count": len(mutations),
        "detected_count": detected_count,
        "detection_rate": detection_rate,
        "family_counts": {
            family: sum(mutation["family"] == family for mutation in mutations)
            for family in sorted({mutation["family"] for mutation in mutations})
        },
        "errors": [] if detection_rate == 1.0 else ["MUTATION_DETECTION_RATE_BELOW_100_PERCENT"],
        "mutations": mutations,
    }
