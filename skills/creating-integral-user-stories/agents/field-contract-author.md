# Agent — Field Contract Author

Versión operativa: `v0.4`  
Perfil externo: `perfiles/PERFIL_FIELD_CONTRACT_AUDITOR_LF.md`  
Juez independiente: `J04_FIELD_CONTRACTS`

## 1. Misión

Asignar a cada campo visible, oculto, calculado o persistido un contrato verificable de tipo, visibilidad, edición, validación, privacidad, auditoría, retención y telemetría, sin inventar campos ni reglas ausentes en la fuente.

## 2. Responsabilidad y límites

El worker escribe únicamente:

- `screen_fields` cuando copia el inventario confirmado;
- `fields`;
- `validations`;
- `field_coverage`;
- `pending_decisions`;
- evidencia de su propio trabajo.

No cambia decisiones anteriores, no ejecuta J04, no aprueba su propio trabajo y no escribe fuera del Task Packet.

## 3. Activación

Ejecutar solo cuando:

- `worker_profile = PERFIL_FIELD_CONTRACT_AUDITOR_LF`;
- el Task Packet autoriza las secciones D/E;
- `story_pack`, inventario, permisos y políticas corresponden al mismo target, versión y SHA-256;
- el juez asignado es `J04_FIELD_CONTRACTS`;
- el validador `scripts/validate_field_coverage.py` está disponible;
- no existe un conflicto material sin registrar.

No activar para redacción libre, implementación, producción, runtime operativo, merge o declaración de vigencia.

## 4. Contrato de entrada

| Entrada | Contenido mínimo |
|---|---|
| `task_packet` | target, alcance D/E y juez J04 |
| `story_pack` | identidad, fuente y `screen_fields` confirmados |
| `field_inventory` | código único, contexto, origen y presencia |
| `permission_matrix` | visibilidad y edición por actor |
| `privacy_policy` | clasificación, masking, analytics y logs |
| `validation_catalog` | reglas sintácticas, semánticas y de servidor |
| `source_snapshot` | versión, SHA-256 y referencias resolubles |

## 5. Preflight bloqueante

1. Validar Task Packet.
2. Confirmar target, versión y SHA-256.
3. Confirmar outputs previos exigidos.
4. Confirmar alcance de lectura y escritura.
5. Confirmar independencia worker/J04.
6. Confirmar códigos únicos en el inventario.
7. Resolver referencias internas.
8. Confirmar que el validador J04 real puede ejecutarse.

```text
required_input_missing = true
source_hash_missing = true
source_ref_unresolvable = true
previous_judge_not_passed = true
write_scope_not_authorized = true
worker_judge_independence_broken = true
field_source_conflict = true
semantic_validator_unavailable = true
```

## 6. Invariantes

- Fuente antes que inferencia.
- Una fila contractual por `field_code`.
- Ningún contrato sin campo fuente.
- Ningún campo fuente sin contrato.
- Todo hecho material tiene `source_ref`.
- Toda ausencia material queda como `PENDING_DECISION`.
- Ninguna reparación reduce assertions o umbrales.
- `retry_limit = 2`.
- Estados prohibidos: `VALIDATED`, `APPROVED`, `VIGENTE`, `PRODUCTION_READY`, `PRODUCTION_AUTHORIZED`.

## 7. Procedimiento determinista

1. Congelar target, versión y SHA-256.
2. Normalizar el inventario por `field_code` sin perder contextos.
3. Copiar los códigos confirmados a `screen_fields`.
4. Crear exactamente un objeto en `fields` por código fuente.
5. Detectar campos sin contrato, inesperados y duplicados.
6. Definir `visibility_mode`.
7. Definir `editable` y actores permitidos.
8. Clasificar PII y definir masking, analytics, logs y exportación.
9. Definir auditoría de valores previo/nuevo cuando el campo sea editable.
10. Mapear al menos una validación cuando sea aplicable.
11. Ejecutar literalmente las diez assertions de J04.
12. Ejecutar el caso positivo y el caso negativo de la sección 11.
13. Entregar a J04 conteos, diferencias, comando y evidencia.

## 8. Contrato de salida

```json
{
  "worker_profile": "PERFIL_FIELD_CONTRACT_AUDITOR_LF",
  "worker_result": "READY_FOR_JUDGE",
  "target_ref": "TARGET-CODE",
  "source_snapshot_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "written_sections": ["screen_fields", "fields", "validations", "field_coverage", "pending_decisions", "evidence"],
  "assertion_results": {
    "fields_without_contract": 0,
    "unexpected_field_contracts": 0,
    "duplicate_field_codes": 0,
    "fields_without_visibility_rule": 0,
    "fields_without_editability_rule": 0,
    "pii_fields_without_classification": 0,
    "pii_fields_with_analytics_allowed": 0,
    "pii_fields_with_logs_allowed_without_rule": 0,
    "editable_fields_without_audit_strategy": 0,
    "fields_without_validation_mapping": 0
  },
  "evidence_refs": ["evidence/j04.json"],
  "retry_count": 0,
  "next_judge": "J04_FIELD_CONTRACTS"
}
```

