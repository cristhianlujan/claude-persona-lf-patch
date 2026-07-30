# Contrato de auditoría y trazabilidad

Versión operativa: `v0.5`. Juez asociado: `J07_AUDIT_TRACEABILITY`.
Validador: `scripts/validate_traceability.py`.

## 1. Propósito

Mantener una cadena verificable desde la fuente hasta cada regla, criterio, prueba, evento de auditoría y evidencia.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `source_snapshot` | Fuente y hash de origen. |
| `story_pack` | Reglas, criterios, pruebas y acciones. |
| `audit_policy` | Eventos y tratamiento de valores sensibles. |
| `traceability_matrix` | Relaciones fuente-regla-criterio-prueba-evidencia. |

## 3. Preflight

1. Confirmar entradas, versión, referencias y SHA-256.
2. Confirmar independencia entre worker y J07.
3. Confirmar `judge_version` y `executor_identity`.
4. Detener con `BLOCKED` ante matriz/fuente ausente, conflicto o metadata faltante.

## 4. Procedimiento obligatorio

1. Enumerar criterios, validaciones, pruebas y eventos de auditoría.
2. Exigir código y `source_ref` por evento de auditoría.
3. Exigir `source_ref` por criterio y validación.
4. Enlazar cada criterio y regla crítica con al menos una prueba.
5. Exigir `criterion_ref` o `rule_ref` resoluble por prueba.
6. Exigir `evidence_path` y códigos de prueba únicos.
7. Ejecutar positivo, negativo y metadata ausente contra el validador real.

## 5. Reglas e invariantes

- Auditoría no se sustituye por analytics o logs.
- Una ausencia contractual requiere `audit.reason` explícita o queda pendiente.
- Cada referencia es resoluble y versionada.
- Pruebas huérfanas, sin evidencia o duplicadas impiden PASS.
- No se fabrican referencias ni se eliminan assertions para cerrar.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/audit`, matriz de trazabilidad y envelope `schemas/judge-result.schema.json` v0.5.

## 7. Assertions de paso

```text
audit_contract_missing = 0
audit_events_without_code = 0
audit_events_without_source_reference = 0
criteria_without_source_reference = 0
rules_without_source_reference = 0
criteria_without_test_reference = 0
critical_rules_without_test = 0
tests_without_story_reference = 0
tests_without_evidence_path = 0
duplicate_test_codes = 0
```

## 8. Condiciones de bloqueo

```text
traceability_matrix_missing = true
source_reference_unresolvable = true
metadata_or_evidence_unavailable = true
retry_limit_exhausted = true
```

## 9. Caso positivo ejecutable

```json
{
  "core": {"acceptance_criteria": [{"criterion_code": "AC-01", "source_ref": "SRC-1"}]},
  "validations": [{"validation_code": "VAL-01", "source_ref": "SRC-2", "critical": true}],
  "tests": [
    {"test_code": "T-01", "criterion_ref": "AC-01", "evidence_path": "evidence/t01.json"},
    {"test_code": "T-02", "rule_ref": "VAL-01", "evidence_path": "evidence/t02.json"}
  ],
  "audit": {"events": [{"audit_event_code": "AUD-01", "source_ref": "SRC-3"}]}
}
```

Resultado esperado: `PASS_WITH_EVIDENCE`.

## 10. Caso negativo ejecutable

```json
{
  "core": {"acceptance_criteria": [{"criterion_code": "AC-01"}]},
  "validations": [{"validation_code": "VAL-01", "critical": true}],
  "tests": [{"test_code": "T-01"}, {"test_code": "T-01"}],
  "audit": {}
}
```

Resultado esperado: `RETURN_TO_WORKER` con roturas de fuente, cobertura, evidencia y duplicidad.

## 11. Reparación y handoff

Reparar exclusivamente el objeto asociado; no reducir umbral, borrar assertion, fabricar referencias ni autoaprobar. Tras `retry_limit = 2`, devolver `BLOCKED`. Entregar comando, ejecutor, conteos, fallas, hashes y `evidence_refs`.

## 12. Fuentes de diseño no normativas

- **anthropics/skills:** evals objetivas y reparación iterativa.
- **microsoft/vscode:** workflows, formatos y stop conditions.
- **freeCodeCamp/freeCodeCamp:** referencias, unicidad y rechazo determinista.
- **Significant-Gravitas/AutoGPT:** persistencia y límites operativos.

Los contratos LF prevalecen.
