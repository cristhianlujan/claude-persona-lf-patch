#!/usr/bin/env python3
"""RW1-06 C1 commit-reveal verifier: CANDIDATE, advisory-only, not an admission.

Purpose: a lower-friction carrier for the sealed holdout that needs no GnuPG, no key
and no file management by the owner. The separate GPT Native reviewer keeps the
corpus and oracles in a sealed bundle; the producer only ever receives hashes
(public Git commitment, BEFORE producer RAW) and, after its RAW is committed, the
bundle for integrity verification.

What this proves (and nothing else):
  STRUCTURE   exact public fields, minima 12/24/2, F01-F13, pre-registered oracles
  CHRONOLOGY  Git ancestry: attempt -> commitment -> producer RAW
  INTEGRITY   revealed bytes hash to the committed digests (at reveal only)

What this never proves: reviewer isolation, provider attestation, independent
review or C1 closure. Those stay false until the owner decision recorded in
RW1_06_C1_SEPARATION_EVIDENCE_DECISION_V1.md is taken and its evidence exists.
Existing validators and the GPG route are untouched.
"""
from __future__ import annotations

import argparse
import ast
import base64
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import re
import secrets
import subprocess
import tempfile
import zlib
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _load(stem: str):
    spec = importlib.util.spec_from_file_location(stem, HERE / (stem + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


seal = _load("seal_rw106_c1_gpg_v2")
pre = _load("validate_rw106_c1_precommit_order_v2")

SOURCE, POLICY, REPO = seal.SOURCE, seal.POLICY, pre.REPO
ATTEMPT_PATH = pre.ATTEMPT_PATH
SHA40, SHA64 = pre.SHA40, pre.SHA64
CANON = "JSON_SORTED_COMPACT_ASCII_V1"
SCHEMA = "RW106_C1_COMMIT_REVEAL_COMMITMENT_V1"
STATUS = "COMMITTED_AWAITING_PRODUCER_RAW"
CHANNEL = "GPT_NATIVE_NEW_CHAT_OUTSIDE_LF_PROJECT"
MAX_BUNDLE_BYTES = 4 * 1024 * 1024
CHUNK = 1800
PUBLIC_FIELDS = {
    "schema_version", "checkpoint", "status", "attempt_ref",
    "source_snapshot_commit", "source_policy_git_blob", "canonicalization",
    "holdout_counts", "holdout_content_sha256", "holdout_manifest_sha256",
    "reviewer_channel", "reviewer_locator_sha256", "owner_declaration_sha256",
    "handshake_nonce", "handshake_sha256", "reviewer_reported_utc",
    "case_bodies_revealed", "producer_raw_observed",
    "separate_reviewer_evidence_verified", "provider_attested",
    "independent_review", "checkpoint_done",
}
FALSE_FLAGS = (
    "case_bodies_revealed", "producer_raw_observed",
    "separate_reviewer_evidence_verified", "provider_attested",
    "independent_review", "checkpoint_done",
)
BUNDLE_LINE = re.compile(
    r"RW106B\|(corpus|manifest)\|([0-9]{1,4})/([0-9]{1,4})\|"
    r"([A-Za-z0-9+/=]*)\|([0-9a-f]{8})"
)


class CommitRevealGap(ValueError):
    pass


def check(ok, code):
    if not ok:
        raise CommitRevealGap(code)


# ---------------------------------------------------------------- canonical form
def _no_number(_value):
    raise CommitRevealGap("NON_INTEGER_NUMBER_FORBIDDEN")


def parse_json(raw: bytes):
    try:
        return json.loads(raw.decode("utf-8"), parse_float=_no_number,
                          parse_constant=_no_number)
    except CommitRevealGap:
        raise
    except (UnicodeError, ValueError) as exc:
        raise CommitRevealGap("PRIVATE_JSON_INVALID") from exc


def canonical_bytes(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("ascii")


def canonical_digest(obj) -> str:
    return hashlib.sha256(canonical_bytes(obj)).hexdigest()


# ---------------------------------------------------------------- sealed bundle
def _crc(text: str) -> str:
    return format(zlib.crc32(text.encode("ascii")) & 0xFFFFFFFF, "08x")


def encode_bundle(kind: str, obj) -> list:
    text = base64.b64encode(zlib.compress(canonical_bytes(obj), 9)).decode("ascii")
    parts = [text[i:i + CHUNK] for i in range(0, len(text), CHUNK)] or [""]
    return [f"RW106B|{kind}|{i}/{len(parts)}|{p}|{_crc(p)}"
            for i, p in enumerate(parts, 1)]


def decode_bundle(text: str, kind: str):
    """Whitespace, CRLF and indentation are tolerated; every line is CRC checked."""
    rows, total = {}, None
    for line in text.splitlines():
        match = BUNDLE_LINE.fullmatch(line.strip())
        if match is None or match.group(1) != kind:
            continue
        index, count, chunk, crc = (int(match.group(2)), int(match.group(3)),
                                    match.group(4), match.group(5))
        check(count >= 1 and 1 <= index <= count, "BUNDLE_INDEX_INVALID")
        check(total in (None, count), "BUNDLE_TOTAL_INCONSISTENT")
        total = count
        check(_crc(chunk) == crc, "BUNDLE_CHUNK_CRC_MISMATCH")
        check(rows.get(index, chunk) == chunk, "BUNDLE_CHUNK_CONFLICT")
        rows[index] = chunk
    check(total is not None and sorted(rows) == list(range(1, total + 1)),
          "BUNDLE_INCOMPLETE")
    try:
        packed = base64.b64decode("".join(rows[i] for i in sorted(rows)),
                                  validate=True)
        inflater = zlib.decompressobj()
        raw = inflater.decompress(packed, MAX_BUNDLE_BYTES + 1)
    except (ValueError, zlib.error) as exc:
        raise CommitRevealGap("BUNDLE_DECODE_FAILED") from exc
    check(len(raw) <= MAX_BUNDLE_BYTES and not inflater.unconsumed_tail,
          "BUNDLE_TOO_LARGE")
    check(inflater.eof, "BUNDLE_TRUNCATED")
    return parse_json(raw)


# ---------------------------------------------------------------- handshake
def handshake_digest(nonce: str) -> str:
    return hashlib.sha256(("RW106-C1-HANDSHAKE:" + nonce).encode("utf-8")).hexdigest()


def challenge() -> dict:
    nonce = secrets.token_hex(16)
    return {"nonce": nonce, "expected_sha256": handshake_digest(nonce)}


# ---------------------------------------------------------------- public commitment
def secret_key_in_public(obj) -> bool:
    return pre.secret_key_in_public(obj)


def validate_commitment(obj) -> dict:
    check(isinstance(obj, dict), "COMMITMENT_NOT_OBJECT")
    check(not secret_key_in_public(obj), "SECRET_MATERIAL_IN_PUBLIC_GIT")
    check(set(obj) == PUBLIC_FIELDS, "PUBLIC_COMMITMENT_FIELDS_NOT_ALLOWLISTED")
    check(obj["schema_version"] == SCHEMA, "COMMITMENT_SCHEMA_INVALID")
    check(obj["checkpoint"] == "RW1-06_C1", "CHECKPOINT_MISMATCH")
    check(obj["status"] == STATUS, "PREMATURE_COMMITMENT_ADMISSION")
    check(obj["source_snapshot_commit"] == SOURCE
          and obj["source_policy_git_blob"] == POLICY, "SOURCE_POLICY_MISMATCH")
    check(obj["canonicalization"] == CANON, "CANONICALIZATION_UNSUPPORTED")
    check(obj["reviewer_channel"] == CHANNEL, "REVIEWER_CHANNEL_UNSUPPORTED")
    check(isinstance(obj["attempt_ref"], str)
          and seal.ATTEMPT.fullmatch(obj["attempt_ref"]) is not None,
          "ATTEMPT_REF_INVALID")
    counts = obj["holdout_counts"]
    check(isinstance(counts, dict)
          and set(counts) == {"valid", "invalid", "novel_falsifiers"}
          and all(type(v) is int for v in counts.values()), "COUNT_CONTRACT_MISSING")
    check(counts["valid"] >= 12 and counts["invalid"] >= 24
          and counts["novel_falsifiers"] >= 2, "HOLDOUT_MINIMUM_NOT_MET")
    for field in ("holdout_content_sha256", "holdout_manifest_sha256",
                  "reviewer_locator_sha256", "owner_declaration_sha256",
                  "handshake_sha256"):
        check(isinstance(obj[field], str) and SHA64.fullmatch(obj[field]) is not None,
              "COMMITMENT_HASH_MISSING_OR_INVALID")
    check(obj["holdout_content_sha256"] != obj["holdout_manifest_sha256"],
          "DIGESTS_IDENTICAL")
    nonce = obj["handshake_nonce"]
    check(isinstance(nonce, str) and re.fullmatch(r"[0-9a-f]{32}", nonce) is not None
          and handshake_digest(nonce) == obj["handshake_sha256"],
          "HANDSHAKE_NOT_VERIFIED")
    stamp = obj["reviewer_reported_utc"]
    check(isinstance(stamp, str) and stamp.endswith("Z"), "REPORTED_TIMESTAMP_MISSING")
    try:
        datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError as exc:
        raise CommitRevealGap("REPORTED_TIMESTAMP_INVALID") from exc
    for flag in FALSE_FLAGS:
        check(obj[flag] is False, "SELF_ATTESTED_COMPLETION_FORBIDDEN")
    return obj


def _is_ancestor(root, older, newer) -> bool:
    return subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", older, newer],
        capture_output=True, timeout=10, check=False).returncode == 0


def check_commitment(root, commit, path, raw_commit=None):
    """Return (verdict, commitment). Reads the exact Git blob; trusts no timestamp."""
    try:
        obj = pre.read_git_json(root, commit, path)
    except pre.PrecommitGap as exc:
        raise CommitRevealGap(str(exc)) from exc
    validate_commitment(obj)
    match = re.fullmatch(r"github://([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([a-f0-9]{40})/(.+)",
                         obj["attempt_ref"])
    check(match is not None and match.group(1) == REPO
          and match.group(3) == ATTEMPT_PATH, "ATTEMPT_REF_INVALID")
    attempt_commit = match.group(2)
    try:
        attempt = pre.read_git_json(root, attempt_commit, ATTEMPT_PATH)
    except pre.PrecommitGap as exc:
        raise CommitRevealGap(str(exc)) from exc
    check(attempt.get("schema_version") == "RW106_C1_CAPTURE_ATTEMPT_V2"
          and attempt.get("source_snapshot_commit") == SOURCE
          and attempt.get("source_policy_git_blob") == POLICY
          and attempt.get("status") == "PREPARATION_ONLY"
          and attempt.get("holdout_generated") is False
          and attempt.get("checkpoint_done") is False,
          "ATTEMPT_SOURCE_OR_STAGE_INVALID")
    check(attempt_commit != commit, "COMMITMENT_NOT_AFTER_ATTEMPT")
    check(_is_ancestor(root, attempt_commit, commit), "ATTEMPT_NOT_ANCESTOR_OF_COMMITMENT")
    chronology = "PENDING_NO_PRODUCER_RAW"
    if raw_commit is not None:
        check(SHA40.fullmatch(raw_commit) is not None, "PRODUCER_RAW_COMMIT_INVALID")
        check(raw_commit != commit, "RAW_EQUALS_COMMITMENT")
        check(_is_ancestor(root, commit, raw_commit), "PRECOMMIT_NOT_BEFORE_PRODUCER_RAW")
        chronology = "GIT_COMMIT_ANCESTRY_PASS"
    verdict = {
        "schema_version": "RW106_C1_COMMIT_REVEAL_VERDICT_V1",
        "checkpoint": "RW1-06_C1",
        "structure": "PASS_EXACT_ALLOWLIST_AND_MINIMA",
        "chronology": chronology,
        "content_integrity": "NOT_CHECKED_UNTIL_REVEAL",
        "reviewer_separation_verified": False,
        "provider_attested": False,
        "independent_review": False,
        "checkpoint_done": False,
        "material_admission": "GAP_PENDING_OWNER_DECISION_D1",
    }
    return verdict, obj


def verify_reveal(root, commit, path, raw_commit, bundle_text):
    check(raw_commit is not None, "REVEAL_REQUIRES_RAW_AFTER_COMMITMENT")
    verdict, obj = check_commitment(root, commit, path, raw_commit)
    corpus = decode_bundle(bundle_text, "corpus")
    manifest = decode_bundle(bundle_text, "manifest")
    check(canonical_digest(corpus) == obj["holdout_content_sha256"],
          "HOLDOUT_INTEGRITY_GAP:CONTENT_HASH_MISMATCH")
    check(canonical_digest(manifest) == obj["holdout_manifest_sha256"],
          "HOLDOUT_INTEGRITY_GAP:MANIFEST_HASH_MISMATCH")
    try:
        counts = seal.inspect(canonical_bytes(corpus), canonical_bytes(manifest),
                              obj["attempt_ref"])
    except seal.SealError as exc:
        raise CommitRevealGap("REVEAL_STRUCTURE_INVALID:" + str(exc)) from exc
    check(counts == obj["holdout_counts"], "REVEAL_COUNT_MISMATCH")
    verdict = dict(verdict)
    verdict.update({
        "content_integrity": "PASS_CANONICAL_SHA256_MATCHES_PRECOMMIT",
        "revealed_counts": counts,
        "secret_case_bodies_printed": False,
    })
    return verdict


# ---------------------------------------------------------------- reviewer-side code
REVIEWER_FINALIZE = '''
def _canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("ascii")


def finalize(corpus, manifest, attempt_ref, out_path="/mnt/data/rw106_c1_sealed_bundle.txt"):
    corpus_bytes, manifest_bytes = _canon(corpus), _canon(manifest)
    counts = inspect(corpus_bytes, manifest_bytes, attempt_ref)  # raises on any gap
    lines = []
    for kind, raw in (("corpus", corpus_bytes), ("manifest", manifest_bytes)):
        text = base64.b64encode(zlib.compress(raw, 9)).decode("ascii")
        parts = [text[i:i + 1800] for i in range(0, len(text), 1800)] or [""]
        for number, part in enumerate(parts, 1):
            crc = format(zlib.crc32(part.encode("ascii")) & 0xFFFFFFFF, "08x")
            lines.append("RW106B|%s|%d/%d|%s|%s" % (kind, number, len(parts), part, crc))
    with open(out_path, "w", encoding="ascii", newline="\\n") as handle:
        handle.write("\\n".join(lines) + "\\n")
    print("RW106-COMMIT-BLOCK-BEGIN")
    print(json.dumps({
        "holdout_counts": counts,
        "holdout_content_sha256": hashlib.sha256(corpus_bytes).hexdigest(),
        "holdout_manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "reviewer_reported_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "bundle_file": out_path,
    }, indent=2, sort_keys=True))
    print("RW106-COMMIT-BLOCK-END")
'''


def reviewer_snippet() -> str:
    """Standalone reviewer checker, extracted verbatim from the existing sealer so
    the reviewer validates with the very same rules the verifier applies."""
    source = (HERE / "seal_rw106_c1_gpg_v2.py").read_text(encoding="utf-8")
    assigned, defined = {"SOURCE", "POLICY", "FAMILIES", "ATTEMPT"}, {
        "SealError", "require", "private_doc", "inspect"}
    parts = []
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name) \
                and node.targets[0].id in assigned:
            parts.append(ast.get_source_segment(source, node))
        elif isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in defined:
            parts.append(ast.get_source_segment(source, node))
    check(len(parts) == len(assigned) + len(defined), "REVIEWER_SNIPPET_EXTRACTION_GAP")
    header = ("import base64, hashlib, json, re, zlib\n"
              "from datetime import datetime, timezone\n\n")
    return header + "\n\n\n".join(parts) + "\n\n" + REVIEWER_FINALIZE.strip("\n") + "\n"


PINNED = "76924bbb8a1ede147412cdd1be8f98619b659776"
PINNED_SOURCES = (
    ("docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json",
     "138efc3285ee5226c107827c66f84ced6be4afcb"),
    ("docs/programming-agent/router_wave/RW1_06_C1_INDEPENDENT_HOLDOUT_HANDOFF_V1.md",
     "d0ae33254f875f45081b56cfbe7506bdadfef477"),
    ("docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md",
     "4bb64d568c3f005cf454fb223b4a5ed699c34504"),
)


def pinned_blobs_status() -> str:
    """Re-read every pinned blob from Git; never trust the constants above."""
    root = HERE.parents[2]
    probe = subprocess.run(["git", "-C", str(root), "cat-file", "-e", PINNED + "^{commit}"],
                           capture_output=True, check=False)
    if probe.returncode != 0:
        return "NOT_VERIFIED_PINNED_COMMIT_ABSENT_LOCALLY"
    for path, blob in PINNED_SOURCES:
        actual = subprocess.run(["git", "-C", str(root), "rev-parse", f"{PINNED}:{path}"],
                                capture_output=True, text=True, check=False)
        check(actual.returncode == 0 and actual.stdout.strip() == blob,
              "PINNED_SOURCE_BLOB_MISMATCH:" + path)
    return "VERIFIED_AGAINST_GIT"


SOURCE_OPEN, SOURCE_CLOSE = "<<<FUENTE", "<<<FIN_FUENTE>>>"


def pinned_available(root=None) -> bool:
    root = Path(root) if root else HERE.parents[2]
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", PINNED + "^{commit}"],
                          capture_output=True, check=False).returncode == 0


