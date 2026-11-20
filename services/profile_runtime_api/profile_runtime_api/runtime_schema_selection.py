"""One fail-closed schema selector shared by API and native profile bridge.

The profile binding declares modes, shape keys and default aliases. The only
external translation here maps the public UI_* transport vocabulary into the
binding's mode vocabulary, without any per-profile slug branch.
"""
from __future__ import annotations

EXTERNAL_MODE_TO_BINDING = {
    "UI_PRODUCTION_SPEC": "PRODUCTION_SPEC",
    "UI_FOCUSED_DECISION": "FOCUSED_DECISION",
    "UI_MISSING_INPUT": "MISSING_INPUT",
}

class RuntimeSchemaSelectionError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        super().__init__(f"{code}: {detail}" if detail else code)

def _canonical_mode(value: str) -> str:
    return EXTERNAL_MODE_TO_BINDING.get(value, value)

def select_schema_relative(
    schema_contract: dict,
    *, output_mode: str = "AUTO", payload: dict | None = None
) -> str:
    """Return the declared relative schema path; never synthesize a schema.

    Selection order: explicit transport mode and canonical payload form must
    agree, otherwise reject; default applies only when no distinct form is
    selected. Undeclared modes and ambiguous shape keys fail closed.
    """
    if not isinstance(schema_contract, dict):
        raise RuntimeSchemaSelectionError("RUNTIME_SCHEMA_CONTRACT_INVALID")
    default = schema_contract.get("default")
    modes = schema_contract.get("output_modes", {})
    default_mode = schema_contract.get("default_mode")
    aliases = schema_contract.get("output_type_modes", {})
    shapes = schema_contract.get("shape_modes", {})
    if (not isinstance(default, str) or not default.strip()
        or not isinstance(modes, dict) or not isinstance(aliases, dict)
        or not isinstance(shapes, dict)
        or any(not isinstance(k, str) or not isinstance(v, str) for mapping in (modes, aliases, shapes) for k, v in mapping.items())
        or (default_mode is not None and (not isinstance(default_mode, str) or not default_mode))):
        raise RuntimeSchemaSelectionError("RUNTIME_SCHEMA_CONTRACT_INVALID")

    if output_mode is None:
        output_mode = "AUTO"
    if not isinstance(output_mode, str):
        raise RuntimeSchemaSelectionError("OUTPUT_MODE_UNDECLARED")
    explicit = None if output_mode == "AUTO" else _canonical_mode(output_mode)
    form = None
    if payload is not None:
        if not isinstance(payload, dict):
            raise RuntimeSchemaSelectionError("OUTPUT_FORM_INVALID")
        output_type = payload.get("output_type")
        if output_type is not None:
            if not isinstance(output_type, str) or not output_type:
                raise RuntimeSchemaSelectionError("OUTPUT_FORM_INVALID")
            form = _canonical_mode(aliases.get(output_type, output_type))
        matches = {_canonical_mode(mode) for marker, mode in shapes.items() if marker in payload}
        if len(matches) > 1:
            raise RuntimeSchemaSelectionError("OUTPUT_FORM_AMBIGUOUS")
        shape_mode = next(iter(matches), None)
        if form and shape_mode and form != shape_mode:
            raise RuntimeSchemaSelectionError("OUTPUT_FORM_CONFLICT")
        form = form or shape_mode

    if explicit is not None and form is not None and explicit != form:
        raise RuntimeSchemaSelectionError("OUTPUT_MODE_FORM_CONFLICT")
    chosen = explicit or form
    if chosen is None or chosen == default_mode:
        return default
    if chosen in modes and isinstance(modes[chosen], str) and modes[chosen].strip():
        return modes[chosen]
    # Profiles with a single default schema can carry their own output_type
    # without declaring a redundant one-to-one output_modes mapping.
    if not modes and default_mode is None and explicit is None:
        return default
    raise RuntimeSchemaSelectionError("OUTPUT_MODE_UNDECLARED", str(chosen))
