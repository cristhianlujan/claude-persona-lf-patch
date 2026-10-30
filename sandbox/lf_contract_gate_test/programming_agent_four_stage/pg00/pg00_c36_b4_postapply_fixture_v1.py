"""PG-00 C3.6-B4 offline postapply correlation.

Consumes a general Train verifier result and synthetic catalog readback, but
does NOT authenticate either input. No DB access, no publication authority.
"""
import re

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def inspect_postapply(train_report, expected, catalog_rows):
    errors = {"AUTHENTICATED_POSTAPPLY_READBACK_REQUIRED"}
    if not isinstance(train_report, dict) or train_report.get("result") != "PASS":
        errors.add("TRAIN_RECEIPT_NOT_VERIFIED")
    if not isinstance(expected, dict):
        errors.add("INVALID_EXPECTATION")
        expected = {}
    if not isinstance(catalog_rows, list):
        errors.add("INVALID_CATALOG_READBACK")
        catalog_rows = []
    identity_keys = ("proposal_id", "catalog_version", "release_catalog_sha256")
    if set(expected) != set(identity_keys):
        errors.add("EXPECTATION_FIELDS_MISMATCH")
    for key in identity_keys:
        value = expected.get(key)
        if not isinstance(value, str) or not value:
            errors.add("INVALID_EXPECTED_" + key.upper())
    digest = expected.get("release_catalog_sha256")
    if not isinstance(digest, str) or HEX64.fullmatch(digest) is None:
        errors.add("INVALID_EXPECTED_DIGEST")
    if any(
        not isinstance(row, dict)
        or set(row) != set(identity_keys)
        or any(not isinstance(row.get(key), str) or not row[key]
               for key in identity_keys)
        or not HEX64.fullmatch(row["release_catalog_sha256"])
        for row in catalog_rows
    ):
        errors.add("INVALID_CATALOG_ROW_SHAPE")
    elif any(not isinstance(expected.get(key), str) or not expected[key]
             for key in identity_keys):
        # Do not compare arbitrary Python objects (including cyclic lists).
        errors.add("INVALID_EXPECTATION")
    else:
        matches = [
            row for row in catalog_rows
            if all(row.get(key) == expected.get(key) for key in identity_keys)
        ]
        if len(matches) != 1:
            errors.add("CATALOG_EXACT_ROW_NOT_UNIQUE")
        if len(catalog_rows) != 1:
            errors.add("UNSCOPED_READBACK_ROWS")
    # Even exact fixtures and PASS report are caller-controlled, so never
    # promote the result to TRAIN_APPLIED_VERIFIED or CONSUMABLE_BY_PG.
    return {"verdict": "BLOCKED", "authority": "NONE",
            "consumable_by_pg": False, "reason_codes": sorted(errors)}
