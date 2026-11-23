"""Guardia creativa positiva de la skill existente (NO genera ni transmite).

Se ejecuta después de art_direction_preflight_v1 y antes de compilar el handoff.
No es una skill nueva, un nuevo Router ni un proveedor de arte/QA. No modifica
contratos históricos, permisos o fuentes. Valida propuestas; no juzga estética.
"""
from __future__ import annotations

import copy
import hashlib
import json
from typing import Any

from art_direction_preflight_v1 import ArtBlocked, preflight

SCHEMA = "SALY_CREATIVE_POSITIVE_PROCESS_V1"
MODES = {"CORRECTION_STRICT", "EXPLORE_CREATIVE"}
CRITERIA = ("direccion", "creatividad_funcional", "composicion",
            "legibilidad", "fidelidad_fuentes", "handoff")
GENERIC = {"premium", "moderno", "elegante", "wow", "bonito", "creativo",
           "más premium", "más moderno", "más elegante", "más creativo"}
SHA64 = set("0123456789abcdef")


class CreativeProcessBlocked(ValueError):
    pass


def check(condition: bool, code: str) -> None:
    if not condition:
        raise CreativeProcessBlocked(code)


def exact(value: Any, names: set[str], code: str) -> None:
    check(type(value) is dict and set(value) == names, code)


def filled(value: Any) -> bool:
    return type(value) is str and bool(value.strip())


