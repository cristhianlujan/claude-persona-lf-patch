#!/usr/bin/env python3
"""Validador del contrato de la etapa 1 del Router ACT-0001 (LF): LF_ROUTER_STAGE1_V1.

La etapa 1 la produce el modelo nativo (GPT/Claude). Este validador solo comprueba la forma y las
reglas del contrato y decide el siguiente paso; no clasifica, no busca y no autoriza ningun efecto.
"""
from __future__ import annotations
import json
import re
import sys
from typing import Any

SCHEMA = "LF_ROUTER_STAGE1_V1"
SISTEMAS = {"LF", "SALY", "OTRO", "DESCONOCIDO"}
MAX_FORMAS = 4
MAX_ALTERNATIVAS = 3
CODE_RE = re.compile(r"\b(?:ACT-\d{3,5}|REG_[A-Z0-9_]+|PERFIL-[A-Z0-9-]+|ADAPTER-[A-Z0-9-]+|SKILL-[A-Z0-9-]+|EDGE_FN_[A-Z0-9_]+)\b", re.I)
HINT_RE = re.compile(r"^[A-Z][A-Z0-9_]{2,63}$")


def _s(v: Any) -> bool:
    return isinstance(v, str) and bool(v.strip())


def validate(out: Any) -> dict[str, Any]:
    """Devuelve {valid, codes, next_step}. next_step: DIRECT_ANSWER | ASK_USER | LEVEL1_SEARCH | SYSTEM_NOT_SUPPORTED | INVALID."""
    codes: list[str] = []
    if not isinstance(out, dict):
        return {"valid": False, "codes": ["NOT_AN_OBJECT"], "next_step": "INVALID"}
    if out.get("schema_version") != SCHEMA:
        codes.append("BAD_SCHEMA_VERSION")
    if not _s(out.get("texto_original")):
        codes.append("ORIGINAL_TEXT_REQUIRED")
    if out.get("downstream_execution_allowed") is not False:
        codes.append("DOWNSTREAM_EXECUTION_MUST_BE_FALSE")
    es_op = out.get("es_operacion")
    if not isinstance(es_op, bool):
        codes.append("ES_OPERACION_BOOL_REQUIRED")
    sistema = out.get("sistema")
    formas = out.get("formas_busqueda", [])
    alts = out.get("alternativas", [])
    ambiguo = out.get("ambiguo")
    pregunta = out.get("pregunta_usuario")
    hint = out.get("capability_hint")
    corr = out.get("correcciones", [])

    if not isinstance(ambiguo, bool):
        codes.append("AMBIGUO_BOOL_REQUIRED")
    if not isinstance(formas, list) or not all(_s(x) for x in formas):
        codes.append("FORMAS_BUSQUEDA_INVALID")
        formas = []
    if not isinstance(alts, list) or not all(_s(x) for x in alts):
        codes.append("ALTERNATIVAS_INVALID")
        alts = []
    if pregunta is not None and not _s(pregunta):
        codes.append("PREGUNTA_INVALID")
    if isinstance(pregunta, str) and pregunta.count("?") + pregunta.count("¿") > 2:
        codes.append("MORE_THAN_ONE_QUESTION")
    if hint is not None and not (isinstance(hint, str) and HINT_RE.match(hint)):
        codes.append("CAPABILITY_HINT_INVALID")
    if not isinstance(corr, list) or not all(
        isinstance(c, dict) and _s(c.get("de")) and _s(c.get("a")) and c["de"].strip().lower() != c["a"].strip().lower() for c in corr
    ):
        codes.append("CORRECCIONES_INVALID")

    # No inventar: ningun codigo de activo puede aparecer en las formas si el usuario no lo escribio.
    original = out.get("texto_original") if isinstance(out.get("texto_original"), str) else ""
    typed = {m.group(0).upper() for m in CODE_RE.finditer(original)}
    for f in formas:
        for m in CODE_RE.finditer(f):
            if m.group(0).upper() not in typed:
                codes.append("INVENTED_ASSET_CODE")
                break
    if len(formas) > MAX_FORMAS:
        codes.append("TOO_MANY_FORMAS")
    if len(alts) > MAX_ALTERNATIVAS:
        codes.append("TOO_MANY_ALTERNATIVAS")

    if es_op is False:
        if out.get("respuesta_directa") is not True:
            codes.append("NON_OPERATION_REQUIRES_DIRECT_ANSWER")
        if formas or hint is not None:
            codes.append("NON_OPERATION_MUST_NOT_SEARCH")
    elif es_op is True:
        if sistema not in SISTEMAS:
            codes.append("SISTEMA_INVALID")
        if not (_s(out.get("sujeto")) or _s(out.get("accion"))):
            codes.append("SUBJECT_OR_ACTION_REQUIRED")
        if not formas:
            codes.append("FORMAS_BUSQUEDA_REQUIRED")
        if out.get("respuesta_directa") is True:
            codes.append("OPERATION_CANNOT_BE_DIRECT_ANSWER")
    if ambiguo is True and not (2 <= len(alts) <= MAX_ALTERNATIVAS and _s(pregunta)):
        codes.append("AMBIGUOUS_REQUIRES_ALTERNATIVES_AND_ONE_QUESTION")
    if ambiguo is False and alts:
        codes.append("ALTERNATIVES_WITHOUT_AMBIGUITY")

    if codes:
        return {"valid": False, "codes": sorted(set(codes)), "next_step": "INVALID"}
    if es_op is False:
        step = "DIRECT_ANSWER"
    elif ambiguo is True:
        step = "ASK_USER"
    elif sistema != "LF":
        step = "SYSTEM_NOT_SUPPORTED"
    else:
        step = "LEVEL1_SEARCH"
    return {"valid": True, "codes": [], "next_step": step}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: stage1_validator_v1.py <stage1.json>")
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.dumps(validate(json.load(f)), indent=2, ensure_ascii=False))