def source_pack_text(root=None) -> str:
    """Public sources as readable text, each blob re-verified against Git here, so the
    reviewer (whose Python sandbox has no network) needs no download."""
    root = Path(root) if root else HERE.parents[2]
    blocks = []
    for path, blob in PINNED_SOURCES:
        shown = subprocess.run(["git", "-C", str(root), "show", f"{PINNED}:{path}"],
                               capture_output=True, check=False)
        check(shown.returncode == 0, "PINNED_SOURCES_UNAVAILABLE")
        raw = shown.stdout
        check(hashlib.sha1(b"blob %d\0" % len(raw) + raw).hexdigest() == blob,
              "PINNED_SOURCE_BLOB_MISMATCH:" + path)
        try:
            text = raw.decode("utf-8")
        except UnicodeError as exc:
            raise CommitRevealGap("PINNED_SOURCE_NOT_UTF8:" + path) from exc
        check(SOURCE_OPEN not in text and SOURCE_CLOSE not in text,
              "SOURCE_DELIMITER_COLLISION:" + path)
        body = text if text.endswith("\n") else text + "\n"
        blocks.append(f"{SOURCE_OPEN} ruta={path} git_blob={blob} bytes={len(raw)}>>>\n"
                      f"{body}{SOURCE_CLOSE}")
    return "\n".join(blocks)


