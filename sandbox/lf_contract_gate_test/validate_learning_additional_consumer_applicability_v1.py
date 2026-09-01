#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "learning_additional_consumer_applicability_v1.json"
EXPECTED = {
    "PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531": "ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531",
    "PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531": "ADAPTER-MARKETPLACE-LF-UX-20260531",
}


def main() -> None:
    payload = json.loads(DATA.read_text(encoding="utf-8"))
    assert payload["schema"] == "LF_LEARNING_ADDITIONAL_CONSUMER_APPLICABILITY_V1"
    assert payload["mode"] == "READ_ONLY"
    assert payload["automatic_binding"] is False
    assert payload["automatic_impact"] is False
    assert payload["production_authorized"] is False
    rows = payload["consumers"]
    assert len(rows) == 2
    seen = set()
    for row in rows:
        cid = row["consumer_id"]
        assert cid in EXPECTED
        assert cid not in seen
        seen.add(cid)
        assert row["adapter_code"] == EXPECTED[cid]
        assert row["adapter_operational_status"] == "READ_ONLY"
        assert row["runtime_enabled"] is False
        assert row["production_enabled"] is False
        assert row["exact_capability_binding_observed"] is False
        assert row["read_only_learning_status"] == "READY_FOR_BINDING_AFTER_EXACT_CAPABILITY_CLASSIFICATION"
        assert row["fallback"] == "NO_COMPETITIVE_CONTEXT"
    assert seen == set(EXPECTED)
    print("LEARNING_ADDITIONAL_CONSUMER_APPLICABILITY=PASS consumers=2/2 automatic_binding=false production_authorized=false")


if __name__ == "__main__":
    main()
