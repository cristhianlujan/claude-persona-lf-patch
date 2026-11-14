"""UI Architect canonical runtime adapter: preserve established V5 and V6 contracts."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ALLOWED_ROOT = {"worker","output_type","output_contract_version","governance_envelope","deliverable_created","composer_payload","score","handoff_to_next","self_verdict"}

def _load(alias, relative):
    spec = importlib.util.spec_from_file_location(alias, ROOT / relative)
    if spec is None or spec.loader is None:
        raise ValueError("PROFILE_VALIDATOR_DEPENDENCY_MISSING")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def _schema_errors(payload, relative):
    from jsonschema import Draft202012Validator
    schema = json.loads((ROOT / relative).read_text(encoding="utf-8"))
    return [{"code":"SCHEMA_INVALID","detail":"/".join(map(str,e.path)) or "root"} for e in Draft202012Validator(schema).iter_errors(payload)]

def validate(payload):
    if not isinstance(payload,dict):
        return {"status":"BLOCKED","errors":[{"code":"ROOT_NOT_OBJECT"}]}
    try:
        if payload.get("output_type")=="PRODUCTION_UI_SPEC":
            errors = _schema_errors(payload,"schemas/ui_production_spec.schema.json")
            errors += _load("ui_canonical","validators/validate_ui_architect_output.py").validate(payload)
            if payload.get("output_contract_version")!="UI_PRODUCTION_SPEC_V6":
                errors.append({"code":"V6_REQUIRED_FOR_NEW_RUN"})
            else:
                errors += _load("ui_composer_boundary","validators/validate_composer_payload_boundary.py").validate(payload)
            for k in sorted(set(payload)-ALLOWED_ROOT):
                errors.append({"code":"UNEXPECTED_ROOT_FIELD","detail":k})
        elif "decision_subject" in payload:
            errors = _schema_errors(payload,"schemas/ui_focused_decision.schema.json")
        elif "pipeline_action" in payload:
            errors = _schema_errors(payload,"schemas/ui_missing_input.schema.json")
        else:
            errors = [{"code":"OUTPUT_MODE_UNRECOGNIZED"}]
        return {"status":"PASS" if not errors else "BLOCKED","errors":errors}
    except Exception as exc:
        return {"status":"BLOCKED","errors":[{"code":"VALIDATOR_FAIL_CLOSED","detail":type(exc).__name__}]}

def main():
    """Declared JSON_FILE_ARGUMENT transport: stdout JSON + exit status."""
    import sys
    try:
        if len(sys.argv) != 2:
            raise ValueError("JSON_FILE_ARGUMENT_REQUIRED")
        result = validate(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
        errors = result.get("errors") if isinstance(result, dict) else None
        if not isinstance(errors, list):
            errors = [{"code": "VALIDATOR_OUTPUT_INVALID"}]
        valid = isinstance(result, dict) and result.get("status") == "PASS" and not errors
    except (OSError, ValueError, UnicodeError) as exc:
        valid = False
        errors = [{"code": "VALIDATOR_CLI_INPUT_INVALID", "detail": type(exc).__name__}]
    print(json.dumps({"valid": bool(valid), "errors": errors}, ensure_ascii=False))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
