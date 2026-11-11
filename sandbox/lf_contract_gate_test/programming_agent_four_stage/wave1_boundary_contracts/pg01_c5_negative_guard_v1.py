#!/usr/bin/env python3
"""PG-01_C5 source-only negative admission and same-fingerprint reuse boundary.

This is a candidate test adapter, not an authority, source resolver or runtime
PG-01 receipt. Reuses PG-01_C3 and the canonical A9 snapshot matrix validator.
"""
import hashlib
import json
import re

from pg01_c3_scope_front_clean_v1 import assess_scope_front_clean

HEX64 = re.compile(r"^[0-9a-f]{64}$")
REQUERY_TRIGGERS = frozenset({
    "MISSING", "STALE", "CONTRADICTION", "SOURCE_DRIFT", "MATERIAL_NEW_QUESTION"
})


def snapshot_digest(snapshot):
    """Digest only for this Python fixture/cache binding, not a PostgreSQL jsonb digest."""
    return hashlib.sha256(
        json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()


def blocked(reason):
    return {
        "state": "BLOCK", "reason": reason, "authority": "NONE",
        "runtime_verified": False, "rediscovery_count": 0,
    }


def assess_c5(snapshot, receipt, requested_scope_ids, cached_snapshot, fingerprint,
              requery_trigger=None, typed_resolver=None):
    """Fail closed on missing/stale proof; unchanged fingerprint MUST do zero I/O.

    The caller supplies a previously verified immutable snapshot cache. A changed
    fingerprint returns BLOCK, demanding separately governed rebuild; this
    adapter never performs untrusted rediscovery itself.
    """
    if not isinstance(snapshot, dict) or not isinstance(cached_snapshot, dict):
        return blocked("PG01_C5_CACHE_OR_SNAPSHOT_MISSING")
    if not isinstance(fingerprint, str) or not HEX64.fullmatch(fingerprint):
        return blocked("PG01_C5_FINGERPRINT_INVALID")
    observed = snapshot.get("authority_fingerprint_sha256")
    if not isinstance(observed, str) or observed != fingerprint:
        return blocked("PG01_C5_FINGERPRINT_DRIFT")
    if cached_snapshot.get("authority_fingerprint_sha256") != fingerprint:
        return blocked("PG01_C5_CACHED_FINGERPRINT_DRIFT")
    if snapshot_digest(snapshot) != snapshot_digest(cached_snapshot):
        return blocked("PG01_C5_SOURCE_SNAPSHOT_DRIFT")
    if requery_trigger is not None:
        if requery_trigger not in REQUERY_TRIGGERS:
            return blocked("PG01_C5_REQUERY_TRIGGER_UNAUTHORIZED")
        return blocked("PG01_C5_REBUILD_REQUIRED_FOR_REQUERY")
    if typed_resolver is not None and not callable(typed_resolver):
        return blocked("PG01_C5_RESOLVER_INVALID")
    # No network/source read, no resolver call, no rediscovery for stable cache.
    decision = assess_scope_front_clean(snapshot, receipt, requested_scope_ids)
    if not decision["admissible"]:
        return blocked("PG01_C5_SCOPE_FRONT_BLOCK:" + decision["reason"])
    return {
        "state": "CANDIDATE_PASS", "reason": "PG01_C5_CACHED_CLEAN_READY",
        "authority": "NONE", "runtime_verified": False,
        "rediscovery_count": 0, "scope_ids": decision["scope_ids"],
        "fingerprint": fingerprint,
    }
