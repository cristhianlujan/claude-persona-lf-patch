"""Trusted-runner adapter: validate signed chat event, NEVER record approval.

The parent workflow must resolve expected scope from immutable PR/head or
rule snapshots, and configure signer key + owner id through protected settings.
A model-provided event path / scope is not authorization. DB consumption is
separate and atomic, through the existing human-decision routing ledger.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives import serialization

from scripts.lf_owner_chat_event_v1 import ApprovalRejected, digest, verify_event


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--event-json", required=True)
    p.add_argument("--expected-scope-json", required=True)
    p.add_argument("--out-json", required=True)
    args = p.parse_args(argv)

    key_pem = os.getenv("LF_CHAT_TRUSTED_SIGNER_PUBLIC_KEY_PEM")
    fingerprint = os.getenv("LF_CHAT_TRUSTED_SIGNER_PUBLIC_KEY_SHA256")
    owner = os.getenv("LF_CHAT_TRUSTED_OWNER_SUBJECT")
    kid = os.getenv("LF_CHAT_TRUSTED_KID")
    if not all((key_pem, fingerprint, owner, kid)):
        raise ApprovalRejected("TRUSTED_CHAT_INGRESS_NOT_CONFIGURED")
    if digest(key_pem.encode("utf-8")) != fingerprint:
        raise ApprovalRejected("TRUST_ROOT_FINGERPRINT_MISMATCH")
    pk = serialization.load_pem_public_key(key_pem.encode("utf-8"))
    event = json.loads(Path(args.event_json).read_text(encoding="utf-8"))
    scope = json.loads(Path(args.expected_scope_json).read_text(encoding="utf-8"))
    receipt = verify_event(
        event, trusted_public_key=pk, trusted_key_id=kid,
        trusted_owner_subject=owner, expected_scope=scope,
        now=datetime.now(timezone.utc))
    Path(args.out_json).write_text(json.dumps(receipt, ensure_ascii=False,
                                             sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status":"SIGNED_EVENT_VERIFIED_UNCONSUMED",
                      "scope_sha256":receipt["scope_sha256"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ApprovalRejected, ValueError, OSError) as exc:
        print("BLOCKED_CHAT_APPROVAL:" + str(exc), file=sys.stderr)
        sys.exit(2)
