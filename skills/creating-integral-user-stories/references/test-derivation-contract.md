# Contrato de derivación de pruebas

Versión operativa: `v0.6`.  
Worker: `STORY_TEST_DERIVER_WORKER`.  
Juez independiente: `J10_TEST_COVERAGE` v0.6.  
Runtime reservado al juez: `scripts/validate_test_coverage.py`.

## 1. Propósito

Definir la derivación determinista de pruebas, fixtures exactos, reporte externo
de cobertura y evidencia del worker desde un Story Pack aprobado hasta J09,
sin modificar el comportamiento esperado y sin permitir autoejecución ni
autoaprobación.

Este contrato separa tres responsabilidades:

1. el worker prepara cuatro salidas autorizadas;
2. un ejecutor independiente construye y ejecuta el handoff de J10;
3. J10 emite el resultado contractual de cobertura.

## 2. Entradas del worker

El worker recibe exactamente el contexto autorizado por el Task Packet:

| Entrada | Contenido obligatorio |
|---|---|
| `task_packet` | worker, juez, target, scopes, outputs y `retry_limit` |
| `story_pack` | Story Pack A–N congelado, con criterios codificados |
| `critical_rules` | reglas críticas, familia, aplicabilidad y fuente |
| `traceability_matrix` | fuente → regla → criterio, con referencias resolubles |
| `error_catalog` | errores críticos y políticas de reintento |
| `test_environment` | actores, tenants, estados, datasets y restricciones |
| `source_snapshot` | versión, SHA-256 y referencias de fuente |
| `previous_judge_evidence` | evidencia aplicable de J01–J09 |

Todas las entradas pertenecen al mismo target, versión y snapshot. El worker no
inventa valores ausentes ni reemplaza una fuente aprobada.

## 3. Preflight bloqueante

Antes de derivar contenido, verificar en orden:

1. Task Packet, worker, juez y target coinciden;
2. existe un Story Pack singular y congelado;
3. versión y SHA-256 de fuente están presentes;
4. J01–J09 aplicables tienen evidencia resoluble;
5. criterios y reglas poseen códigos y referencias;
6. catálogo de errores, matriz y ambiente pertenecen al mismo snapshot;
7. el scope autoriza las cuatro salidas del worker;
8. los schemas de pruebas y reporte están disponibles;
9. `worker_identity` y `executor_identity` están declaradas y son distintas;
10. el runtime J10 existe;
11. el runtime J10 está registrado en la ubicación canónica;
12. el SHA del runtime coincide entre archivo, `main`, registro y evidencia;
13. `judge_version = v0.6`;
14. ninguna condición exige modificar A–N, reglas, schemas o jueces.

Bloquear si una condición falla. No degradar el umbral ni presentar el handoff
como listo.

Registro canónico del runtime:

```text
supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_TEST_COVERAGE
```

## 4. Alcance de escritura

El worker puede escribir únicamente:

1. `story_pack.tests`;
2. `fixtures[test_code]` como mapa externo;
3. `coverage_report` conforme a
   `schemas/coverage-report.schema.json`;
4. `worker_evidence` como sidecar externo.

El worker no escribe `test_coverage` dentro del Story Pack. No modifica
criterios, reglas, permisos, estados, errores, contratos transversales, schemas
o jueces para obtener un resultado favorable.

## 5. Invariantes de derivación

- Cada criterio tiene al menos una prueba positiva.
- Cada regla crítica tiene prueba o no-aplicabilidad aprobada.
- Cada permiso aplicable tiene un caso `DENY`.
- Cada regla tenant tiene un caso cross-tenant.
- Cada transición aplicable tiene prueba de estado.
- Cada acción idempotente tiene prueba de duplicidad.
- Cada error crítico tiene prueba.
- Cada recurso mutable compartido tiene prueba de concurrencia.
- Cada prueba contiene `criterion_ref` o `rule_ref` resoluble.
- Cada prueba contiene un resultado observable.
- Cada `test_code` resuelve un fixture externo exacto.
- Los códigos son únicos.
- Los datos son controlados y no contienen PII real.
- Una lista de títulos, pasos genéricos o fixtures vacíos no es cobertura.
- `retry_limit = 2`.

## 6. Procedimiento determinista del worker

1. Congelar versión, SHA, criterios, reglas, errores y referencias.
2. Crear positivos por criterio.
3. Crear negativos, límites y regresión por regla aplicable.
4. Crear cobertura de permisos, tenant, estados, idempotencia, concurrencia,
   errores, seguridad y calidad transversal.
