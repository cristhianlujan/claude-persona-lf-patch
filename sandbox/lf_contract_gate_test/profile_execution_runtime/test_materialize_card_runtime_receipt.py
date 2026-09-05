from pathlib import Path
import importlib.util
import json

MODULE_PATH = Path(__file__).with_name("materialize_card_runtime_receipt.py")
FIXTURE_PATH = Path(__file__).with_name("golden_family_ui_architect_v1.json")
spec = importlib.util.spec_from_file_location("card_receipt", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)

CARD = "cards/marketplace_lf/decision_product_experience/CARD.md"


def test_materializes_same_request_source_bound_receipt():
    receipt = module.materialize_card_receipt(
        request_id="GF-REQ-001",
        card_path=CARD,
        selected_sections=["Role", "Decision lenses"],
        budget=2048,
    )
    assert receipt["request_id"] == "GF-REQ-001"
    assert receipt["card_ref"] == CARD
    assert str(receipt["card_version_or_hash"]).startswith("sha256:")
    assert receipt["sections_consumed"] == ["Role", "Decision lenses"]
    assert receipt["budget"] == 2048
    assert receipt["decision"] == "MATERIALIZED_READ_ONLY"


def test_receipt_satisfies_exact_golden_family_card_contract():
    fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    receipt = module.materialize_card_receipt(
        request_id="GF-REQ-CONTRACT",
        card_path=fixture["card"]["source_ref"],
        selected_sections=["Role"],
        budget=1024,
    )
    required = fixture["card"]["required_receipt_fields"]
    assert sorted(receipt) == sorted(required)
    assert receipt["card_ref"] == fixture["card"]["source_ref"]


def test_unknown_section_fails_closed():
    try:
        module.materialize_card_receipt(
            request_id="GF-REQ-NEG",
            card_path=CARD,
            selected_sections=["DOES NOT EXIST"],
            budget=128,
        )
    except ValueError as exc:
        assert str(exc).startswith("CARD_RECEIPT_UNKNOWN_SECTION:")
    else:
        raise AssertionError("unknown section must fail closed")


def test_missing_request_id_fails_closed():
    try:
        module.materialize_card_receipt(
            request_id="",
            card_path=CARD,
            selected_sections=["Role"],
            budget=128,
        )
    except ValueError as exc:
        assert str(exc) == "CARD_RECEIPT_REQUEST_ID_REQUIRED"
    else:
        raise AssertionError("missing request id must fail closed")


if __name__ == "__main__":
    test_materializes_same_request_source_bound_receipt()
    test_receipt_satisfies_exact_golden_family_card_contract()
    test_unknown_section_fails_closed()
    test_missing_request_id_fails_closed()
    print("CARD_RUNTIME_RECEIPT_TESTS_PASS")
