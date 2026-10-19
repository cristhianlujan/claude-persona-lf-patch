#!/usr/bin/env python3
"""A15Q_C1 refreeze confirmation (GPT Native in-chat; mechanics only).

build_packet(): packet for a separate GPT Native chat holding the refreeze manifest and the
exact bytes of every source_bundle file. verify_confirmation(): deterministic check of the
reviewer's raw JSON. The reviewer's hashes must equal the hashes recomputed here from the bytes
in the packet, so a confirmation that did not read the bytes cannot pass.

Limits: confirms bundle integrity and manifest consistency only. It does not re-run the empirical
gates, is not provider-attested and is not an independent review. Never rewrites the manifest.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "analysis_v1_freeze_manifest_v1.json"
SCHEMA = "ANALYSIS_A15_REFREEZE_CONFIRMATION_V1"
CHECKS = ("BUNDLE_BYTES_MATCH_MANIFEST", "REFREEZE_REASON_CONSISTENT", "NO_OVERCLAIM")
STATEMENTS = {
    "BUNDLE_BYTES_MATCH_MANIFEST": "Para cada archivo del paquete, el git blob sha1 calculado desde sus bytes exactos coincide con el blob declarado en source_bundle del manifiesto.",
    "REFREEZE_REASON_CONSISTENT": "El motivo del refreeze (contrato A5 omitido en el primer paquete y cambio posterior del contrato de entrada de Programming y del validador Wave1) es coherente con el contenido: el paquete incluye ahora el contrato A5 (decision_context), el contrato de entrada y el validador Wave1.",
    "NO_OVERCLAIM": "El manifiesto no afirma un merge realizado, ni autoriza retirar historias, ni activa runtime o producción, ni se autoconfirma (independent_confirmation_ref vacío), y declara que los gates empíricos pertenecen al primer freeze y no fueron re-ejecutados.",
}


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def git_blob(b: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest()


def build_packet(base: Path = HERE) -> dict:
    mtext = (base / MANIFEST.name).read_text(encoding="utf-8")
    manifest = json.loads(mtext)
    files = []
    for e in manifest["source_bundle"]:
        data = (base / e["path"]).read_bytes()
        files.append({"unit": e["unit"], "path": e["path"], "declared_blob": e["blob"],
                      "bytes": len(data), "content": data.decode("utf-8")})
    expected = [{"unit": f["unit"], "path": f["path"], "sha256": sha256(f["content"].encode()),
                 "git_blob_sha1": git_blob(f["content"].encode())} for f in files]
    schema_example = {"schema_version": SCHEMA, "files": [{"unit": "A1", "path": "…", "sha256": "…", "git_blob_sha1": "…", "matches_declared_blob": True}],
                      "checks": [{"code": c, "result": "PASS|FAIL", "evidence_refs": ["texto literal del paquete"], "note": "…"} for c in CHECKS],
                      "verdict": "CONFIRM|REJECT", "rationale": "…"}
    prompt = (
        "Eres un confirmador independiente del refreeze de análisis A15. Usa SOLO este paquete. "
        "Para CADA archivo de 'files' calcula con código (no de memoria) el sha256 y el git blob sha1 de sus bytes UTF-8 exactos "
        "(content tal cual; git blob = sha1 de b'blob <len>\\0' + bytes) y compáralo con declared_blob. "
        "Luego evalúa los chequeos y responde SOLO con un objeto JSON, sin texto adicional, con este esquema:\n"
        + json.dumps(schema_example, ensure_ascii=False)
        + "\nChequeos (código: enunciado):\n"
        + "\n".join(f"- {c}: {STATEMENTS[c]}" for c in CHECKS)
        + "\nReglas: 'files' debe tener una entrada por archivo, en el mismo orden. Cada chequeo lleva 2 a 4 evidence_refs "
        "copiados literalmente del paquete (campos del manifiesto o hashes calculados) y una note de al menos 40 caracteres. "
        "verdict es CONFIRM solo si los tres chequeos son PASS; en otro caso REJECT. Esta confirmación solo cubre integridad del paquete y "
        "consistencia del manifiesto; no re-ejecuta los gates empíricos y no es una atestación de proveedor.")
    pkt = {"subject_ref": "PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A15Q/A15Q_C1", "checkpoint": "A15Q_C1",
           "kind": "REFREEZE_INDEPENDENT_CONFIRMATION", "manifest_text": mtext, "files": files,
           "checks": [{"code": c, "statement": STATEMENTS[c]} for c in CHECKS], "prompt_for_gpt": prompt,
           "limits": {"provider_attested": False, "independent_review": False, "empirical_gates_rerun": False},
           "evidence_tier": "OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT"}
    pkt["packet_sha256"] = sha256(json.dumps({k: v for k, v in pkt.items()}, ensure_ascii=False, sort_keys=True).encode())
    return pkt, expected


def verify_confirmation(raw: str, packet: dict, expected: list) -> str:
    """Return 'CONFIRMED' or 'REJECTED:<code>' (fail closed)."""
    try:
        d = json.loads(raw)
    except Exception:
        return "REJECTED:NOT_JSON"
    if raw.strip() != raw.strip().strip("`") or not isinstance(d, dict):
        return "REJECTED:NOT_PURE_JSON"
    if set(d) != {"schema_version", "files", "checks", "verdict", "rationale"} or d["schema_version"] != SCHEMA:
        return "REJECTED:SCHEMA"
    fs = d["files"]
    if not isinstance(fs, list) or len(fs) != len(expected):
        return "REJECTED:FILES_COUNT"
    for got, exp in zip(fs, expected):
        if not isinstance(got, dict) or any(got.get(k) != exp[k] for k in exp):
            return "REJECTED:FILE_HASH_MISMATCH:" + str(exp["unit"])
        if got.get("matches_declared_blob") is not True:
            return "REJECTED:FILE_NOT_MATCHING_DECLARED:" + str(exp["unit"])
    cs = d["checks"]
    if not isinstance(cs, list) or [c.get("code") for c in cs] != list(CHECKS):
        return "REJECTED:CHECK_CODES"
    blob = packet["manifest_text"] + "\n" + "\n".join(f["content"] for f in packet["files"]) + "\n" + json.dumps(expected)
    for c in cs:
        refs = c.get("evidence_refs")
        if c.get("result") != "PASS":
            return "REJECTED:CHECK_NOT_PASS:" + c["code"]
        if not isinstance(refs, list) or not 2 <= len(refs) <= 4 or any(not isinstance(r, str) or len(r) < 6 or r not in blob for r in refs):
            return "REJECTED:EVIDENCE_NOT_IN_PACKET:" + c["code"]
        if not isinstance(c.get("note"), str) or len(c["note"]) < 40:
            return "REJECTED:NOTE_SHORT:" + c["code"]
    if d["verdict"] != "CONFIRM" or not isinstance(d["rationale"], str) or len(d["rationale"]) < 40:
        return "REJECTED:VERDICT"
    return "CONFIRMED"


if __name__ == "__main__":
    p, e = build_packet()
    print(p["packet_sha256"], len(json.dumps(p, ensure_ascii=False)), len(e))