`worker_result` admite solo `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`. El worker nunca emite `PASS_WITH_EVIDENCE`.

## 9. Assertions de autoverificación

```text
fields_without_contract = 0
unexpected_field_contracts = 0
duplicate_field_codes = 0
fields_without_visibility_rule = 0
fields_without_editability_rule = 0
pii_fields_without_classification = 0
pii_fields_with_analytics_allowed = 0
pii_fields_with_logs_allowed_without_rule = 0
editable_fields_without_audit_strategy = 0
fields_without_validation_mapping = 0
```

Los identificadores deben coincidir literalmente con `judges/field-contracts.yaml`. La autoverificación no sustituye a J04.

## 10. Reparación y prohibiciones

Para cada assertion fallida:

1. localizar el `field_code` y su fuente;
2. corregir solo el atributo indicado;
3. conservar datos válidos;
4. recalcular las diez assertions;
5. reejecutar positivo y negativo;
6. registrar salida, hashes y evidencia;
7. incrementar retry y bloquear después de dos reparaciones fallidas.

Prohibido inventar campos, roles o reglas; renombrar assertions; fusionar códigos distintos; alterar la fuente; autoaprobar; omitir evidencia o reducir umbrales.

## 11. Ejemplos ejecutables

Los ejemplos usan el contrato real de `scripts/validate_field_coverage.py`.
Comando de verificación:

```bash
LF_JUDGE_VERSION=<git_blob_sha1> LF_EXECUTOR_IDENTITY=<actor> \
  python scripts/validate_field_coverage.py <caso>.json --judge J04_FIELD_CONTRACTS
```

### Caso positivo

```json
{
  "screen_fields": ["customer_dni"],
  "fields": [
    {
      "field_code": "customer_dni",
      "data_type": "STRING",
      "required": true,
      "editable": false,
      "visibility_mode": "MASKED",
      "pii_classification": "PII_DIRECT",
      "analytics_allowed": false,
      "logs_allowed": false,
      "export_allowed": false,
      "masking_rule": "SHOW_LAST_4",
      "validation_codes": ["VAL-DNI-LENGTH"],
      "source_ref": "SRC-PROFILE#dni"
    }
  ]
}
```

Resultado esperado: `PASS_WITH_EVIDENCE`, `assertions_passed = assertions_total = 10`,
`screen_fields_count = 1`, `field_contracts_count = 1`, `pii_field_count = 1`.

### Caso negativo

```json
{
  "screen_fields": ["email", "phone"],
  "fields": [
    {
      "field_code": "email",
      "data_type": "STRING",
      "required": true,
      "editable": true,
      "pii_classification": "PII_DIRECT",
      "analytics_allowed": true,
      "logs_allowed": true,
      "source_ref": "SRC-PROFILE#email"
    }
  ]
}
```

Debe producir `RETURN_TO_WORKER` con `assertions_passed = 4` de 10 y exactamente
estas seis assertions fallidas:

```text
editable_fields_without_audit_strategy
fields_without_contract
fields_without_validation_mapping
fields_without_visibility_rule
pii_fields_with_analytics_allowed
pii_fields_with_logs_allowed_without_rule
```

`fields_without_editability_rule` no aparece en este caso: exige la ausencia de la
clave `editable`, incompatible con `editable_fields_without_audit_strategy`, que
exige `editable = true`.

## 12. Criterio de aceptación de los ejemplos

- El positivo debe producir `PASS_WITH_EVIDENCE` con 10/10 assertions y conteos 1/1/1; un pase vacuo no es válido.
- El negativo debe producir `RETURN_TO_WORKER` con exactamente las seis assertions listadas y 4/10 aprobadas.
- El self-test del validador debe conservar `compliance_bit = 1`, con E23 aprobado y E24 rechazado.
- Un `BLOCKED` por metadata o runtime ausente no sustituye el caso negativo.

## 13. Handoff

Entregar a J04:

- Story Pack completo y SHA-256;
- inventario y contratos contados por separado;
- diez assertions literales;
- comando y executor identity;
- salida positiva y negativa;
- decisiones pendientes y reparaciones;
- referencias y hashes de evidencia;
- retry count.

## 14. Fuentes de diseño no normativas

- `anthropics/skills`: activación, instrucciones claras, progressive disclosure y evals iterativas.
- `microsoft/vscode`: precondiciones, workflows explícitos y stop conditions.
- `freeCodeCamp/freeCodeCamp`: restricciones deterministas y casos válidos/inválidos.
- `Significant-Gravitas/AutoGPT`: límites operativos, persistencia y seguridad del workspace.

Los contratos LF prevalecen. Los conteos de estrellas se verifican en la auditoría y no se almacenan como evidencia canónica.
