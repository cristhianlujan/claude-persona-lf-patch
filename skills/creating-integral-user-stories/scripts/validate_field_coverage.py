"""Every screen field must own a field contract. J04 support."""
import sys

from lf_common import argv_path, emit, load

REQUIRED = ("visibility_mode", "editable", "required", "data_type", "pii_classification")


def main():
    pack = load(argv_path(1))
    screen_fields = {f for f in pack.get("screen_fields", [])}
    contracts = pack.get("fields", [])
    contract_codes = {c.get("field_code") for c in contracts}
    uncontracted = sorted(screen_fields - contract_codes)
    no_visibility, no_edit, pii_no_class, editable_no_audit = [], [], [], []
    for c in contracts:
        if not c.get("visibility_mode"):
            no_visibility.append(c.get("field_code"))
        if c.get("editable") is None:
            no_edit.append(c.get("field_code"))
        if c.get("pii_classification") in (None, "", "UNKNOWN"):
            pii_no_class.append(c.get("field_code"))
        if c.get("editable") and not c.get("audit_required"):
            editable_no_audit.append(c.get("field_code"))
    failed = []
    if uncontracted:
        failed.append("fields_without_contract=%d" % len(uncontracted))
    if no_visibility:
        failed.append("fields_without_visibility_rule=%d" % len(no_visibility))
    if no_edit:
        failed.append("fields_without_editability_rule=%d" % len(no_edit))
    if pii_no_class:
        failed.append("pii_fields_without_classification=%d" % len(pii_no_class))
    if editable_no_audit:
        failed.append("editable_fields_without_audit_strategy=%d" % len(editable_no_audit))
    evidence = {
        "screen_fields": len(screen_fields),
        "field_contracts": len(contracts),
        "required_keys": list(REQUIRED),
        "uncontracted_fields": uncontracted,
    }
    return emit("J04_FIELD_CONTRACTS", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
