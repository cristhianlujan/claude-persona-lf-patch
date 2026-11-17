"""Synthetic cryptographically real fixtures, NEVER real ChatGPT receipts."""
import base64
from datetime import datetime, timedelta, timezone
import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from scripts.lf_owner_chat_event_v1 import ApprovalRejected, canonical, digest, verify_event

NOW = datetime(2026, 11, 16, 23, 54, tzinfo=timezone.utc)
CHALLENGE = "LF-ABCDE1234567"
OWNER = "test-provider-subject-owner"
RULES = ["B2B-RULE-AUTH-004", "B2B-RULE-AUTH-005"]
PR_SCOPE = {"action":"MERGE_GOVERNANCE_PR", "repository":"cristhianlujan/claude-persona-lf-patch",
            "pr_number":4061, "head_sha":"a"*40}
RULE_SCOPE = {"action":"PROMOTE_RULE_BATCH", "repository":PR_SCOPE["repository"],
              "pr_number":4061, "head_sha":"a"*40,
              "execution_id":"EXEC-TEST-SYNTHETIC-ONLY", "rule_codes":RULES,
              "rule_snapshots_sha256":"b"*64}


def packet_for(key, scope=None, **patch):
    event = dict(schema_version="LF_OWNER_CHAT_SIGNED_MESSAGE_V1",
                 event_type="USER_MESSAGE", source_platform="CHATGPT",
                 issuer_kind="TRUSTED_FIRST_PARTY_INGRESS", actor_subject=OWNER,
                 conversation_id="fixture-conversation-001", message_id="fixture-message-0001",
                 challenge_id=CHALLENGE, literal_text=f"APRUEBO {CHALLENGE}",
                 sent_at=NOW.isoformat().replace("+00:00", "Z"),
                 expires_at=(NOW+timedelta(minutes=10)).isoformat().replace("+00:00", "Z"),
                 scope=scope or PR_SCOPE)
    event.update(patch)
    raw = canonical(event)
    b = lambda x: base64.urlsafe_b64encode(x).rstrip(b"=").decode()
    return {"key_id":"fixture-only-kid", "payload_b64":b(raw),
            "signature_b64":b(key.sign(raw))}


def verified(packet, pub, expected=PR_SCOPE, **kwargs):
    args = dict(trusted_public_key=pub, trusted_key_id="fixture-only-kid",
                trusted_owner_subject=OWNER, expected_scope=expected,
                now=NOW+timedelta(minutes=1))
    args.update(kwargs)
    return verify_event(packet, **args)


def deny(code, packet, pub, **kwargs):
    with pytest.raises(ApprovalRejected, match=code):
        verified(packet, pub, **kwargs)


def test_positive_pr_and_rule_scopes():
    key = Ed25519PrivateKey.generate()
    for scope in (PR_SCOPE, RULE_SCOPE):
        receipt = verified(packet_for(key, scope), key.public_key(), expected=scope)
        assert receipt["scope_sha256"] == digest(canonical(scope))
        assert receipt["consumed"] is False and receipt["signature_verified"] is True


def test_absent():
    key = Ed25519PrivateKey.generate()
    deny("PACKET_FORMAT_INVALID", {}, key.public_key())


def test_wrong_scope():
    key = Ed25519PrivateKey.generate()
    deny("EXACT_SCOPE_MISMATCH", packet_for(key), key.public_key(),
         expected={**PR_SCOPE, "pr_number":4062})


def test_wrong_head():
    key = Ed25519PrivateKey.generate()
    deny("EXACT_SCOPE_MISMATCH", packet_for(key), key.public_key(),
         expected={**PR_SCOPE, "head_sha":"c"*40})


def test_expired():
    key = Ed25519PrivateKey.generate()
    deny("CHAT_APPROVAL_EXPIRED_OR_FUTURE", packet_for(key), key.public_key(),
         now=NOW+timedelta(minutes=11))


def test_wrong_identity():
    key = Ed25519PrivateKey.generate()
    deny("WRONG_OWNER_IDENTITY", packet_for(key, actor_subject="model"),
         key.public_key())


def test_model_self_approval():
    key = Ed25519PrivateKey.generate()
    deny("NO_EXPLICIT_CHALLENGE_APPROVAL",
         packet_for(key, literal_text="El asistente aprueba la propuesta"), key.public_key())


def test_wrong_signer():
    key = Ed25519PrivateKey.generate()
    deny("INVALID_SIGNATURE", packet_for(key), Ed25519PrivateKey.generate().public_key())


def test_tampered_payload():
    key = Ed25519PrivateKey.generate()
    packet = packet_for(key)
    raw = base64.urlsafe_b64decode(packet["payload_b64"] + "="*(-len(packet["payload_b64"])%4))
    packet["payload_b64"] = base64.urlsafe_b64encode(raw.replace(b"4061",b"4062")).rstrip(b"=").decode()
    deny("INVALID_SIGNATURE", packet, key.public_key())


def test_missing_trust_root():
    key = Ed25519PrivateKey.generate()
    deny("TRUSTED_CHAT_INGRESS_NOT_CONFIGURED", packet_for(key),
         key.public_key(), trusted_public_key=None)


def test_wrong_rule_cohort():
    key = Ed25519PrivateKey.generate()
    deny("EXACT_SCOPE_MISMATCH", packet_for(key, RULE_SCOPE), key.public_key(),
         expected={**RULE_SCOPE,"rule_codes":[RULES[0]]})


def test_duplicate_rule_codes():
    key = Ed25519PrivateKey.generate()
    deny("NONEXACT_RULE_COHORT", packet_for(key,
         {**RULE_SCOPE, "rule_codes":[RULES[0],RULES[0]]}),
         key.public_key(), expected=RULE_SCOPE)


def test_future_message_timestamp():
    key = Ed25519PrivateKey.generate()
    deny("CHAT_APPROVAL_EXPIRED_OR_FUTURE",
         packet_for(key, sent_at=(NOW+timedelta(minutes=5)).isoformat().replace("+00:00","Z")),
         key.public_key())


def test_wrong_challenge():
    key = Ed25519PrivateKey.generate()
    deny("NO_EXPLICIT_CHALLENGE_APPROVAL",
         packet_for(key, literal_text="APRUEBO LF-ZYXWV9876543"), key.public_key())
