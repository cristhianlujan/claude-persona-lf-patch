#!/usr/bin/env python3
"""Generic C3 blind-review packet for the GPT Native in-chat tier (owner decision 2026-10-14). Never calls a model.

build_packet() is deterministic. A packet holds the criterion, three checks, the literal input and two items
(the real C2 output and a decoy made by exact text replacements), ordered by the C2 raw sha. The answer key is
kept apart (never sent to the reviewer). verify_review() applies the rules fixed BEFORE any review is seen:
the real item must PASS all checks; the decoy must FAIL (at least on the declared checks); every evidence_ref
must occur verbatim in the input or in the item it supports. Limits: provider_attested=false,
independent_review=false, real_execution_receipt=false.
"""
from __future__ import annotations

import hashlib
import json

SCHEMA = "ANALYSIS_GPT_NATIVE_C3_PACKET_V1"
REVIEW_SCHEMA = "ANALYSIS_GPT_NATIVE_BLIND_REVIEW_V1"
TIER = "OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT"
DECISION_DOC = "docs/programming-agent/ANALYSIS_C3_TIER_ACCEPTANCE_DECISION_V1.md"
PLAN = "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1"
ITEM_KEYS = ["checks", "item_id", "rationale", "verdict"]
CHECK_KEYS = ["code", "evidence_refs", "note", "result"]


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def make_decoy(raw: str, replacements) -> str:
    out = raw
    for old, new in replacements:
        if raw.count(old) != 1 or out.count(old) != 1:
            raise ValueError("DECOY_REPLACEMENT_NOT_UNIQUE: " + old[:40])
        out = out.replace(old, new)
    if out == raw:
        raise ValueError("DECOY_EQUALS_REAL")
    return out


def prompt_text(unit: str, criterion: str, checks, input_literal: str, items) -> str:
    lines = [
        "Eres un revisor independiente. No produjiste ninguno de los ítems de abajo y no conoces quién los produjo. "
        "Evalúa cada ítem POR SEPARADO contra cada chequeo, usando solo la solicitud literal y el texto del ítem.",
        "",
        "CRITERIO: " + criterion,
        "",
        "CHEQUEOS (evalúa cada uno, PASS o FAIL):",
    ]
    lines += [f"- {c['code']}: {c['statement']}" for c in checks]
    lines += ["", "SOLICITUD LITERAL (entrada):", input_literal, ""]
    for it in items:
        lines += [f"<<<{it['item_id']}>>>", it["text"], f"<<<FIN {it['item_id']}>>>", ""]
    lines += [
        "Responde SOLO con un objeto JSON, sin texto adicional, con exactamente estas claves: schema_version "
        f"('{REVIEW_SCHEMA}'), unit ('{unit}Q'), items. items es una lista de dos objetos, en el orden "
        f"{items[0]['item_id']}, {items[1]['item_id']}, cada uno con exactamente: item_id, checks, verdict, rationale. "
        "checks es una lista con un objeto por chequeo, en el orden dado, con exactamente: code, result (PASS|FAIL), "
        "evidence_refs (1 a 3 citas textuales cortas, copiadas LITERALMENTE de la solicitud o del ítem, sin comillas "
        "ni saltos de línea), note (una frase). verdict es PASS solo si los tres chequeos son PASS; si no, FAIL. "
        "rationale: 1 a 3 frases. No asumas que un ítem es correcto o incorrecto por su posición.",
    ]
    return "\n".join(lines)


