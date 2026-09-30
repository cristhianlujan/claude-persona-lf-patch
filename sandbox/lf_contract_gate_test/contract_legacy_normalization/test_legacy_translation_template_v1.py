from __future__ import annotations

import copy
import legacy_translation_template_v1 as sut


def row(op, code, sections):
    return {
        "operation_code": op,
        "contract_code": code,
        "contract_path": f"supabase://public/lf_operation_contracts/{op}/{code}",
        "contract_sha": None,
        **copy.deepcopy(sections),
        "status": "ACTIVE_ENFORCEMENT",
        "created_at": "ignored-audit-field",
    }


def template(catalog, tid):
    return next(t for t in catalog["templates"] if t["template_id"] == tid)


def main():
    catalog = sut.load_catalog()
    assert catalog["coverage"]["contracts_covered"] == 11
    assert catalog["coverage"]["semantic_definitions_covered"] == 3
    rule = template(catalog, "RULE_MUTATION_V1")
    app = template(catalog, "APP_SHELL_MUTATION_V1")
    ekb = template(catalog, "PRE_EKB_GATE_V1")

    r1 = row("ACTUALIZACION_REGLA_LF", "CONTRACT-ACTUALIZACION_REGLA_LF-v0.1", rule["source_sections"])
    r2 = row("CREACION_REGLA_LF", "CONTRACT-CREACION_REGLA_LF-v0.1", rule["source_sections"])
    a1 = row("ACTUALIZACION_APP_SHELL_LF", "CONTRACT-ACTUALIZACION_APP_SHELL_LF-v0.1", app["source_sections"])
    a2 = row("CREACION_APP_SHELL_LF", "CONTRACT-CREACION_APP_SHELL_LF-v0.1", app["source_sections"])
    e1 = row("ANALISIS_RIESGO_CONTENIDO_LF", "CONTRACT-PRE-EKB-GATE-LF-v0.1", ekb["source_sections"])
    e2 = row("ORQUESTACION_PIPELINE_LF", "CONTRACT-PRE-EKB-GATE-LF-v0.1", ekb["source_sections"])

    cases = 0
    for source, tid in [
        (r1, "RULE_MUTATION_V1"),
        (r2, "RULE_MUTATION_V1"),
        (a1, "APP_SHELL_MUTATION_V1"),
        (a2, "APP_SHELL_MUTATION_V1"),
        (e1, "PRE_EKB_GATE_V1"),
        (e2, "PRE_EKB_GATE_V1"),
    ]:
        chosen = sut.select_exact_template(source, catalog)
        assert chosen["template_id"] == tid
        translation = sut.instantiate_translation(source, chosen)
        assert translation["coverage_mode"] == "FULL"
        assert len(translation["source_contract_sha256"]) == 64
        cases += 1

    assert sut.instantiate_translation(r1, rule)["source_contract_sha256"] != sut.instantiate_translation(r2, rule)["source_contract_sha256"]
    cases += 1

    drift = copy.deepcopy(r1)
    drift["allowed"]["automatic_promotion"] = True
    try:
        sut.select_exact_template(drift, catalog)
    except sut.LegacyTranslationTemplateError as exc:
        assert str(exc) == "exact_template_not_found"
    else:
        raise AssertionError("drift must not exact-match")
    cases += 1

    try:
        sut.instantiate_translation(drift, rule)
    except sut.LegacyTranslationTemplateError as exc:
        assert str(exc) == "template_source_sections_mismatch"
    else:
        raise AssertionError("drift must not instantiate")
    cases += 1

    r1_with_audit = copy.deepcopy(r1)
    r1_with_audit["updated_at"] = "other-audit"
    assert sut.select_exact_template(r1_with_audit, catalog)["template_id"] == "RULE_MUTATION_V1"
    cases += 1

    pre_ekb_mappings = {m["source_pointer"]: m for m in ekb["mappings"]}
    assert pre_ekb_mappings["/blocked/blocked_when"]["typed_term"]["predicate"]["op"] == "ANY"
    cases += 1
    assert pre_ekb_mappings["/required_before_write/task_signature_required"]["typed_term"]["predicate"]["op"] == "ALL"
    cases += 1
    assert pre_ekb_mappings["/required_before_write/minimum_error_codes"]["typed_term"]["predicate"]["op"] == "EQ"
    cases += 1

    assert cases == 13
    print("PASS_LEGACY_TRANSLATION_TEMPLATE_V1=13/13")


if __name__ == "__main__":
    main()
