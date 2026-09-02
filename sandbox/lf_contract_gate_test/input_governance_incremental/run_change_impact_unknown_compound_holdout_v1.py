from change_impact_resolver_readonly_v1 import RuntimeAuthority, resolve_change_impact

runtime = RuntimeAuthority(
    behavioral_contract_present=True,
    operation_schema_authority_materialized=False,
)

unknown_compounds = [
    ("ACTION_SEMANTICS", "Mantener EXPORT, pero alterar radicalmente una propiedad no catalogada."),
    ("PERMISSION_BINDING", "Conservar el permiso; además aplicar una modificación no reconocida."),
    ("ROUTING_NAVIGATION", "Mantener la ruta y simultáneamente cambiar un comportamiento interno desconocido."),
    ("DESIGN_COMPONENT", "Conservar el componente; no obstante modificar una propiedad no clasificada."),
    ("FIELD_CONTRACT", "Mantener el campo y, a la vez, alterar una característica desconocida."),
]

for surface, mutation in unknown_compounds:
    result = resolve_change_impact(surface, mutation, runtime)
    assert result.decision == "HUMAN_REQUIRED", (surface, mutation, result)
    assert result.uncertainty == "MIXED", (surface, mutation, result)
    assert result.fail_closed is True, (surface, mutation, result)
    assert result.rationale_code == "CONFLICTING_SEMANTIC_ATOMS", (surface, mutation, result)

# Known explicitly non-material compound remains bounded.
safe = resolve_change_impact(
    "COPY_RECONCILIATION",
    "Mantener la copy canónica, pero solo ajustar whitespace sin efecto visual.",
    runtime,
)
assert safe.decision == "SCOPED_CANDIDATE", safe
assert safe.impacted_families == ("VISUAL_EVIDENCE",), safe
assert safe.uncertainty == "NONE", safe

print("CHANGE_IMPACT_UNKNOWN_COMPOUND_HOLDOUT_PASS 6/6")
