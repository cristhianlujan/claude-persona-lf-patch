#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATCH = ROOT / "supabase/migrations/20260922214500_lf_profile_baseline_digest_parity_guard_v1.sql"
ENGINE = ROOT / "services/profile_runtime_api/profile_runtime_api/engine.py"
VALIDATOR = ROOT / "profiles/systemic_root_cause_repair_lf/validators/incremental_value.py"

for path in (PATCH, ENGINE, VALIDATOR):
    assert path.is_file(), path

patch = PATCH.read_text()
engine = ENGINE.read_text()
validator = VALIDATOR.read_text()

fixture = {"z": [True, None, "ñ"], "a": {"n": 7, "s": "á"}}
raw = json.dumps(
    fixture,
    sort_keys=True,
    separators=(",", ":"),
    ensure_ascii=False,
).encode("utf-8")
expected = hashlib.sha256(raw).hexdigest()

assert expected == "29ed0b05def02fe73beceeaceafcd9d9ca025fa3c2ad405e3a365fdc1672e0d1"

# Same canonical digest semantics at producer, validator, and persistence boundary.
assert 'canonical_json_sha256(snapshot)' in engine
assert 'json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False)' in validator
assert "private.fn_payload_sha256_v7(" in patch
assert "p_baseline_envelope->'snapshot'" in patch
assert "PROFILE_RESEARCH_BASELINE_DIGEST_MISMATCH" in patch
assert expected in patch

# The correction is generic; it must never encode the M14 test or a profile/case identity.
for forbidden in (
    "EXEC-M14",
    "SRCR-LIFECYCLE-DEEP-BLIND-001",
    "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
):
    assert forbidden not in patch, forbidden

# Independent jsonb-text fingerprint is retained and is not the canonical digest authority.
assert "server_snapshot_fingerprint:='sha256:'||encode(" in patch
assert "canonical_baseline_digest:='sha256:'||private.fn_payload_sha256_v7(" in patch

print("PASS_PROFILE_BASELINE_DIGEST_PARITY")
