"""C3.6-B2 exploratory byte representation comparison. NOT approved canonical JSON.

This module deliberately does not declare Python JSON equal to PostgreSQL
jsonb::text or RFC 8785/JCS. It emits separate domain-labelled digests only.
"""
import hashlib
import json


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def compare_representations(source_raw, release_raw, *, pg_jsonb_text=None):
    """Offline diagnosis only: returns BLOCKED/NONE even if all digests match."""
    errors = ["CANONICALIZATION_POLICY_APPROVAL_REQUIRED"]
    if not isinstance(source_raw, bytes) or not isinstance(release_raw, bytes):
        return {"verdict": "BLOCKED", "authority": "NONE",
                "reason_codes": sorted(errors + ["INVALID_INPUT_BYTES"])}
    result = {"source_bytes_sha256": hashlib.sha256(source_raw).hexdigest(),
              "release_bytes_sha256": hashlib.sha256(release_raw).hexdigest()}
    try:
        source = json.loads(source_raw, object_pairs_hook=_unique,
                            parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
        release = json.loads(release_raw, object_pairs_hook=_unique,
                             parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
        if not isinstance(source, dict) or not isinstance(release, dict):
            raise ValueError("ROOT_NOT_OBJECT")
    except (ValueError, UnicodeError):
        errors.append("INVALID_JSON")
    else:
        # This is Python's stable diagnostic encoding, NOT a released digest format.
        diagnostic = json.dumps(release, sort_keys=True, separators=(",", ":"),
                                ensure_ascii=False, allow_nan=False).encode("utf-8")
        result["python_diagnostic_sha256"] = hashlib.sha256(diagnostic).hexdigest()
        result["raw_release_equals_python_diagnostic"] = release_raw == diagnostic
    if pg_jsonb_text is not None:
        if not isinstance(pg_jsonb_text, str):
            errors.append("INVALID_PG_READBACK_SHAPE")
        else:
            result["pg_jsonb_text_sha256"] = hashlib.sha256(pg_jsonb_text.encode("utf-8")).hexdigest()
            result["raw_release_equals_pg_jsonb_text"] = release_raw == pg_jsonb_text.encode("utf-8")
    return {"verdict": "BLOCKED", "authority": "NONE",
            "reason_codes": sorted(set(errors)), "diagnostics": result}
