#!/usr/bin/env python3
import json
import sys
from pathlib import Path

TIERS = {"CONSERVATIVE", "DIFFERENTIATED", "TEN_X"}


def fail(errors):
    print(json.dumps({"valid": False, "errors": errors}, ensure_ascii=False, sort_keys=True))
    return 1


def main(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = []
    if data.get("schema") != "s37-decision-discovery-portfolio/v1":
        errors.append("schema")
    sources = {x.get("source_id") for x in data.get("source_catalog", []) if isinstance(x, dict)}
    hyps = data.get("hypotheses")
    if not isinstance(hyps, list) or len(hyps) != 3:
        errors.append("hypotheses_exactly_3")
        return fail(errors)
    tiers = [h.get("tier") for h in hyps if isinstance(h, dict)]
    if set(tiers) != TIERS or len(tiers) != 3:
        errors.append("tiers_exactly_conservative_differentiated_ten_x")
    ids = [h.get("hypothesis_id") for h in hyps if isinstance(h, dict)]
    if len(ids) != len(set(ids)):
        errors.append("hypothesis_ids_unique")

    for h in hyps:
        hid = h.get("hypothesis_id", "UNKNOWN")
        refs = h.get("source_refs", [])
        if not refs or any(r not in sources for r in refs):
            errors.append(f"{hid}:source_refs_not_bound")
        required_text = [
            "hypothesis", "specific_decision_changed", "causal_mechanism", "economic_metric",
            "experiment", "falsification_condition", "learning_loop", "compounding_moat",
            "why_not_generic", "copyability_barrier"
        ]
        for key in required_text:
            if not isinstance(h.get(key), str) or not h[key].strip():
                errors.append(f"{hid}:{key}_missing")
        if not h.get("material_deltas"):
            errors.append(f"{hid}:material_deltas_missing")
        checks = h.get("semantic_checks") or {}
        if checks.get("experiment_is_falsifiable") is not True:
            errors.append(f"{hid}:experiment_not_falsifiable")
        if h.get("tier") in {"DIFFERENTIATED", "TEN_X"}:
            if checks.get("portable_to_generic_fintech_unchanged") is not False:
                errors.append(f"{hid}:generic_portability_not_rejected")
            if checks.get("causal_mechanism_distinct") is not True:
                errors.append(f"{hid}:causal_distinction_unproven")
            if checks.get("uses_lf_compounding_asset") is not True:
                errors.append(f"{hid}:lf_compounding_asset_missing")
        if h.get("tier") == "TEN_X":
            deltas = set(h.get("material_deltas", []))
            if not deltas.intersection({"ECONOMICS", "PRODUCT", "NETWORK_EFFECT", "DATA"}):
                errors.append(f"{hid}:ten_x_material_logic_delta_missing")

    if errors:
        return fail(errors)
    print(json.dumps({
        "valid": True,
        "errors": [],
        "claim_ceiling": "STRUCTURAL_CONTRACT_PASS_ONLY_SEMANTIC_JUDGE_STILL_REQUIRED"
    }, ensure_ascii=False, sort_keys=True))
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: s37_validate_portfolio.py <portfolio.json>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
