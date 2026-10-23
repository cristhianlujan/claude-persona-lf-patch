#!/usr/bin/env python3
"""Capa 2b del nivel 2 del Router ACT-0001: busqueda de solo lectura en los archivos versionados del repo.

La invoca la capa llamadora (la base no puede leer archivos) despues de `lf_router_search_nivel2_v1` (capa 2a), solo con
consentimiento del usuario. Usa las palabras que recibe tal cual (las formas de la etapa 1 o el detalle del usuario):
no expande sinonimos. Devuelve pistas con la misma forma que la capa 2a; nunca autoriza efectos.
"""
from __future__ import annotations
import json
import math
import os
import re
import subprocess
import sys
import unicodedata

TEXT_EXT = (".md", ".json", ".py", ".sql", ".yml", ".yaml")
MAX_READ = 60000
STOP = set("de del la el los las para con que y en un una por al a es se".split())
SUFFIXES = ("ciones", "cion", "ando", "mente", "es", "s")


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def _stem(w: str) -> str:
    for suf in SUFFIXES:
        if w.endswith(suf) and len(w) - len(suf) >= 4:
            return w[: -len(suf)]
    return w


def tokens(s: str) -> set[str]:
    return {_stem(t) for t in re.findall(r"[a-z0-9]+", _norm(s)) if t not in STOP and len(t) > 2}


def tracked_files(repo_root: str) -> list[str]:
    out = subprocess.run(["git", "-C", repo_root, "ls-files"], capture_output=True, text=True, check=True).stdout
    return [p for p in out.splitlines() if p.endswith(TEXT_EXT)]


def search(repo_root: str, text: str, limit: int = 5) -> dict:
    qt = tokens(text)
    n = len(qt)
    need = min(n, min(3, max(2, math.ceil(n * 0.6)))) if n else 0
    found = []
    root = os.path.realpath(repo_root)
    for rel in tracked_files(repo_root):
        full = os.path.realpath(os.path.join(root, rel))
        if not full.startswith(root + os.sep):
            continue  # solo lectura dentro del repo
        try:
            with open(full, encoding="utf-8", errors="ignore") as f:
                content = f.read(MAX_READ)
        except OSError:
            continue
        pt = tokens(rel.replace("_", " ").replace("-", " ").replace("/", " "))
        ct = tokens(content)
        matched = sum(1 for t in qt if t in pt or t in ct)
        in_path = sum(1 for t in qt if t in pt)
        if n and matched >= need and matched > 0:
            found.append((in_path, matched, rel))
    found.sort(key=lambda x: (-x[0], -x[1], x[2]))
    lim = max(1, min(limit, 10))
    return {
        "schema_version": "LF_ROUTER_SEARCH_NIVEL2_REPO_V1",
        "router": "ACT-0001",
        "nivel": 2,
        "fuente": "repo:git ls-files (solo lectura)",
        "terminos_consulta": sorted(qt),
        "resultado": "ENCONTRADO_FUERA_DE_INVENTARIO" if found else "NO_ENCONTRADO_EN_REPO",
        "total_candidatos": len(found),
        "candidatos": [{"origen": "REPO_FILE", "ref": "repo://" + rel, "en_ruta": ip, "coinciden": m, "de": n} for ip, m, rel in found[:lim]],
        "consentimiento_requerido_antes_de_usar": True,
        "nota_es": "Son pistas: evidencia de que un archivo existe, no permiso ni decision. Si hay muchos candidatos, pedir un detalle al usuario y repetir con sus palabras.",
        "downstream_execution_allowed": False,
    }


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("usage: repo_search_nivel2_v1.py <repo_root> <texto> [limite]")
    print(json.dumps(search(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 5), ensure_ascii=False, indent=2))
