#!/usr/bin/env python3
"""N-17 NEG_HEURISTIC_CAUSALITY: name / object / timestamp similarity never proves causality.
Base = the REAL CAUSAL_EFFECT_LINEAGE request built from run 836 receipts (Curator handoff -> Validator completion).
The base must evaluate LINKED; every heuristic-only or heuristic-polluted variant must NOT produce a causal edge. No writes."""
from __future__ import annotations
import argparse, copy, json, os, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "transversal_assets" / "causal_effect_lineage"))
from causal_effect_lineage_v1 import evaluate_lineage  # noqa: E402

TEST_CODE = "ENG_N_17_NEG_HEURISTIC_CAUSALITY"


def cases(base: dict):
    def m(name, fn, want):
        c = copy.deepcopy(base); fn(c); return name, c, want

    yield m("NAME_ONLY", lambda c: (c.clear(), c.update(name="validator-completed.run-836")), {"UNLINKED"})
    yield m("OBJECT_REF_ONLY", lambda c: (c.clear(), c.update(object_ref="input-readiness-run:836")), {"UNLINKED"})
    yield m("TIMESTAMP_ONLY", lambda c: (c.clear(), c.update(timestamp="2026-10-09T10:40:00-05:00", observed_at="2026-10-09T10:40:01-05:00")), {"UNLINKED"})
    yield m("NAME_OBJECT_TIME_COMBINED", lambda c: (c.clear(), c.update(name="a", object_ref="b", timestamp="t", created_at="t")), {"UNLINKED"})
    yield m("SAME_OBJECT_WITHOUT_RECEIPTS", lambda c: (c.pop("producer_receipt"), c.pop("receiver_effect_receipt"), c.update(object_ref="input-readiness-run:836")), {"UNLINKED"})
    yield m("IDENTITIES_DROPPED_HEURISTICS_KEPT", lambda c: (c.pop("parent_identity"), c.pop("correlation_identity"), c.update(name="x", timestamp="t")), {"UNLINKED"})
    yield m("RECEIVER_CORRELATION_OTHER_RUN_SAME_NAME", lambda c: (c["receiver_effect_receipt"]["receipt_payload"].update(correlation_identity={"scope": "lf:ig-run", "opaque_id": "run-835"}), c.update(name="validator-completed.run-836")), {"AMBIGUOUS"})
    yield m("RECEIVER_PARENT_OTHER_HANDOFF", lambda c: c["receiver_effect_receipt"]["receipt_payload"].update(parent_identity={"scope": "lf:ig-curator-handoff", "opaque_id": "receipt-206"}), {"AMBIGUOUS"})
    yield m("CROSSLINK_SHA_FORGED_BY_SIMILARITY", lambda c: c["receiver_effect_receipt"]["receipt_payload"].update(producer_receipt_sha256="c" * 64), {"UNLINKED"})
    yield m("READBACK_NOT_OBSERVED", lambda c: c["receiver_readback"].update(observed=False), {"UNLINKED"})
    yield m("READBACK_EFFECT_REF_DIFFERS", lambda c: c["receiver_readback"].update(effect_ref="validator-completed.run-836.1"), {"UNLINKED"})
    yield m("RECEIVER_STALE", lambda c: c["currentness"].update(receiver="STALE"), {"UNLINKED"})
    yield m("BOUNDARY_INVALID", lambda c: c["provenance"].update(boundary="NAME_MATCH"), {"UNLINKED"})
    yield m("PII_IN_REQUEST", lambda c: c.update(email="x@example.com"), {"UNLINKED"})


def run(base: dict) -> dict:
    ctl = evaluate_lineage(base)
    control_ok = ctl["state"] == "LINKED" and bool(ctl["causal_edge_digest"]) and not ctl["business_authority"] and not ctl["execution_permission"]
    res = []
    for name, c, want in cases(base):
        o = evaluate_lineage(c)
        ok = o["state"] in want and o["causal_edge_digest"] is None
        res.append({"case": name, "state": o["state"], "reasons": o["reasons"][:2], "rejected_as_causal": ok})
    # heuristic noise added to a VALID request must not change the edge (heuristics are non-probative, not additive)
    noisy = copy.deepcopy(base); noisy.update(name="zzz", object_ref="zzz", timestamp="zzz")
    noise_ok = evaluate_lineage(noisy)["causal_edge_digest"] == ctl["causal_edge_digest"]
    ok = control_ok and noise_ok and all(r["rejected_as_causal"] for r in res)
    return {
        "test_code": TEST_CODE, "control_linked": control_ok, "heuristic_noise_does_not_change_edge": noise_ok,
        "cases_total": len(res), "cases_rejected": sum(r["rejected_as_causal"] for r in res), "cases": res,
        "observed": {"test_passed": ok, "test_exit_code": 0 if ok else 1,
                     "semantic_authority_bound": bool(base.get("parent_identity") and base.get("producer_receipt") and base.get("receiver_readback")),
                     "adversarial_case_executed": len(res) == 14},
    }


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--input")
    a = ap.parse_args()
    p = Path(a.input) if a.input else HERE / "run836_lineage_request.json"
    out = run(json.loads(p.read_text()))
    print(json.dumps(out, indent=1, sort_keys=True)); return out["observed"]["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
