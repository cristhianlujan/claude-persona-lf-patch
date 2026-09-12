from change_impact_resolver_readonly_v1 import RuntimeAuthority, resolve_change_impact

runtime = RuntimeAuthority(
    behavioral_contract_present=True,
    operation_schema_authority_materialized=False,
)

cases = [
    ("ACTION_SEMANTICS", "Mantener EXPORT pero cambiar a DELETE."),
    ("PERMISSION_BINDING", "Mantener el permiso y a la vez quitar la autorización."),
    ("ROUTING_NAVIGATION", "Mantener la ruta actual pero redirigir a otra ruta existente."),
    ("DESIGN_COMPONENT", "Mantener el componente pero usar un token obsoleto."),
    ("FIELD_CONTRACT", "Mantener el campo y hacerlo obligatorio en el mismo cambio."),
]

for surface, mutation in cases:
    result = resolve_change_impact(surface, mutation, runtime)
    assert result.decision == "HUMAN_REQUIRED", (surface, mutation, result)
    assert result.uncertainty == "MIXED", (surface, mutation, result)
    assert result.fail_closed is True, (surface, mutation, result)
    assert result.rationale_code == "CONFLICTING_SEMANTIC_ATOMS", (surface, mutation, result)

print("CHANGE_IMPACT_CONFLICT_HOLDOUT_PASS 5/5")
