#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import sys
from pathlib import Path

MARKERS = [
    "OWNER_LITERAL",
    "OWNER_AMENDMENT",
    "SCREEN_SPEC",
    "AUTHORIZED_SAMPLE_AMOUNTS",
    "SEMANTIC_QA",
    "LF_IDENTITY_TOKENS",
    "FROZEN_ASSETS",
    "NON_NEGOTIABLE",
]
EXPECTED_HEADER = b"SalyNativeInput::F3A_PROMPT_V1\n"
EXPECTED_NON_NEGOTIABLE = (
    b"Preserve the owner literal and governed semantic meaning exactly. "
    b"Do not invent amounts, messages, actions, assets, tokens or scope. "
    b"Use only the supplied screen specification, identity tokens and frozen assets. "
    b"Do not reinterpret the owner literal. Evidence and provider execution are outside F3-A."
)
EXPECTED_CHECK_CODES = {
    "LF_SEM_OFFER_INTENT",
    "LF_SEM_AMOUNT_MEANING",
    "LF_SEM_TRANSFER_MEANING",
    "LF_SEM_LETTER_CONDITION",
    "LF_SEM_SCOPE_AND_ACTION",
}
EXPECTED_FULL_TOKEN_SHA = "6b5f5eea5fe000441a7b774e5e02ec19709da6dd2603e8d6feebb88afc6c22fd"
EXPECTED_SNAPSHOT_SHA = "f4bc5bf450bdfb220191305c134121c266cbd4ff14d8a69910085e4b211914aa"
EXPECTED_ORIGINAL_SHA = "78160d6438c2908d469e9ece838b0a14b57eb317b1215cfb702e507e7bbb1f40"