5. Construir `story_pack.tests[]` con códigos y referencias resolubles.
6. Construir `fixtures[test_code]` con valores exactos.
7. Construir el `coverage_report` externo.
8. Validar estructuralmente pruebas y reporte contra sus schemas.
9. Calcular los trece indicadores con actual, expected y evidencia.
10. Construir el payload exacto de cinco propiedades para J10.
11. Construir el sidecar separado del worker.
12. Entregar ambas piezas a un ejecutor J10 independiente.
13. Reparar únicamente salidas del worker cuando J10 retorne fallas reparables.
14. Tras dos reintentos, retornar `BLOCKED` con evidencia acumulada.

El worker no ejecuta el runtime J10 en ningún paso.

## 7. Contrato de prueba canónica

Cada prueba escrita en `story_pack.tests` cumple el schema canónico:

```json
{
  "test_code": "TEST-TENANT-001",
  "family": "TENANT",
  "criterion_ref": null,
  "rule_ref": "SEC-CROSS-TENANT-DENY",
  "preconditions": [
    "actor belongs to TENANT-A",
    "record belongs to TENANT-B"
  ],
  "steps": [
    "request REC-B-001 through the authorized application path"
  ],
  "expected_result": "access is denied and no record attributes are returned",
  "negative": true,
  "critical": true,
  "automatable": true,
  "actor_profile": "UNAUTHORIZED_USER",
  "tenant_scope": "CROSS_TENANT",
  "evidence_path": "evidence/tests/TEST-TENANT-001.json"
}
```

No se aceptan resultados genéricos, referencias rotas ni pruebas huérfanas.

## 8. Contrato de fixture externo

Cada `test_code` posee un fixture externo exacto:

```json
{
  "actor": "UNAUTHORIZED_USER",
  "tenant": "TENANT-A",
  "initial_state": {
    "authenticated": true,
    "record_tenant": "TENANT-B"
  },
  "exact_inputs": {
    "record_id": "REC-B-001"
  },
  "steps": [
    "request REC-B-001 through the authorized application path"
  ],
  "expected_result": "access is denied and no record attributes are returned",
  "evidence_path": "evidence/tests/TEST-TENANT-001.json"
}
```

Campos obligatorios:

```text
actor
tenant
initial_state
exact_inputs
steps
expected_result
evidence_path
```

Fixtures con placeholders, `TODO`, `TBD`, datos de producción, PII real o pasos
genéricos son inválidos.

## 9. Reporte externo de cobertura

El `coverage_report` es externo al Story Pack y debe validar contra
`schemas/coverage-report.schema.json`.

Debe contener, como mínimo:

- identidad del target y versión;
- SHA-256 de entrada;
- criterios y reglas inventariados;
- pruebas y fixtures generados;
- familias cubiertas;
- no-aplicabilidades aprobadas;
- trece indicadores con actual y expected;
- referencias de evidencia;
- decisiones pendientes;
- identidad del worker;
- hashes de salidas.

Una validación estructural local no ejecuta J10 ni concede aprobación.

## 10. Trece indicadores obligatorios

```text
acceptance_criteria_without_test = 0
critical_rule_without_test = 0
permission_without_negative_test = 0
tenant_rule_without_cross_tenant_test = 0
state_transition_without_state_test = 0
idempotent_action_without_duplicate_test = 0
critical_error_without_test = 0
mutable_shared_resource_without_concurrency_test = 0
tests_without_exact_fixture = 0
tests_without_expected_result = 0
tests_without_traceability_ref = 0
orphan_tests = 0
vacuous_pass_count = 0
```

Cada indicador conserva:

- valor actual;
- valor esperado;
- códigos afectados;
- referencias de evidencia;
- reparación propuesta cuando el valor no es cero.

## 11. Handoff exacto a J10

El payload del juez contiene exactamente cinco propiedades top-level:

```json
{
  "story_pack": {
    "identity": {},
    "core": {
      "acceptance_criteria": []
    },
    "tests": []
  },
  "critical_rules": [],
  "fixtures": {},
  "traceability_matrix": {},
  "test_environment": {}
}
```

Reglas del handoff:

- no agregar `task_packet`, `coverage_report`, `worker_evidence`,
  `error_catalog` ni `source_snapshot` al payload;
- `story_pack.tests` contiene solo pruebas canónicas;
- `fixtures` permanece externo al Story Pack;
- `traceability_matrix` y `test_environment` son obligatorios;
- reporte y sidecar se entregan mediante `evidence_refs`;
- el worker no ejecuta el payload ni selecciona el resultado del juez.

## 12. Sidecar del worker

El sidecar permanece separado del payload J10:

