#!/usr/bin/env python3
"""Deterministic F4 TypeScript emitter from lf_ops.f4_tipos_catalogo_v1 JSON.

No network, no LLM, no invented data. Fail-closed for shape, ordering, or source drift.
Usage: psql -At -c 'SELECT lf_ops.f4_tipos_catalogo_v1()' | python3 f4_codegen.py --verify <path>
"""
import argparse
import json
import pathlib
import re
import sys

FAMILY = re.compile(r"^[A-Z][A-Z0-9_]{2,62}$")
TYPE = {"TECNICA", "VISUAL", "NEGOCIO", "LEGAL"}

def lit(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

def generate(doc):
    if not isinstance(doc, dict) or doc.get("schema_version") != "LF_NUCLEO_TYPED_CATALOG_V1":
        raise ValueError("F4_CODEGEN_SCHEMA_INVALID")
    families = doc.get("familias")
    enums = doc.get("enums")
    if not isinstance(families, list) or not isinstance(enums, list) or not families or not enums:
        raise ValueError("F4_CODEGEN_COLLECTIONS_EMPTY")
    family_codes = []
    enum_codes = []
    for f in families:
        if not isinstance(f, dict) or set(f) != {"codigo", "tipo"}:
            raise ValueError("F4_CODEGEN_FAMILY_SHAPE")
        if not isinstance(f["codigo"], str) or not FAMILY.fullmatch(f["codigo"]) or f["tipo"] not in TYPE:
            raise ValueError("F4_CODEGEN_FAMILY_BAD")
        family_codes.append(f["codigo"])
    for e in enums:
        if not isinstance(e, dict) or set(e) != {"hecho", "valores"}:
            raise ValueError("F4_CODEGEN_ENUM_SHAPE")
        if not isinstance(e["hecho"], str) or not e["hecho"].startswith("COL-") or not isinstance(e["valores"], list) or not e["valores"]:
            raise ValueError("F4_CODEGEN_ENUM_BAD")
        vals = e["valores"]
        if not all(isinstance(v, str) and v.strip() for v in vals) or len(vals) != len(set(vals)):
            raise ValueError("F4_CODEGEN_ENUM_VALUES_UNTRUSTED")
        e["valores"] = sorted(vals)
        enum_codes.append(e["hecho"])
    # Database collations can differ. Fail on duplicates, but normalize order
    # canonically in code so SDK bytes do not vary by PostgreSQL locale.
    if len(family_codes) != len(set(family_codes)) or len(enum_codes) != len(set(enum_codes)):
        raise ValueError("F4_CODEGEN_DUPLICATE")
    families = sorted(families, key=lambda x: x["codigo"])
    enums = sorted(enums, key=lambda x: x["hecho"])
    lines = [
        "// GENERATED; do not hand-edit. Source: lf_ops.f4_tipos_catalogo_v1() (Supabase LF).",
        "// No runtime binding or business implementation is implied by these types.",
        "export const LF_NUCLEO_FAMILIAS = [",
    ]
    lines.extend("  " + lit(f["codigo"]) + "," for f in families)
    lines.extend([
        "] as const;",
        "export type LfNucleoFamilia = (typeof LF_NUCLEO_FAMILIAS)[number];",
        "",
        "export const LF_NUCLEO_TIPO_POR_FAMILIA = {",
    ])
    lines.extend("  " + lit(f["codigo"]) + ": " + lit(f["tipo"]) + "," for f in families)
    lines.extend([
        "} as const;",
        "export type LfNucleoTipoDeFamilia<F extends LfNucleoFamilia> = (typeof LF_NUCLEO_TIPO_POR_FAMILIA)[F];",
        "",
        "export const LF_NUCLEO_ENUMS_POR_HECHO = {",
    ])
    lines.extend("  " + lit(e["hecho"]) + ": [" + ",".join(lit(v) for v in e["valores"]) + "]," for e in enums)
    lines.extend([
        "} as const;",
        "export type LfNucleoEnumHecho = keyof typeof LF_NUCLEO_ENUMS_POR_HECHO;",
        "export type LfNucleoEnumValor<H extends LfNucleoEnumHecho> = (typeof LF_NUCLEO_ENUMS_POR_HECHO)[H][number];",
        "",
    ])
    return "\n".join(lines)

def main():
    ap = argparse.ArgumentParser()
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--verify", type=pathlib.Path)
    group.add_argument("--output", type=pathlib.Path)
    args = ap.parse_args()
    doc = json.load(sys.stdin)
    generated = generate(doc)
    if args.verify is not None:
        if not args.verify.is_file() or args.verify.read_text(encoding="utf-8") != generated:
            raise RuntimeError("F4_CODEGEN_DRIFT: committed types disagree with database catalog")
        print("F4_CODEGEN_PASS families=" + str(len(doc["familias"])) +
              " enum_groups=" + str(len(doc["enums"])) +
              " enum_values=" + str(sum(len(x["valores"]) for x in doc["enums"])))
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(generated, encoding="utf-8")
        print("F4_CODEGEN_EMITTED " + str(args.output))
if __name__ == "__main__":
    main()