def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def load_json(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def dec(obj, key):
    return base64.b64decode(obj[key])

def parse_sections(prompt: bytes):
    if not prompt.startswith(EXPECTED_HEADER):
        return None
    pos = len(EXPECTED_HEADER)
    out = {}
    for idx, name in enumerate(MARKERS):
        marker = f"[{name}]\n".encode()
        if prompt[pos:pos+len(marker)] != marker:
            return None
        pos += len(marker)
        if idx + 1 < len(MARKERS):
            next_marker = f"\n[{MARKERS[idx+1]}]\n".encode()
            end = prompt.find(next_marker, pos)
            if end < 0:
                return None
            out[name] = prompt[pos:end]
            pos = end + 1
        else:
            out[name] = prompt[pos:]
            pos = len(prompt)
    return out

def canonical_messages_bytes(messages):
    # PostgreSQL jsonb::text formatting: separators ", " and ": ", booleans lowercase.
    return json.dumps(messages, ensure_ascii=False, sort_keys=True, separators=(", ", ": ")).encode()

def evaluate(prompt: bytes, run: dict, expected: dict, before: dict, after: dict):
    sections = parse_sections(prompt)
    controls = {}

    def put(code, ok, input_desc, evidence):
        controls[code] = {
            "ok": bool(ok),
            "input": input_desc,
            "evidence": evidence,
        }

    if sections is None:
        for n in range(1, 11):
            put(f"F3A-{n:02d}", False, "prompt_structure", "section parse failed")
        return controls

    literal = dec(expected, "literal_b64")
    original_literal = dec(expected, "original_literal_b64")
    amendment = dec(expected, "owner_amendment_b64")
    screen = dec(expected, "screen_spec_b64")
    amounts = dec(expected, "amounts_b64")
    semantic = dec(expected, "semantic_b64")
    tokens = dec(expected, "tokens_b64")
    assets = dec(expected, "assets_b64")
    inputs = dec(expected, "inputs_b64")

    put("F3A-01",
        sections["OWNER_LITERAL"] == literal,
        f"OWNER_LITERAL sha256={sha(sections['OWNER_LITERAL'])}",
        "literal bytes exact" if sections["OWNER_LITERAL"] == literal else "literal bytes differ")

    amounts_obj = json.loads(amounts.decode())
    amount_ok = (
        sections["AUTHORIZED_SAMPLE_AMOUNTS"] == amounts
        and amounts_obj == {
            "term": "por 12 meses",
            "total": "S/ 2,268.00",
            "monthly": "S/ 189.00",
            "illustrative": True,
        }
    )
    put("F3A-02", amount_ok,
        f"AUTHORIZED_SAMPLE_AMOUNTS sha256={sha(sections['AUTHORIZED_SAMPLE_AMOUNTS'])}",
        "monthly/term/total exact" if amount_ok else "authorized amount bytes/meaning changed")

    sem_obj = json.loads(semantic.decode())
    check_codes = {x.get("code") for x in sem_obj.get("checks", [])}
    original_messages = sem_obj.get("original_messages", [])
    original_messages_bytes = dec(expected, "original_messages_b64")
    sem_ok = (
        sections["SEMANTIC_QA"] == semantic
        and len(sem_obj.get("checks", [])) == 5
        and check_codes == EXPECTED_CHECK_CODES
        and all(x.get("severity") == "BLOCK" for x in sem_obj.get("checks", []))
        and json.loads(original_messages_bytes.decode()) == original_messages
        and sem_obj.get("original_request_sha256") == EXPECTED_ORIGINAL_SHA
        and sha(original_messages_bytes) == EXPECTED_ORIGINAL_SHA
    )
    put("F3A-03", sem_ok,
        f"SEMANTIC_QA sha256={sha(sections['SEMANTIC_QA'])};checks={len(sem_obj.get('checks', []))}",
        "5 governed checks + original SHA exact" if sem_ok else "semantic QA bytes/checks/hash changed")

    amendment_obj = json.loads(amendment.decode())
    governed_messages = [
        {"text": original_literal.decode(), "speaker": "USER"},
        {"text": amendment_obj["text"], "speaker": "USER"},
    ]
    governance_ok = (
        sections["OWNER_AMENDMENT"] == amendment
        and original_messages == governed_messages
        and amendment_obj.get("text") == "Los montos deben ser reales no texto"
    )
    put("F3A-04", governance_ok,
        f"OWNER_AMENDMENT sha256={sha(sections['OWNER_AMENDMENT'])}",
        "original literal + owner amendment govern messages" if governance_ok else "message/amendment authority mismatch")

    screen_obj = json.loads(screen.decode())
    screen_ok = (
        sections["SCREEN_SPEC"] == screen
        and screen_obj == {"width": 390, "height": 844, "screen": "TU_OFERTA"}
    )
    put("F3A-05", screen_ok,
        f"SCREEN_SPEC sha256={sha(sections['SCREEN_SPEC'])}",
        "390x844 TU_OFERTA exact" if screen_ok else "screen spec changed")

    token_obj = json.loads(tokens.decode())
    token_ok = (
        sections["LF_IDENTITY_TOKENS"] == tokens
        and len(token_obj) == 109
        and sha(tokens) == EXPECTED_FULL_TOKEN_SHA
        and expected.get("snapshot_sha256") == EXPECTED_SNAPSHOT_SHA
    )
    put("F3A-06", token_ok,
        f"LF_IDENTITY_TOKENS bytes={len(tokens)} sha256={sha(tokens)} count={len(token_obj)}",
        "109-token real context exact" if token_ok else "token manifest/count/hash drift")

    asset_obj = json.loads(assets.decode())
    asset_ok = sections["FROZEN_ASSETS"] == assets and asset_obj == []
    put("F3A-07", asset_ok,
        f"FROZEN_ASSETS sha256={sha(sections['FROZEN_ASSETS'])}",
        "real item requests no asset_codes; exact []" if asset_ok else "unexpected asset refs")

    interp = sem_obj.get("interpretation", {})
    constraints_ok = (
        sections["NON_NEGOTIABLE"] == EXPECTED_NON_NEGOTIABLE
        and isinstance(interp.get("preserve"), list) and len(interp["preserve"]) > 0
        and isinstance(interp.get("excluded"), list) and len(interp["excluded"]) > 0
        and sections["SEMANTIC_QA"] == semantic
    )
    put("F3A-08", constraints_ok,
        f"NON_NEGOTIABLE sha256={sha(sections['NON_NEGOTIABLE'])}",
        "preserve/excluded + non-negotiable exact" if constraints_ok else "semantic constraints changed")

    raw_sha = sha(prompt)
    deterministic = (
        raw_sha == run.get("prompt_sha256")
        and run.get("run1_sha256") == run.get("run2_sha256")
        and run.get("run1_b64") == run.get("run2_b64")
    )
    put("F3A-09", deterministic,
        f"prompt bytes={len(prompt)} sha256={raw_sha}",
        "raw bytes hash + two-run determinism exact" if deterministic else "prompt bytes/hash/determinism mismatch")

    input_ok = (
        sha(inputs) == run.get("inputs_sha256")
        and before == after
        and run.get("prompt_sealed") is False
        and run.get("native_transmitted") is False
        and run.get("ready_for_independent_review") is True
    )
    put("F3A-10", input_ok,
        f"inputs bytes={len(inputs)} sha256={sha(inputs)}; side_effect_snapshot={sha(json.dumps(before,sort_keys=True).encode())}",
        "inputs hash exact + no compiler side effects" if input_ok else "inputs hash/scope/side-effect mismatch")

    return controls

def mutate_amount(prompt: bytes) -> bytes:
    sections = parse_sections(prompt)
    if sections is None:
        raise RuntimeError("cannot parse prompt for amount mutant")
    old = b'"monthly": "S/ 189.00"'
    new = b'"monthly": "S/ 190.00"'
    if old not in sections["AUTHORIZED_SAMPLE_AMOUNTS"]:
        raise RuntimeError("amount mutation anchor missing")
    return prompt.replace(old, new, 1)

def mutate_term(prompt: bytes) -> bytes:
    sections = parse_sections(prompt)
    if sections is None:
        raise RuntimeError("cannot parse prompt for term mutant")
    old = b'"term": "por 12 meses"'
    new = b'"term": "por 13 meses"'
    if old not in sections["AUTHORIZED_SAMPLE_AMOUNTS"]:
        raise RuntimeError("term mutation anchor missing")
    return prompt.replace(old, new, 1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run1", required=True)
    ap.add_argument("--run2", required=True)
    ap.add_argument("--expected", required=True)
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", required=True)
    a = ap.parse_args()

    r1 = load_json(a.run1)
    r2 = load_json(a.run2)
    expected = load_json(a.expected)
    before = load_json(a.before)
    after = load_json(a.after)

    p1 = base64.b64decode(r1["prompt_b64"])
    p2 = base64.b64decode(r2["prompt_b64"])
    run = dict(r1)
    run.update({
        "run1_sha256": sha(p1),
        "run2_sha256": sha(p2),
        "run1_b64": r1["prompt_b64"],
        "run2_b64": r2["prompt_b64"],
    })

    print(f"F3A_REAL_PROMPT_RUN1_BYTES|{len(p1)}")
    print(f"F3A_REAL_PROMPT_RUN1_SHA256|{sha(p1)}")
    print(f"F3A_REAL_PROMPT_RUN2_BYTES|{len(p2)}")
    print(f"F3A_REAL_PROMPT_RUN2_SHA256|{sha(p2)}")
    print(f"F3A_REAL_INPUTS_SHA256|{r1.get('inputs_sha256')}")

    controls = evaluate(p1, run, expected, before, after)
    for code in sorted(controls):
        d = controls[code]
        print(f"F3A_CONTROL|{code}|input={d['input']}|result={'PASS' if d['ok'] else 'FAIL'}|evidence={d['evidence']}")
    if not all(d["ok"] for d in controls.values()):
        print("F3A_INDEPENDENT_POSITIVE_FAILED", file=sys.stderr)
        return 10

    byte_mut = bytearray(p1)
    byte_mut[-1] ^= 1
    c_byte = evaluate(bytes(byte_mut), run, expected, before, after)
    if c_byte["F3A-09"]["ok"]:
        print("F3A_NEG_BYTE_NOT_KILLED", file=sys.stderr)
        return 11
    print("F3A_NEGATIVE|BYTE_1|target=F3A-09|result=FAIL_EXPECTED")

    amount_mut = mutate_amount(p1)
    c_amount = evaluate(amount_mut, run, expected, before, after)
    if c_amount["F3A-02"]["ok"]:
        print("F3A_NEG_AMOUNT_NOT_KILLED", file=sys.stderr)
        return 12
    print("F3A_NEGATIVE|AMOUNT|target=F3A-02|result=FAIL_EXPECTED")

    term_mut = mutate_term(p1)
    c_term = evaluate(term_mut, run, expected, before, after)
    if c_term["F3A-02"]["ok"]:
        print("F3A_NEG_TERM_NOT_KILLED", file=sys.stderr)
        return 13
    print("F3A_NEGATIVE|TERM|target=F3A-02|result=FAIL_EXPECTED")

    if p1 != p2 or sha(p1) != sha(p2):
        print("F3A_TWO_RUN_DETERMINISM_FAILED", file=sys.stderr)
        return 14

    print("F3A_REAL_CONTEXT_INDEPENDENT_10_10_PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