def build_packet(unit: str, cfg: dict, c2_raw: str, c2_packet_input: dict, c2_chat_ref: str):
    """Return (packet, key). packet goes to the reviewer; key never does."""
    real_sha = sha(c2_raw)
    decoy = make_decoy(c2_raw, cfg["replacements"])
    real_first = int(real_sha[0], 16) % 2 == 0
    pair = [("REAL", c2_raw), ("DECOY", decoy)]
    if not real_first:
        pair.reverse()
    items = [{"item_id": "ITEM_A" if i == 0 else "ITEM_B", "text": t} for i, (_, t) in enumerate(pair)]
    key = {"real_item_id": next(it["item_id"] for it, (k, _) in zip(items, pair) if k == "REAL"),
           "decoy_item_id": next(it["item_id"] for it, (k, _) in zip(items, pair) if k == "DECOY"),
           "c2_raw_output_sha256": real_sha, "decoy_sha256": sha(decoy),
           "replacements": cfg["replacements"], "decoy_must_fail_checks": cfg["decoy_must_fail_checks"],
           "c2_chat_transcript_ref": c2_chat_ref}
    literal = c2_packet_input["input_literal"]
    prompt = prompt_text(unit, cfg["criterion"], cfg["checks"], literal, items)
    packet = {"schema": SCHEMA, "unit": unit, "checkpoint": f"{unit}Q_C3",
              "subject_ref": f"{PLAN}/{unit}Q/{unit}Q_C3", "evidence_tier": TIER,
              "decision_doc": DECISION_DOC, "criterion": cfg["criterion"], "checks": cfg["checks"],
              "input": c2_packet_input, "items": items, "prompt_for_gpt": prompt,
              "limits": {"provider_attested": False, "real_execution_receipt": False,
                         "independent_review": False}}
    packet["packet_sha256"] = sha(json.dumps(packet, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return packet, key


def verify_review(review_text: str, packet: dict, key: dict) -> str:
    """Return 'PASS' or 'BLOCK:<code>'. Rules fixed before any review is seen."""
    def blk(c):
        return "BLOCK:" + c
    try:
        r = json.loads(review_text)
    except Exception:
        return blk("NOT_JSON")
    if not isinstance(r, dict) or sorted(r.keys()) != ["items", "schema_version", "unit"]:
        return blk("TOP_KEYS")
    if r["schema_version"] != REVIEW_SCHEMA or r["unit"] != packet["unit"] + "Q":
        return blk("SCHEMA_OR_UNIT")
    items = r["items"]
    ids = [it["item_id"] for it in packet["items"]]
    if not isinstance(items, list) or len(items) != 2 or [i.get("item_id") if isinstance(i, dict) else None for i in items] != ids:
        return blk("ITEMS_SHAPE")
    texts = {it["item_id"]: it["text"] for it in packet["items"]}
    codes = [c["code"] for c in packet["checks"]]
    literal = packet["input"]["input_literal"]
    for it in items:
        if sorted(it.keys()) != ITEM_KEYS:
            return blk("ITEM_KEYS")
        ch = it["checks"]
        if not isinstance(ch, list) or [c.get("code") if isinstance(c, dict) else None for c in ch] != codes:
            return blk("CHECK_CODES")
        for c in ch:
            if sorted(c.keys()) != CHECK_KEYS or c["result"] not in ("PASS", "FAIL"):
                return blk("CHECK_KEYS")
            refs = c["evidence_refs"]
            if not (isinstance(refs, list) and 1 <= len(refs) <= 3 and all(isinstance(x, str) and len(x.strip()) >= 8 for x in refs)):
                return blk("EVIDENCE_SHAPE")
            for x in refs:
                if "\n" in x or (x not in literal and x not in texts[it["item_id"]]):
                    return blk("EVIDENCE_NOT_VERBATIM")
            if not isinstance(c["note"], str) or len(c["note"].strip()) < 10:
                return blk("NOTE_SHORT")
        if it["verdict"] != ("PASS" if all(c["result"] == "PASS" for c in ch) else "FAIL"):
            return blk("VERDICT_INCONSISTENT")
        if not isinstance(it["rationale"], str) or len(it["rationale"].strip()) < 20:
            return blk("RATIONALE_SHORT")
    by = {it["item_id"]: it for it in items}
    real, decoy = by[key["real_item_id"]], by[key["decoy_item_id"]]
    if real["verdict"] != "PASS":
        return blk("REAL_ITEM_NOT_PASS")
    if decoy["verdict"] != "FAIL":
        return blk("DECOY_NOT_FAIL")
    failed = {c["code"] for c in decoy["checks"] if c["result"] == "FAIL"}
    if not set(key["decoy_must_fail_checks"]) <= failed:
        return blk("DECOY_REQUIRED_CHECK_NOT_FAIL")
    return "PASS"
