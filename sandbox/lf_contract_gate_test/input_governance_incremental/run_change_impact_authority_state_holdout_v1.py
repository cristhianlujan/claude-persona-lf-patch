from change_impact_resolver_readonly_v1 import RuntimeAuthority, resolve_change_impact

cases = [
    (
        "API_DATA_CONTRACT",
        "Cambio solo artefacto; mantener filtros/query y comportamiento visible.",
        RuntimeAuthority(False, False),
        "behavioral_missing_schema_missing",
    ),
    (
        "API_DATA_CONTRACT",
        "Cambiar comportamiento de filtros/query.",
        RuntimeAuthority(False, False),
        "behavioral_missing_schema_missing_material",
    ),
    (
        "API_DATA_CONTRACT",
        "Cambiar comportamiento de filtros/query.",
        RuntimeAuthority(False, True),
        "behavioral_missing_schema_present_material",
    ),
    (
        "API_DATA_CONTRACT",
        "Cambiar payload/formato de exportación.",
        RuntimeAuthority(False, True),
        "behavioral_missing_schema_present_payload",
    ),
]

for surface, mutation, runtime, case_name in cases:
    result = resolve_change_impact(surface, mutation, runtime)
    assert result.decision == "HUMAN_REQUIRED", (case_name, result)
    assert result.uncertainty == "UNKNOWN", (case_name, result)
    assert result.fail_closed is True, (case_name, result)
    assert result.rationale_code == "API_BEHAVIORAL_AUTHORITY_MISSING", (case_name, result)
    assert "API_DATA_CONTRACT" in result.impacted_families, (case_name, result)
    assert "SOURCE_AUTHORITY_PROVENANCE" in result.impacted_families, (case_name, result)

print("CHANGE_IMPACT_AUTHORITY_STATE_HOLDOUT_PASS 4/4")