PART_LIMIT = 15000  # ChatGPT truncated a single 30 KB paste at exactly 20,000 chars


def build_generate_parts(attempt_ref: str) -> list:
    """Same generate prompt split into 3 messages that each stay far below the paste limit."""
    full = build_prompt("generate", attempt_ref=attempt_ref)
    third = full.index(SOURCE_OPEN, full.index(SOURCE_OPEN, full.index(SOURCE_OPEN) + 1) + 1)
    step2 = full.index("\n2. Redacta")
    cuts = [full[:third], full[third:step2], full[step2:]]
    total = len(cuts)
    out = []
    for i, body in enumerate(cuts, 1):
        if i < total:
            head = (f"PARTE {i}/{total} de un único encargo. SOLO recíbela: no ejecutes nada ni redactes "
                    f"casos todavía. Comprueba que el texto termina con el marcador "
                    f"<<<FIN_PARTE {i}/{total}>>>; si falta o está cortado responde PARTE_{i}_TRUNCADA. "
                    f"Si no, responde únicamente RECIBIDA_{i}_DE_{total}.\n\n")
        else:
            head = (f"PARTE {i}/{total} (final). Comprueba que el texto termina con <<<FIN_PARTE {i}/{total}>>> "
                    f"y que tienes las PARTES 1 y 2 completas (las tres fuentes con su <<<FIN_FUENTE>>>). "
                    f"Si algo falta o está cortado responde PARTE_TRUNCADA o FUENTE_NO_VERIFICADA y detente. "
                    f"Si todo está completo, ejecuta el encargo completo (reglas y pasos 1-5).\n\n")
        text = head + body.rstrip("\n") + f"\n<<<FIN_PARTE {i}/{total}>>>\n"
        check(len(text) < PART_LIMIT, f"PART_{i}_TOO_LONG:{len(text)}")
        out.append(text)
    return out