def digest(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True,
                     separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def meaningful_direction(text: Any) -> bool:
    if not filled(text):
        return False
    clean = " ".join(text.lower().split()).strip(". ")
    return clean not in GENERIC and len(clean.split()) >= 5


def prepare_positive_review(plan: dict[str, Any],
                            decision: dict[str, Any]) -> dict[str, Any]:
    """Produce una proyección de revisión sin autoridad Native ni mutaciones."""
    check(type(plan) is dict and type(decision) is dict,
          "CREATIVE_PROCESS_INPUT_SHAPE")
    # Deep copy: the preflight cannot influence the judge's immutable snapshot.
    frozen_plan, frozen_decision = copy.deepcopy(plan), copy.deepcopy(decision)
    try:
        structural = preflight(frozen_plan)
    except ArtBlocked as exc:
        raise CreativeProcessBlocked("CREATIVE_BASE_" + str(exc)) from exc

    exact(frozen_decision, {"schema_version", "mode", "mode_evidence",
                            "positive_outcomes", "creative_zones",
                            "alternatives", "selected_alternative",
                            "transport"}, "CREATIVE_PROCESS_FIELDS")
    check(frozen_decision["schema_version"] == SCHEMA, "CREATIVE_PROCESS_SCHEMA")
    mode = frozen_decision["mode"]
    check(type(mode) is str and mode in MODES, "CREATIVE_MODE_UNKNOWN")

    evidence = frozen_decision["mode_evidence"]
    exact(evidence, {"source", "quote"}, "CREATIVE_MODE_EVIDENCE_FIELDS")
    check(evidence["source"] == "REQUEST" and filled(evidence["quote"])
          and evidence["quote"] in frozen_plan["literal_request"],
          "CREATIVE_MODE_NOT_GROUNDED")
    # Structural provenance does not certify semantic intent: separate QA needed.
    sources = {"REQUEST": {"status": "USER_LITERAL",
                           "ref": "CURRENT_REQUEST",
                           "sha256": hashlib.sha256(
                               frozen_plan["literal_request"].encode("utf-8")
                           ).hexdigest()}}
    sources.update({s["id"]: s for s in frozen_plan["sources"]})
    components = {c["name"]: c for c in frozen_plan["components"]}

    outcomes = frozen_decision["positive_outcomes"]
    check(type(outcomes) is list and len(outcomes) >= 3,
          "CREATIVE_POSITIVE_OUTCOMES_MISSING")
    seen_goals = set()
    for row in outcomes:
        exact(row, {"goal", "visual_instruction", "source_ids"},
              "CREATIVE_OUTCOME_FIELDS")
        check(filled(row["goal"]) and meaningful_direction(row["visual_instruction"]),
              "CREATIVE_OUTCOME_NOT_RENDERABLE")
        check(row["goal"] not in seen_goals, "CREATIVE_OUTCOME_DUPLICATE")
        seen_goals.add(row["goal"])
        ids = row["source_ids"]
        check(type(ids) is list and len(ids) > 0
              and all(type(k) is str and k in sources for k in ids),
              "CREATIVE_OUTCOME_SOURCE_UNGROUNDED")

    zones = frozen_decision["creative_zones"]
    check(type(zones) is list and len(zones) == len(components),
          "CREATIVE_ZONE_COVERAGE")
    seen_zones, free_native = set(), 0
    for row in zones:
        exact(row, {"component", "freedom", "positive_direction"},
              "CREATIVE_ZONE_FIELDS")
        name = row["component"]
        check(type(name) is str and name in components
              and name not in seen_zones, "CREATIVE_ZONE_DUPLICATE_OR_UNKNOWN")
        seen_zones.add(name)
        component = components[name]
        check(row["freedom"] == component["freedom"],
              "CREATIVE_ZONE_LOCK_MISMATCH")
        check(meaningful_direction(row["positive_direction"]),
              "CREATIVE_ZONE_DIRECTION_EMPTY")
        if component["owner"] == "NATIVE" and component["freedom"] == "FREE":
            free_native += 1
    check(seen_zones == set(components), "CREATIVE_ZONE_COVERAGE")

    if mode == "EXPLORE_CREATIVE":
        check(type(frozen_plan["blueprint"].get("free")) is list
              and len(frozen_plan["blueprint"]["free"]) > 0 and free_native > 0,
              "CREATIVE_EXPLORE_FREEDOM_EMPTY")

    alternatives = frozen_decision["alternatives"]
    check(type(alternatives) is list and
          len(alternatives) >= (2 if mode == "EXPLORE_CREATIVE" else 1),
          "CREATIVE_ALTERNATIVES_MISSING")
    by_id, moves = {}, set()
    for row in alternatives:
        exact(row, {"id", "visual_thesis", "design_move", "tradeoff"},
              "CREATIVE_ALTERNATIVE_FIELDS")
        check(filled(row["id"]) and filled(row["visual_thesis"]) and
              meaningful_direction(row["design_move"]) and filled(row["tradeoff"]),
              "CREATIVE_ALTERNATIVE_WEAK")
        check(row["id"] not in by_id and row["design_move"] not in moves,
              "CREATIVE_ALTERNATIVES_NOT_DISTINCT")
        by_id[row["id"]] = row
        moves.add(row["design_move"])

    choice = frozen_decision["selected_alternative"]
    exact(choice, {"id", "reason"}, "CREATIVE_SELECTION_FIELDS")
    check(type(choice["id"]) is str and choice["id"] in by_id and
          meaningful_direction(choice["reason"]), "CREATIVE_SELECTION_UNSUPPORTED")

    transport = frozen_decision["transport"]
    exact(transport, {"recipient", "presentation", "source_ids",
                      "transmitted", "render_authorized"}, "CREATIVE_TRANSPORT_FIELDS")
    check(transport["recipient"] == "NATIVE_GRAPHIC_GENERATOR"
          and transport["presentation"] == frozen_plan["presentation"]["mode"],
          "CREATIVE_TRANSPORT_DESTINATION")
    check(transport["transmitted"] is False and
          transport["render_authorized"] is False,
          "CREATIVE_TRANSPORT_FALSE_AUTHORITY")
    refs = transport["source_ids"]
    check(type(refs) is list and refs and len(set(refs)) == len(refs)
          and all(type(k) is str and k in sources for k in refs),
          "CREATIVE_TRANSPORT_SOURCE_UNGROUNDED")
    # Assets referenced here are metadata, never attest binary access or
    # attach an unofficial logo. Actual sender re-reads source bytes.
    source_manifest = [
        {"id":k, "ref":sources[k]["ref"], "status":sources[k]["status"],
         "sha256":sources[k]["sha256"]}
        for k in refs
    ]
    selected = by_id[choice["id"]]
    # Only renderable directives, not the deliberation, grades or QA metadata.
    prompt = "\n".join([
        structural["art_direction_supplement"],
        "Concepto compositivo seleccionado: " + selected["design_move"],
        *[row["visual_instruction"] for row in outcomes],
        *[row["component"] + ": " + row["positive_direction"] for row in zones
          if components[row["component"]]["owner"] == "NATIVE"],
    ])
    return {
        "schema_version": SCHEMA,
        "status": "CREATIVE_REVIEW_PREPARED_SEMANTIC_QA_PENDING",
        "business_code": frozen_plan["business_code"],
        "mode": mode,
        "plan_sha256": digest(frozen_plan),
        "decision_sha256": digest(frozen_decision),
        "selected_alternative": selected["id"],
        "source_manifest": source_manifest,
        "prompt_review": prompt,
        "prompt_sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
        "qa_criteria": list(CRITERIA),
        "qa_independent": "NOT_EVALUATED",
        "source_binary_attested": False,
        "native_transmitted": False,
        "image_generation_allowed": False,
        "order_created": False,
        "production_approved": False,
    }
