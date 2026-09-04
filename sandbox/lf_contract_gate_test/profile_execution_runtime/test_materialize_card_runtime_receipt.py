from pathlib import Path
import importlib.util

MODULE_PATH = Path(__file__).with_name("materialize_card_runtime_receipt.py")
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
    test_unknown_section_fails_closed()
    test_missing_request_id_fails_closed()
    print("CARD_RUNTIME_RECEIPT_TESTS_PASS")