def parse_source_pack(text: str) -> dict:
    """Parse the inline source pack and re-derive each git blob sha1 from the text."""
    found = {}
    pattern = re.compile(re.escape(SOURCE_OPEN) + r" ruta=(\S+) git_blob=([0-9a-f]{40}) bytes=(\d+)>>>\n"
                         r"(.*?)" + re.escape(SOURCE_CLOSE), re.S)
    for path, blob, size, body in pattern.findall(text):
        raw = body.encode("utf-8")
        check(len(raw) >= int(size) and len(raw) <= int(size) + 1, "SOURCE_PACK_SIZE_MISMATCH:" + path)
        for candidate in (raw, raw[:-1]):  # trailing newline added when the file lacked one
            if hashlib.sha1(b"blob %d\0" % len(candidate) + candidate).hexdigest() == blob:
                found[path] = blob
                break
        else:
            raise CommitRevealGap("SOURCE_PACK_BLOB_MISMATCH:" + path)
    return found


def build_prompt(stage: str, nonce: str = "", attempt_ref: str = "") -> str:
    if stage == "handshake":
        check(re.fullmatch(r"[0-9a-f]{32}", nonce or "") is not None, "NONCE_REQUIRED")
        return (
            "Esta es una conversación NUEVA de revisión independiente. Antes de nada:\n"
            "1) Con tu herramienta de Python calcula el SHA-256 hexadecimal de la cadena "
            f"exacta `RW106-C1-HANDSHAKE:{nonce}` y responde con ese hexadecimal.\n"
            "2) Responde SI o NO: ¿esta conversación está dentro de un Proyecto de ChatGPT, "
            "o tiene Memoria / historial de otros chats activado y visible para ti?\n"
            "No hagas nada más."
        )
    check(stage == "generate", "UNKNOWN_PROMPT_STAGE")
    check(seal.ATTEMPT.fullmatch(attempt_ref or "") is not None, "ATTEMPT_REF_INVALID")
    sources = source_pack_text()
    return f"""Eres el REVISOR INDEPENDIENTE del checkpoint RW1-06_C1 en una conversación aislada.
Reglas de aislamiento: no uses ni pidas contexto de otras conversaciones; si ves contexto de un proyecto LF, memoria o chats previos, responde solo CONTEXTO_CONTAMINADO y detente. No conoces al productor ni sus salidas.

1. FUENTES. Usa SOLO las tres fuentes públicas de abajo (repositorio {REPO}, commit fijado {PINNED}). El productor ya verificó el blob git de cada una contra el repositorio; tu herramienta de Python no tiene internet y no necesitas descargar nada. Léelas completas. Si el bloque falta, está cortado o no puedes leerlo, responde FUENTE_NO_VERIFICADA y detente.
{sources}
2. Redacta un corpus NUEVO y SECRETO (mínimo 13 VALID, 26 INVALID, 2 FALSIFIER novedosos; cubre las 13 familias F01-F13 del archivo de política) y un manifiesto de oráculos con la acción esperada y severidad por caso, definidos ANTES de que exista cualquier salida del productor. No reutilices casos H01-H12 de RW1-01.
3. Esquemas exactos (JSON): corpus = {{"schema_version":"RW106_C1_CORPUS_PRIVATE_V2","source_snapshot_commit":"{SOURCE}","source_policy_git_blob":"{POLICY}","attempt_ref":"{attempt_ref}","cases":[{{"case_id":"...","family_id":"F01","kind":"VALID|INVALID|FALSIFIER","input":"..."}}]}}; manifiesto = {{"schema_version":"RW106_C1_MANIFEST_PRIVATE_V2","source_snapshot_commit":"{SOURCE}","source_policy_git_blob":"{POLICY}","attempt_ref":"{attempt_ref}","private_nonce":"<secrets.token_hex(16)>","oracles_declared_before_producer_raw":true,"producer_raw_observed":false,"oracles":[{{"case_id":"...","expected_action":"...","severity":"LOW|MEDIUM|HIGH|CRITICAL"}}]}}. Solo enteros, sin números decimales.
4. Ejecuta con tu herramienta de Python este código EXACTO, define `corpus` y `manifest` como dict y llama a `finalize(corpus, manifest, ATTEMPT_REF)`. Si lanza error, corrige y repite; no entregues nada hasta que pase:
```python
ATTEMPT_REF = "{attempt_ref}"
{reviewer_snippet()}```
5. Entrega SOLO: (a) el bloque entre RW106-COMMIT-BLOCK-BEGIN y RW106-COMMIT-BLOCK-END tal cual lo imprimió el código; (b) el enlace de descarga del archivo generado. NO muestres casos, oráculos ni el nonce en texto legible. Conserva este chat: es tu custodia hasta la revelación."""


