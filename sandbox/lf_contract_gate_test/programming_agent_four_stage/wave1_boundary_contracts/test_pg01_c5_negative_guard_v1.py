#!/usr/bin/env python3
"""Exactly eight labeled negative admission cases, plus immutable-cache replay."""
import copy
import runpy
from pathlib import Path

from pg01_c3_scope_front_clean_v1 import CONTRACT, ROOT
from pg01_c5_negative_guard_v1 import assess_c5

fixture = runpy.run_path(
    str(Path(__file__).with_name("test_analysis_pg01_snapshot_payload_v1.py"))
)["fixture"]
snapshot = fixture()
snapshot["authority_fingerprint_sha256"] = "a" * 64
paths = [ROOT + f.removesuffix("[]")
         for f in CONTRACT["programming_context_snapshot"]["required_fields"]]
receipt = {"verdict": "ACCEPT", "validated_material_paths": paths}
cached = copy.deepcopy(snapshot)
fingerprint = "a" * 64

reads = {"count": 0}
def forbidden_rediscovery(*args, **kwargs):
    reads["count"] += 1
    raise AssertionError("REDISCOVERY_WITH_UNCHANGED_FINGERPRINT")

# Two identical positive replays: no new source reads, no runtime authority.
for _ in range(2):
    good = assess_c5(snapshot, receipt, ["S1"], cached, fingerprint,
                     typed_resolver=forbidden_rediscovery)
    assert good["state"] == "CANDIDATE_PASS", good
    assert good["authority"] == "NONE" and good["rediscovery_count"] == 0
assert reads["count"] == 0

# The canonical checkpoint only specifies "8 negatives -> BLOCK" without
# enumerating identities. These eight cover distinct fail-closed boundaries
# drawn from the existing snapshot/currentness/admission contracts.
cases = []
cases.append(("N01_MISSING_CACHE", snapshot, receipt, ["S1"], None, fingerprint,
              None, "PG01_C5_CACHE_OR_SNAPSHOT_MISSING"))
cases.append(("N02_INVALID_FINGERPRINT", snapshot, receipt, ["S1"], cached, "invalid",
              None, "PG01_C5_FINGERPRINT_INVALID"))
cases.append(("N03_AUTHORITY_DRIFT", snapshot, receipt, ["S1"], cached, "b"*64,
              None, "PG01_C5_FINGERPRINT_DRIFT"))
stale_cache = copy.deepcopy(cached)
stale_cache["authority_fingerprint_sha256"] = "c"*64
cases.append(("N04_CACHE_DRIFT", snapshot, receipt, ["S1"], stale_cache, fingerprint,
              None, "PG01_C5_CACHED_FINGERPRINT_DRIFT"))
changed = copy.deepcopy(snapshot)
changed["scope_readiness"][0]["reason"] = "changed, without changing fingerprint"
cases.append(("N05_SNAPSHOT_DRIFT", changed, receipt, ["S1"], cached, fingerprint,
              None, "PG01_C5_SOURCE_SNAPSHOT_DRIFT"))
cases.append(("N06_RECEIPT_BLOCK", snapshot, {"verdict":"BLOCK","validated_material_paths":paths},
              ["S1"], cached, fingerprint, None, "PG01_C5_SCOPE_FRONT_BLOCK:PG01_C3_RECEIPT_NOT_ACCEPTED"))
cases.append(("N07_MATERIAL_PATH_MISSING", snapshot,
              {"verdict":"ACCEPT","validated_material_paths":paths[:-1]},
              ["S1"], cached, fingerprint, None,
              "PG01_C5_SCOPE_FRONT_BLOCK:PG01_C3_MATERIAL_PATHS_INCOMPLETE_OR_EXTRA"))
cases.append(("N08_BLOCKED_SCOPE", snapshot, receipt, ["S2"], cached, fingerprint,
              None, "PG01_C5_SCOPE_FRONT_BLOCK:PG01_C3_REQUESTED_SCOPE_NOT_READY"))

assert len(cases) == 8
for label, snap, rec, requested, cache, fp, trigger, reason in cases:
    result = assess_c5(snap, rec, requested, cache, fp, requery_trigger=trigger,
                       typed_resolver=forbidden_rediscovery)
    assert result["state"] == "BLOCK" and result["reason"] == reason, (label, result)
    assert result["authority"] == "NONE" and result["rediscovery_count"] == 0
    print("PG01_C5_NEGATIVE_PASS=" + label)

# Supplementary invariants, NOT counted as the checkpoint's eight cases.
assert assess_c5(snapshot, receipt, ["S1"], cached, fingerprint,
                 requery_trigger="STALE")["state"] == "BLOCK"
assert assess_c5(snapshot, receipt, ["S1"], cached, fingerprint,
                 requery_trigger="UNKNOWN")["state"] == "BLOCK"
assert reads["count"] == 0
print("PASS_PG01_C5_EIGHT_NEGATIVES negative=8 positive_replays=2 "
      "zero_rediscovery_same_fingerprint=true cached_source_binding=true "
      "authority=NONE pg01_runtime_verified=false")