```json
{
  "worker_profile": "PERFIL_STORY_TEST_DERIVER_LF",
  "worker_identity": "STORY_TEST_DERIVER_WORKER",
  "worker_result": "READY_FOR_J10",
  "target_ref": "<TARGET>",
  "source_version": "<VERSION>",
  "source_snapshot_sha256": "<64-hex>",
  "written_outputs": [
    "story_pack.tests",
    "fixtures",
    "coverage_report",
    "worker_evidence"
  ],
  "thirteen_self_checks": {},
  "test_codes": [],
  "fixture_hashes": {},
  "coverage_report_sha256": "<64-hex>",
  "runtime_path": "scripts/validate_test_coverage.py",
  "runtime_sha256_observed": "<64-hex>",
  "runtime_registration": "supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_TEST_COVERAGE",
  "evidence_refs": [],
  "pending_decisions": [],
  "retry_count": 0,
  "next_judge": "J10_TEST_COVERAGE"
}
```

`worker_result` solo puede ser:

```text
READY_FOR_J10
RETURN_TO_WORKER
BLOCKED
```

`READY_FOR_J10` significa preparación completa, no PASS.

## 13. Ejecución reservada al juez

Solo un ejecutor independiente puede ejecutar:

```bash
LF_EXECUTOR_IDENTITY=<independent_executor> \
LF_WORKER_IDENTITY=STORY_TEST_DERIVER_WORKER \
LF_JUDGE_VERSION=v0.6 \
LF_VALIDATOR_REGISTERED_SHA256=<registered_sha256> \
LF_VALIDATOR_REGISTRATION=supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_TEST_COVERAGE \
python scripts/validate_test_coverage.py j10-input.json \
  --evidence-ref <coverage_report_ref> \
  --evidence-ref <worker_evidence_ref>
```

Invariantes:

```text
worker_identity != executor_identity
worker_must_not_execute_own_judge = true
worker_must_not_modify_judge_contract = true
worker_must_not_select_own_pass_result = true
```

## 14. Resultados y bloqueo

Resultados del worker:

```text
READY_FOR_J10
RETURN_TO_WORKER
BLOCKED
```

Resultados de J10:

```text
PASS_WITH_EVIDENCE
RETURN_TO_WORKER
BLOCKED
FAIL
```

El worker bloquea cuando:

- falta una entrada, versión o SHA obligatoria;
- el comportamiento esperado es indefinido o contradictorio;
- el scope no autoriza una de las cuatro salidas;
- falta un schema requerido;
- el runtime J10 no existe o no está registrado;
- el SHA del runtime no coincide con archivo, `main` y registro;
- falta identidad explícita del worker o del ejecutor;
- worker y ejecutor son la misma identidad;
- una reparación exige cambiar una salida aprobada de otro step;
- se alcanzó el segundo reintento.

## 15. Reparación

Cuando J10 retorna una falla reparable:

1. identificar assertion, actual, expected y objeto afectado;
2. reparar únicamente prueba, fixture, reporte o sidecar;
3. conservar hashes y evidencia previa;
4. no reducir umbrales ni borrar assertions;
5. no fabricar referencias ni cambiar la fuente;
6. incrementar `retry_count`;
7. reenviar a un ejecutor independiente;
8. bloquear después del segundo reintento.

## 16. Prohibiciones

- modificar A–N, criterios o reglas para hacer pasar pruebas;
- omitir negativos o fixtures externos;
- crear pruebas sin resultado observable;
- usar placeholders, PII real o evidencia vacía;
- escribir `test_coverage` dentro del Story Pack;
- omitir `traceability_matrix` o `test_environment` del handoff;
- agregar sidecar o reporte al payload J10;
- reducir o eliminar indicadores;
- ejecutar J10 como worker;
- usar identidad de juez;
- autoaprobar o emitir `PASS_WITH_EVIDENCE`;
- declarar producción, release o merge autónomo.

## 17. Evidencia mínima

```text
worker_identity
executor_identity
source_version
source_snapshot_sha256
criteria_inventory
critical_rule_inventory
error_inventory
families_applicable
test_codes
fixture_hashes
coverage_report_sha256
thirteen_self_check_results
runtime_path
runtime_sha256_observed
registered_runtime_sha256
runtime_registration
written_outputs
pending_decisions
evidence_refs
retry_count
```

La evidencia conserva timestamps, hashes, comandos y referencias resolubles.

## 18. Fuentes de diseño no normativas

- **Claude Skills — anthropics/skills:** assertions objetivas, grading
  programático y reparación iterativa.
- **freeCodeCamp/freeCodeCamp:** validaciones condicionales, unicidad y rechazo
  determinista.
- **Significant-Gravitas/AutoGPT:** fixtures aislados, estado y límites de
  ejecución.

Los contratos LF y la fuente operativa prevalecen.
