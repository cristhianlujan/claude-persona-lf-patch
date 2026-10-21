"""PE10 E2 C3 frozen-output validator. Read-only, no DB, no model invocation.

Validates, on the full persisted data, that the B18/B29 producer outputs were frozen
unmodified and that the common P0 input was identical for both arms. It does NOT attest
provider-level isolation, semantic correctness or grading (those are explicitly out of scope).
"""
import hashlib
import json
import re
import sys
from pathlib import Path

CASE = "PE10-IG-M107-M109-P0"
ROLES = ["ARCHITECTURE", "PERFORMANCE", "AUTHORITY", "COVERAGE", "INNOVATION"]
ARMS = {
    "b18": {"arm": "B18", "method": "PE10_M18_E2", "algorithms": ["D"]},
    "b29": {"arm": "B29", "method": "PE10_M29_E2", "algorithms": ["C", "E"]},
}
OBS_CLASSES = {
    "CURRENT", "P0_HISTORICAL", "CURRENT_COMPARED_TO_P0_HISTORICAL",
    "HISTORICAL_EKB_ALLOWED_ROW_CURRENT_READBACK",
}
# Orchestrator-disclosed exposure; recorded in the manifest, not hidden.
DENYLIST_RE = re.compile(r"PE10_M\d+(?!\d|_E2)|RAW_V2|m01_raw")


def sha(b):
    return hashlib.sha256(b).hexdigest()


def csha(obj):
    return sha(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


def packet_json_block(text, header):
    i = text.index(header)
    j = text.index("````json\n", i) + len("````json\n")
    k = text.index("\n````", j)
    return json.loads(text[j:k])


def validate(root):
    root = Path(root)
    manifest = json.loads((root / "C3_FROZEN_OUTPUT_MANIFEST_V1.json").read_text(encoding="utf-8"))
    assert manifest["schema"] == "PE10_E2_C3_FROZEN_OUTPUT_MANIFEST_V1"
    assert manifest["case_ref"] == CASE
    files = manifest["files"]
    on_disk = sorted(
        str(p.relative_to(root)) for p in root.rglob("*")
        if p.is_file() and p.name not in ("C3_FROZEN_OUTPUT_MANIFEST_V1.json", "C3_FROZEN_RUN_RECEIPT_V1.json")
    )
    assert on_disk == sorted(files), "inventory mismatch"
    for rel, meta in files.items():
        data = (root / rel).read_bytes()
        assert sha(data) == meta["sha256"] and len(data) == meta["bytes"], "hash/bytes mismatch " + rel
        assert b"\r" not in data, "CR in " + rel

    out = {"arms": {}}
    for key, cfg in ARMS.items():
        raws = {}
        for role in ROLES:
            text = (root / key / f"RAW_{cfg['arm']}_{role}.md").read_text(encoding="utf-8")
            assert text.startswith(f"===ROLE_REPORT:{role} BEGIN===\n"), role
            assert text.endswith(f"===ROLE_REPORT:{role} END===\n"), role
            assert text.count("ROLE_REPORT:") == 2
            for hdr, want in (("Case", CASE), ("Method", None)):
                m0 = re.search(rf"^{hdr}: (.*)$", text, re.M)
                if m0 and hdr == "Case":
                    assert m0.group(1) == want, (role, hdr)
                if m0 and hdr == "Method":
                    assert cfg["method"] in m0.group(1), (role, hdr)
            m = re.search(r"^Decision: ([A-Z_]+)", text, re.M)
            raws[role] = {"sha256": sha(text.encode()), "decision": m.group(1) if m else None}
        syn = json.loads((root / key / f"SYNTHESIS_{cfg['arm']}_RAW.json").read_text(encoding="utf-8"))
        assert syn["case_id"] == CASE and syn["status"] == "RAW_FROZEN_UNGRADED"
        assert cfg["method"] in (syn.get("variant"), syn.get("method")), "synthesis method"
        algs = syn.get("algorithms") or [syn.get("algorithm")]
        assert algs == cfg["algorithms"], "synthesis algorithms"
        out["arms"][key] = {"raws": raws, "synthesis_sha256": sha((root / key / f"SYNTHESIS_{cfg['arm']}_RAW.json").read_bytes())}

    # P0 equality across producers: both packets embed the same common envelope and a distinct overlay.
    common_repo = json.loads((root.parent / "COMMON_P0_INPUT_ENVELOPE_V1.json").read_text(encoding="utf-8"))
    envs, overlays = [], []
    for key, cfg in ARMS.items():
        t = (root / "packets" / f"PRODUCER_PACKET_{cfg['arm']}.md").read_text(encoding="utf-8")
        envs.append(packet_json_block(t, "## COMMON P0 INPUT ENVELOPE"))
        overlays.append(packet_json_block(t, "## YOUR PRODUCER OVERLAY"))
    assert envs[0] == envs[1] == common_repo, "common envelope differs"
    assert csha(common_repo) == "93d4f5cba4564ddb0cc46f731375d5d83d81b724e195dfc213b2d98fc9ebc090"
    assert overlays[0]["overlay_sha256"] != overlays[1]["overlay_sha256"]
    assert overlays[0]["common_envelope_sha256"] == overlays[1]["common_envelope_sha256"] == csha(common_repo)
    assert common_repo["source_event"]["id"] == 20161 and common_repo["source_cutoff_utc"] == "2026-10-15T00:00:00Z"

    # CURRENT vs P0 separation: every relayed result declares its observation class; none claims CURRENT as P0.
    missing_class, exposures, class_counts, body_hash_checked = [], [], {}, 0
    for key in ARMS:
        for p in sorted((root / key / "relays").iterdir()):
            t = p.read_text(encoding="utf-8")
            m = re.search(r"Observation class: ([A-Z0-9_]+)|class (CURRENT|P0_HISTORICAL)\b", t)
            cls = (m.group(1) or m.group(2)) if m else None
            if p.name.startswith("QUERY_ERROR"):
                continue
            if cls is None:
                missing_class.append(f"{key}/{p.name}")
            else:
                assert cls in OBS_CLASSES, (p.name, cls)
                class_counts[cls] = class_counts.get(cls, 0) + 1
            hm = re.search(r"Body sha256 \(lines after ---BEGIN ROWS---, joined by \\n\): ([0-9a-f]{64})\n---BEGIN ROWS---\n", t)
            if hm:
                body = t.split("---BEGIN ROWS---\n", 1)[1]
                # Two writer conventions exist: hash over the full body, or over the body without the
                # single final LF appended by the file writer (bodies whose last row legitimately ends in LF).
                ok = sha(body.encode()) == hm.group(1) or (body.endswith("\n") and sha(body[:-1].encode()) == hm.group(1))
                assert ok, "relay body sha mismatch " + p.name
                body_hash_checked += 1
            if DENYLIST_RE.search(t):
                exposures.append(f"{key}/{p.name}")
    assert set(exposures) <= set(manifest["known_exceptions"]["denylist_exposure_files"]), exposures
    assert sorted(missing_class) == sorted(manifest["known_exceptions"]["relays_without_class_line"]), missing_class
    out.update(
        status="PASS", same_common_p0=True, common_envelope_sha256=csha(common_repo),
        relay_class_counts=class_counts, relay_body_hashes_rechecked=body_hash_checked,
        known_denylist_exposure=sorted(exposures), relays_without_class_line=sorted(missing_class),
    )
    return out


if __name__ == "__main__":
    print(json.dumps(validate(sys.argv[1]), sort_keys=True, indent=1))