# ---------------------------------------------------------------- self-test
def _synthetic(attempt_ref, valid=13, invalid=26, falsifiers=2, **overrides):
    """Mechanics fixture. Deliberately meaningless: NOT a holdout, NOT a Router case."""
    plan = [("VALID", valid), ("INVALID", invalid), ("FALSIFIER", falsifiers)]
    cases, oracles, number = [], [], 0
    for kind, amount in plan:
        for _ in range(amount):
            number += 1
            ident = f"SYN-{number:03d}"
            cases.append({"case_id": ident, "family_id": f"F{(number - 1) % 13 + 1:02d}",
                          "kind": kind, "input": f"SYNTHETIC_MECHANICS_ONLY_{number}"})
            oracles.append({"case_id": ident, "expected_action": "SYNTHETIC",
                            "severity": "LOW"})
    corpus = {"schema_version": "RW106_C1_CORPUS_PRIVATE_V2",
              "source_snapshot_commit": SOURCE, "source_policy_git_blob": POLICY,
              "attempt_ref": attempt_ref, "cases": cases}
    manifest = {"schema_version": "RW106_C1_MANIFEST_PRIVATE_V2",
                "source_snapshot_commit": SOURCE, "source_policy_git_blob": POLICY,
                "attempt_ref": attempt_ref, "private_nonce": secrets.token_hex(16),
                "oracles_declared_before_producer_raw": True,
                "producer_raw_observed": False, "oracles": oracles}
    manifest.update(overrides.get("manifest", {}))
    corpus.update(overrides.get("corpus", {}))
    return corpus, manifest


def _commitment(attempt_ref, corpus, manifest, counts):
    nonce = secrets.token_hex(16)
    return {
        "schema_version": SCHEMA, "checkpoint": "RW1-06_C1", "status": STATUS,
        "attempt_ref": attempt_ref, "source_snapshot_commit": SOURCE,
        "source_policy_git_blob": POLICY, "canonicalization": CANON,
        "holdout_counts": counts,
        "holdout_content_sha256": canonical_digest(corpus),
        "holdout_manifest_sha256": canonical_digest(manifest),
        "reviewer_channel": CHANNEL,
        "reviewer_locator_sha256": hashlib.sha256(b"SYNTHETIC_PRIVATE_URL").hexdigest(),
        "owner_declaration_sha256": hashlib.sha256(b"SYNTHETIC_DECLARATION").hexdigest(),
        "handshake_nonce": nonce, "handshake_sha256": handshake_digest(nonce),
        "reviewer_reported_utc": "2026-10-22T09:00:00Z",
        **{flag: False for flag in FALSE_FLAGS},
    }


def _expect(code, func, *args):
    try:
        func(*args)
    except CommitRevealGap as exc:
        check(str(exc) == code, f"WRONG_CODE:{exc}!={code}")
        return str(exc)
    raise AssertionError("FALSE_ACCEPT:" + code)


