#!/usr/bin/env python3
"""L38: local documentary integrity checks, no Supabase, no writers, no network.
Checks exact source L37 SHA/phrase, L38 24-ID overlay and unverified identity.
Negative checks are in-memory only.
"""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
L37=ROOT/"docs/rule-quality-lote37"
L38=ROOT/"docs/rule-quality-lote38"
EXPECTED_MANIFEST_SHA="ae43acb08d1783859607921ca54d58d60da89a8dff55ee38e9da37113712e9c7"
EXPECTED_PHRASE_SHA="a77ef1688ca7679980d807a96177fa3e6cbd2ef3f9f43fa50efee244c48b0475"
STATE="DECIDIDA_CONFIRMADA_EN_BLOQUE_NO_VERIFICADA"
PASSED=[]

def sha(data):
    return hashlib.sha256(data).hexdigest()

def check(label, condition, payload=None):
    assert condition, "FAIL "+label+" "+str(payload)
    PASSED.append(label)
    print("PASS_L38_"+label+" "+json.dumps(payload,sort_keys=True,ensure_ascii=False),flush=True)

def main():
    manifest_raw=(L37/"01_manifiesto_firma_en_bloque_v1.json").read_bytes()
    phrase_raw=(L37/"03_firma_unica_copiar.txt").read_bytes()
    phrase_literal=phrase_raw.removesuffix(b"\n").decode("utf-8")
    m=json.loads(manifest_raw)
    receipt=json.loads((L38/"01_receipt_confirmacion_bloque.json").read_text(encoding="utf-8"))
    overlay=json.loads((L38/"02_overlay_estado_24.json").read_text(encoding="utf-8"))
    pending=(L38/"03_uncovered_proposals_and_signature_mechanism.md").read_text(encoding="utf-8")

    check("SOURCE_MANIFEST_EXACT_SHA256",sha(manifest_raw)==EXPECTED_MANIFEST_SHA,
          {"sha256":sha(manifest_raw)})
    check("SIGNED_PHRASE_EXACT_SOURCE_SHA256",sha(phrase_literal.encode())==EXPECTED_PHRASE_SHA,
          {"sha256":sha(phrase_literal.encode()),"terminal_lf_excluded":phrase_raw.endswith(b"\n")})
    check("RECEIPT_PHRASE_BYTE_IDENTITY",receipt["phrase_literal"]==phrase_literal
          and receipt["phrase_sha256_utf8_without_trailing_newline"]==EXPECTED_PHRASE_SHA,
          {"identical":True})
    check("RECEIPT_MANIFEST_SCOPE_BINDING",receipt["source_manifest"]["sha256_utf8_exact_file"]==EXPECTED_MANIFEST_SHA
          and receipt["block_id"]==m["block_id"] and overlay["base_manifest"]["sha256_utf8"]==EXPECTED_MANIFEST_SHA,
          {"block_id":m["block_id"]})
    original_ids=[r["id"] for r in m["records"]]
    covered=receipt["covered_identifiers"]
    effective=overlay["records"]
    check("EXACT_24_ID_ORDER_AND_UNIQUENESS",len(original_ids)==len(covered)==len(effective)==24
          and len(set(original_ids))==24
          and original_ids==covered==[r["identifier"] for r in effective],
          {"count":len(covered)})
    check("24_STATUS_OVERLAY_COMPLETE",all(r["effective_status"]==STATE for r in effective)
          and overlay["target_status"]==STATE and receipt["confirmation_state"]==STATE,
          {"count":len(effective),"state":STATE})
    check("PREVIOUS_STATES_PRESERVED",all(r["previous_status"]==src["current_status"] for r,src in zip(effective,m["records"]))
          and sum(r["previous_status"].startswith("PROPUESTA") for r in effective)==1,
          {"former_risk_proposal_count":1})
    check("ALL_SOURCE_DOCUMENT_SHA_REFERENCES_PRESERVED",all(
           [(x["path"],x["branch"],x["sha256_utf8"]) for x in e["source_document_shas"]]
           ==[(x["path"],x["branch"],x["sha256_utf8"]) for x in orig["source_documents"]]
           for e,orig in zip(effective,m["records"])),
          {"source_docs":sum(len(r["source_document_shas"]) for r in effective)})
    check("UTC_LIMA_REPORTED_MINUTE",receipt["reported_local_timestamp"]=="2026-11-13T08:31-05:00"
          and receipt["reported_utc_timestamp"]=="2026-11-13T13:31Z"
          and receipt["timestamp_precision"].startswith("MINUTE"),
          {"utc":receipt["reported_utc_timestamp"],"source":"USER_REPORTED"})
    check("IDENTITY_UNVERIFIED_FAIL_CLOSED",receipt["identity_mode"]=="UNVERIFIED_CHAT_DECLARATION"
          and receipt["identity_verified"] is False
          and receipt["authenticated_signature_verified"] is False
          and overlay["formal_signature_verified"] is False
          and all(x["formal_signature_verified"] is False for x in effective)
          and receipt["original_chat_readback_independently_verified"] is False,
          {"signature_authenticated":False})
    check("NO_WRITER_NO_GO_SCOPE",receipt["writer_v2_calls_executed_by_this_lot"]==0
          and receipt["supabase_writes_executed_by_this_lot"]==0
          and receipt["runs_modified"]==0
          and receipt["gates"]["production"]=="NO_GO"
          and overlay["blockers_closed"]==0 and overlay["go_allowed"] is False
          and all(x["creates_authority_to_execute"] is False for x in effective),
          {"blockers_closed":0,"production":"NO_GO"})
    check("UNCOVERED_AUTH_PROPOSALS_RETAINED",all(code in pending for code in [
         "B2B-RULE-AUTH-018","B2B-RULE-AUTH-020","B2B-RULE-AUTH-033",
         "B2B-RULE-AUTH-002/003/040"]),
          {"min_uncovered_proposals":6})
    check("NEGATIVE_TAMPERED_PHRASE_REJECTED",
          sha((phrase_literal+" ").encode())!=EXPECTED_PHRASE_SHA,
          {"test":"append_one_space"})
    check("NEGATIVE_DUPLICATE_ID_REJECTED",
          len(set(covered+[covered[0]]))!=len(covered)+1,
          {"test":"duplicate_ID_in_copy"})
    check("NEGATIVE_FAKE_VERIFIED_IDENTITY_REJECTED",
          not (receipt["identity_verified"] is True and overlay["formal_signature_verified"] is True),
          {"test":"pretend_identity_verified"})
    print("L38_TEST_TOTAL_PASS",len(PASSED),flush=True)
    print("L38_RESULT_DOCUMENTARY_ONLY_NO_SIGNATURE_NO_GO",flush=True)

if __name__=="__main__":
    main()