def self_test() -> dict:
    rejected = {}
    with tempfile.TemporaryDirectory(prefix="rw106_commit_reveal_") as tmp:
        root = Path(tmp)

        def git(*args):
            return pre.git(root, *args).decode("utf-8").strip()

        git("init", "-q")
        git("config", "user.name", "RW106 SELFTEST")
        git("config", "user.email", "selftest@example.invalid")

        def commit_file(path, obj, message):
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(obj, sort_keys=True) + "\n", encoding="utf-8")
            git("add", path)
            git("commit", "-qm", message)
            return git("rev-parse", "HEAD")

        attempt_obj = {"schema_version": "RW106_C1_CAPTURE_ATTEMPT_V2",
                       "checkpoint": "RW1-06_C1", "status": "PREPARATION_ONLY",
                       "source_snapshot_commit": SOURCE, "source_policy_git_blob": POLICY,
                       "holdout_generated": False, "checkpoint_done": False}
        attempt_sha = commit_file(ATTEMPT_PATH, attempt_obj, "attempt")
        branch = git("rev-parse", "--abbrev-ref", "HEAD")
        attempt_ref = f"github://{REPO}@{attempt_sha}/{ATTEMPT_PATH}"
        public_path = pre.PREFIX + "RW1_06_C1_COMMIT_REVEAL_FIXTURE.json"

        # Reviewer side: run the EXACT standalone snippet in a clean namespace.
        corpus, manifest = _synthetic(attempt_ref)
        namespace = {}
        exec(compile(reviewer_snippet(), "reviewer_snippet", "exec"), namespace)
        bundle_path = root / "sealed_bundle.txt"
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            namespace["finalize"](corpus, manifest, attempt_ref, str(bundle_path))
        printed = buffer.getvalue()
        block = json.loads(printed.split("RW106-COMMIT-BLOCK-BEGIN\n")[1]
                           .split("\nRW106-COMMIT-BLOCK-END")[0])
        check(block["holdout_content_sha256"] == canonical_digest(corpus)
              and block["holdout_manifest_sha256"] == canonical_digest(manifest),
              "REVIEWER_VERIFIER_DIGEST_DISAGREEMENT")
        check("SYNTHETIC_MECHANICS_ONLY" not in printed, "REVIEWER_PRINTED_CASE_BODY")
        bundle_text = bundle_path.read_text(encoding="ascii")

        # Reviewer snippet fails closed on an insufficient corpus (nothing printed).
        weak_corpus, weak_manifest = _synthetic(attempt_ref, valid=11)
        quiet = io.StringIO()
        with contextlib.redirect_stdout(quiet):
            try:
                namespace["finalize"](weak_corpus, weak_manifest, attempt_ref,
                                      str(root / "weak.txt"))
            except Exception as exc:  # noqa: BLE001 - asserting any fail-closed error
                check(str(exc) == "CASE_MINIMUM_GAP", "REVIEWER_SNIPPET_WRONG_CODE")
            else:
                raise AssertionError("FALSE_ACCEPT:reviewer_snippet_weak_corpus")
        check(quiet.getvalue() == "" and not (root / "weak.txt").exists(),
              "REVIEWER_EMITTED_ON_FAILURE")
        rejected["reviewer_snippet_insufficient_corpus"] = "CASE_MINIMUM_GAP"

        # Producer side: public commitment, then RAW strictly after.
        commitment = _commitment(attempt_ref, corpus, manifest, block["holdout_counts"])
        commit_sha = commit_file(public_path, commitment, "public commitment")
        raw_sha = commit_file(pre.PREFIX + "RW1_06_C2_RAW_FIXTURE.json",
                              {"fixture": "synthetic producer raw"}, "producer raw")

        verdict, _ = check_commitment(root, commit_sha, public_path)
        check(verdict["chronology"] == "PENDING_NO_PRODUCER_RAW", "POSITIVE_PENDING_FAILED")
        verdict, _ = check_commitment(root, commit_sha, public_path, raw_sha)
        check(verdict["chronology"] == "GIT_COMMIT_ANCESTRY_PASS", "POSITIVE_ORDER_FAILED")
        final = verify_reveal(root, commit_sha, public_path, raw_sha, bundle_text)
        check(final["content_integrity"].startswith("PASS")
              and final["revealed_counts"] == {"valid": 13, "invalid": 26,
                                               "novel_falsifiers": 2}
              and final["independent_review"] is False
              and final["provider_attested"] is False
              and final["checkpoint_done"] is False
              and final["reviewer_separation_verified"] is False,
              "POSITIVE_REVEAL_FAILED")
        messy = "\r\n".join("   > ".replace("> ", "") + line for line in bundle_text.splitlines())
        check(verify_reveal(root, commit_sha, public_path, raw_sha, messy)
              ["content_integrity"].startswith("PASS"), "PASTE_ROBUSTNESS_FAILED")

        # Chronology negatives.
        rejected["reveal_without_raw"] = _expect(
            "REVEAL_REQUIRES_RAW_AFTER_COMMITMENT", verify_reveal, root, commit_sha,
            public_path, None, bundle_text)
        rejected["raw_equals_commitment"] = _expect(
            "RAW_EQUALS_COMMITMENT", check_commitment, root, commit_sha, public_path, commit_sha)
        git("checkout", "-q", "-b", "side", attempt_sha)
        early_raw = commit_file(pre.PREFIX + "RW1_06_C2_EARLY_RAW_FIXTURE.json",
                                {"fixture": "raw not descending from commitment"}, "early raw")
        git("checkout", "-q", branch)
        rejected["raw_not_after_commitment"] = _expect(
            "PRECOMMIT_NOT_BEFORE_PRODUCER_RAW", check_commitment, root, commit_sha,
            public_path, early_raw)
        rejected["raw_commit_invalid"] = _expect(
            "PRODUCER_RAW_COMMIT_INVALID", check_commitment, root, commit_sha,
            public_path, "xyz")
        check(commit_sha != attempt_sha, "FIXTURE_ORDER_BROKEN")
        # attempt_ref must resolve to a genuine PREPARATION_ONLY attempt, not a tampered one.
        bad_attempt = commit_file(ATTEMPT_PATH, {**attempt_obj, "holdout_generated": True},
                                  "tampered attempt")
        lineage = _commitment(f"github://{REPO}@{bad_attempt}/{ATTEMPT_PATH}",
                              corpus, manifest, block["holdout_counts"])
        lineage_path = pre.PREFIX + "RW1_06_C1_FIXTURE_LINEAGE.json"
        lineage_sha = commit_file(lineage_path, lineage, "lineage")
        rejected["attempt_ref_to_tampered_attempt"] = _expect(
            "ATTEMPT_SOURCE_OR_STAGE_INVALID", check_commitment, root, lineage_sha, lineage_path)

        # Integrity negatives (reveal after RAW).
        tampered = copy.deepcopy(corpus)
        tampered["cases"][0]["input"] += " "
        rejected["tampered_corpus"] = _expect(
            "HOLDOUT_INTEGRITY_GAP:CONTENT_HASH_MISMATCH", verify_reveal, root, commit_sha,
            public_path, raw_sha,
            "\n".join(encode_bundle("corpus", tampered) + encode_bundle("manifest", manifest)))
        tampered_manifest = copy.deepcopy(manifest)
        tampered_manifest["oracles"][0]["severity"] = "HIGH"
        rejected["tampered_manifest"] = _expect(
            "HOLDOUT_INTEGRITY_GAP:MANIFEST_HASH_MISMATCH", verify_reveal, root, commit_sha,
            public_path, raw_sha,
            "\n".join(encode_bundle("corpus", corpus) + encode_bundle("manifest", tampered_manifest)))
        lines = bundle_text.splitlines()
        first = next(i for i, ln in enumerate(lines) if ln.startswith("RW106B|corpus|1/"))
        head, body, crc = lines[first].rsplit("|", 2)
        flipped = ("A" if body[0] != "A" else "B") + body[1:]
        corrupt = list(lines)
        corrupt[first] = "|".join((head, flipped, crc))
        rejected["corrupt_chunk"] = _expect(
            "BUNDLE_CHUNK_CRC_MISMATCH", verify_reveal, root, commit_sha, public_path,
            raw_sha, "\n".join(corrupt))
        rejected["missing_manifest"] = _expect(
            "BUNDLE_INCOMPLETE", verify_reveal, root, commit_sha, public_path, raw_sha,
            "\n".join(ln for ln in lines if "|manifest|" not in ln))
        bomb = base64.b64encode(zlib.compress(b"0" * (MAX_BUNDLE_BYTES + 10), 9)).decode()
        rejected["decompression_bomb"] = _expect(
            "BUNDLE_TOO_LARGE", decode_bundle,
            f"RW106B|corpus|1/1|{bomb}|{_crc(bomb)}", "corpus")
        rejected["non_integer_number"] = _expect(
            "NON_INTEGER_NUMBER_FORBIDDEN", parse_json, b'{"x": 1.5}')

        # Structure negatives: honest commitment over a deficient or mis-bound reveal.
        def revealed(case_corpus, case_manifest, counts, label):
            body = _commitment(attempt_ref, case_corpus, case_manifest, counts)
            sha = commit_file(pre.PREFIX + f"RW1_06_C1_FIXTURE_{label}.json", body, label)
            later = commit_file(pre.PREFIX + f"RW1_06_C2_RAW_{label}.json", {"f": label}, label)
            text = "\n".join(encode_bundle("corpus", case_corpus)
                             + encode_bundle("manifest", case_manifest))
            return sha, later, text

        fixed = {"valid": 13, "invalid": 26, "novel_falsifiers": 2}
        weak_c, weak_m = _synthetic(attempt_ref, valid=11)
        sha, later, text = revealed(weak_c, weak_m, fixed, "WEAK")
        rejected["reveal_below_minimum"] = _expect(
            "REVEAL_STRUCTURE_INVALID:CASE_MINIMUM_GAP", verify_reveal, root, sha,
            pre.PREFIX + "RW1_06_C1_FIXTURE_WEAK.json", later, text)
        sha, later, text = revealed(*_synthetic(attempt_ref, valid=12), fixed, "COUNT")
        rejected["reveal_count_mismatch"] = _expect(
            "REVEAL_COUNT_MISMATCH", verify_reveal, root, sha,
            pre.PREFIX + "RW1_06_C1_FIXTURE_COUNT.json", later, text)
        late_c, late_m = _synthetic(attempt_ref, manifest={
            "oracles_declared_before_producer_raw": False})
        sha, later, text = revealed(late_c, late_m, fixed, "LATE")
        rejected["oracles_not_preregistered"] = _expect(
            "REVEAL_STRUCTURE_INVALID:ORACLE_TIMING_GAP", verify_reveal, root, sha,
            pre.PREFIX + "RW1_06_C1_FIXTURE_LATE.json", later, text)
        other = f"github://{REPO}@{'0' * 40}/{ATTEMPT_PATH}"
        wrong_c, wrong_m = _synthetic(other)
        sha, later, text = revealed(wrong_c, wrong_m, fixed, "ATTEMPT")
        rejected["reveal_bound_to_other_attempt"] = _expect(
            "REVEAL_STRUCTURE_INVALID:ATTEMPT_REF_MISMATCH", verify_reveal, root, sha,
            pre.PREFIX + "RW1_06_C1_FIXTURE_ATTEMPT.json", later, text)

    # Public-commitment mutants (no Git needed).
    base = _commitment(f"github://{REPO}@{'1' * 40}/{ATTEMPT_PATH}",
                       *_synthetic("x")[:2], {"valid": 13, "invalid": 26, "novel_falsifiers": 2})
    validate_commitment(base)
    mutants = {
        "secret_seed_key": ("SECRET_MATERIAL_IN_PUBLIC_GIT", {"seed": "x"}),
        "secret_alias_field": ("PUBLIC_COMMITMENT_FIELDS_NOT_ALLOWLISTED", {"hidden_cases": 1}),
        "stale_source": ("SOURCE_POLICY_MISMATCH", {"source_snapshot_commit": "0" * 40}),
        "wrong_policy": ("SOURCE_POLICY_MISMATCH", {"source_policy_git_blob": "0" * 40}),
        "premature_admission": ("PREMATURE_COMMITMENT_ADMISSION", {"status": "ADMITTED"}),
        "shared_channel": ("REVIEWER_CHANNEL_UNSUPPORTED", {"reviewer_channel": "SAME_CHAT"}),
        "unsupported_canonical": ("CANONICALIZATION_UNSUPPORTED", {"canonicalization": "RAW"}),
        "below_minimum": ("HOLDOUT_MINIMUM_NOT_MET",
                          {"holdout_counts": {"valid": 12, "invalid": 23, "novel_falsifiers": 2}}),
        "bool_count": ("COUNT_CONTRACT_MISSING",
                       {"holdout_counts": {"valid": True, "invalid": 26, "novel_falsifiers": 2}}),
        "bad_digest": ("COMMITMENT_HASH_MISSING_OR_INVALID", {"holdout_content_sha256": "zz"}),
        "same_digests": ("DIGESTS_IDENTICAL",
                         {"holdout_manifest_sha256": base["holdout_content_sha256"]}),
        "forged_handshake": ("HANDSHAKE_NOT_VERIFIED", {"handshake_sha256": "0" * 64}),
        "bad_timestamp": ("REPORTED_TIMESTAMP_INVALID", {"reviewer_reported_utc": "notZ-Z"}),
    }
    for flag in FALSE_FLAGS:
        mutants["claims_" + flag] = ("SELF_ATTESTED_COMPLETION_FORBIDDEN", {flag: True})
    for name, (code, change) in mutants.items():
        bad = copy.deepcopy(base)
        bad.update(change)
        rejected[name] = _expect(code, validate_commitment, bad)

    probe_nonce = "a" * 32
    hand = build_prompt("handshake", nonce=probe_nonce)
    check(f"RW106-C1-HANDSHAKE:{probe_nonce}" in hand, "HANDSHAKE_PROMPT_NONCE_MISSING")
    rejected["prompt_without_nonce"] = _expect("NONCE_REQUIRED", build_prompt, "handshake")
    rejected["prompt_bad_attempt"] = _expect("ATTEMPT_REF_INVALID", build_prompt, "generate",
                                             "", "not-a-ref")
    ref = f"github://{REPO}@{'2' * 40}/{ATTEMPT_PATH}"
    gen = build_prompt("generate", attempt_ref=ref)
    for path, blob in PINNED_SOURCES:
        check(path in gen and blob in gen, "GENERATE_PROMPT_SOURCE_MISSING")
    check(parse_source_pack(gen) == dict(PINNED_SOURCES), "GENERATE_PROMPT_SOURCE_PACK_INCOMPLETE")
    check("raw.githubusercontent.com" not in gen, "GENERATE_PROMPT_STILL_NEEDS_NETWORK")
    pos = gen.index(SOURCE_CLOSE) - 40
    tampered = gen[:pos] + ("X" if gen[pos] != "X" else "Y") + gen[pos + 1:]
    first_path = PINNED_SOURCES[0][0]
    rejected["source_pack_tampered"] = _expect(
        "SOURCE_PACK_BLOB_MISMATCH:" + first_path, parse_source_pack, tampered)
    rejected["source_pack_truncated"] = _expect(
        "GENERATE_PROMPT_SOURCE_PACK_INCOMPLETE", lambda t: check(
            parse_source_pack(t) == dict(PINNED_SOURCES), "GENERATE_PROMPT_SOURCE_PACK_INCOMPLETE"),
        gen[:gen.rindex(SOURCE_OPEN)])
    pieces = build_generate_parts(ref)
    check(len(pieces) == 3 and all(len(p) < PART_LIMIT for p in pieces), "PARTS_COUNT_OR_SIZE")
    check(parse_source_pack("".join(pieces)) == dict(PINNED_SOURCES), "PARTS_SOURCE_PACK_INCOMPLETE")
    check("```python" in pieces[2] and "<<<FIN_PARTE 3/3>>>" in pieces[2], "PARTS_FINAL_INCOMPLETE")
    check(all(f"<<<FIN_PARTE {i}/3>>>" in p for i, p in enumerate(pieces, 1)), "PARTS_MARKER_MISSING")
    check("\n".join(p.split("\n\n", 1)[1] for p in pieces).count("Redacta un corpus") == 1, "PARTS_STEP2_DUP")
    code = gen.split("```python\n", 1)[1].split("\n```", 1)[0]
    scope = {}
    exec(compile(code, "prompt_code_block", "exec"), scope)  # the block the reviewer runs
    check(callable(scope.get("finalize")) and scope.get("ATTEMPT_REF") == ref,
          "GENERATE_PROMPT_CODE_NOT_RUNNABLE")
    for forbidden in ("SYNTHETIC_MECHANICS_ONLY", "private_nonce\": \"" + "0" * 16):
        check(forbidden not in gen, "GENERATE_PROMPT_LEAKS_FIXTURE")
    challenge_pair = challenge()
    check(challenge_pair["expected_sha256"] == hashlib.sha256(
        ("RW106-C1-HANDSHAKE:" + challenge_pair["nonce"]).encode()).hexdigest(),
        "HANDSHAKE_DIGEST_MISMATCH")
    return {
        "selftest": "PASS_SYNTHETIC_ONLY",
        "negatives_rejected": rejected,
        "negative_count": len(rejected),
        "reviewer_snippet_roundtrip_with_verifier": True,
        "pinned_source_blobs": pinned_blobs_status(),
        "real_holdout_created": False,
        "real_reviewer_consulted": False,
        "separation_verified": False,
        "provider_attested": False,
        "independent_review": False,
        "checkpoint_done": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("self-test")
    sub.add_parser("challenge", help="new handshake nonce and its expected digest")
    prompt = sub.add_parser("prompt", help="ready-to-paste reviewer prompt")
    prompt.add_argument("stage", choices=["handshake", "generate"])
    prompt.add_argument("--nonce", default="")
    prompt.add_argument("--attempt-ref", default="")
    prompt.add_argument("--part", type=int, default=0, help="generate only: print part N of 3 (0 = whole)")
    chk = sub.add_parser("check-commitment")
    rev = sub.add_parser("verify-reveal")
    for item in (chk, rev):
        item.add_argument("--git-root", type=Path, default=Path("."))
        item.add_argument("--commit", required=True)
        item.add_argument("--path", required=True)
        item.add_argument("--raw-commit")
    rev.add_argument("--bundle", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "self-test":
            result = self_test()
        elif args.command == "challenge":
            result = challenge()
        elif args.command == "prompt":
            if args.stage == "generate" and args.part:
                pieces = build_generate_parts(args.attempt_ref)
                check(1 <= args.part <= len(pieces), "PART_OUT_OF_RANGE")
                print(pieces[args.part - 1], end="")
            else:
                print(build_prompt(args.stage, args.nonce, args.attempt_ref))
            return
        elif args.command == "check-commitment":
            result = check_commitment(args.git_root, args.commit, args.path,
                                      args.raw_commit)[0]
        else:
            result = verify_reveal(args.git_root, args.commit, args.path, args.raw_commit,
                                   args.bundle.read_text(encoding="ascii", errors="strict"))
    except CommitRevealGap as exc:
        print(json.dumps({"verdict": "GAP", "code": str(exc), "checkpoint_done": False},
                         sort_keys=True))
        raise SystemExit(1)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
