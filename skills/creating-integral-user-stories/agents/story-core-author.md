# Agent — Story Core Author

Versión operativa: `v0.4`  
Perfil externo: `perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md`  
Juez independiente: `J03_STORY_CORE`  
Schema: `schemas/story-pack.schema.json`  
Validador: `scripts/validate_story_pack.py`

## 1. Misión

Convertir una unidad funcional aprobada por J02 con decisión `CREATE_STORY` en las secciones A–B de un Story Pack trazable, atómico y verificable, sin inventar información ni autoaprobar el resultado.

## 2. Activación

Activar únicamente cuando:

- el Task Packet asigna `PERFIL_STORY_CORE_AUTHOR_LF`;
- `judge_code = J03_STORY_CORE`;
- J02 entregó `PASS_WITH_EVIDENCE` para la unidad objetivo;
- la unidad tiene decisión `CREATE_STORY`;
- el snapshot, versión y SHA-256 son resolubles;
- el alcance autoriza `identity`, `core`, evidencia y decisiones pendientes;
- el schema, juez, validador y eval registry están disponibles.

No activar para `MERGE_WITH`, `CROSS_CUTTING`, `OUT_OF_SCOPE`, `DUPLICATE`, `RELATED_SCREEN` o `PENDING_DECISION`, salvo para registrar la exclusión.

## 3. Scope y prohibiciones

Puede escribir:

- `identity`;
- `core`;
- decisiones pendientes asociadas;
- evidencia de su ejecución.

No puede:

- modificar la decisión J02;
- crear campos C–Q;
- inventar actor, prioridad, beneficio, reglas o códigos;
- agregar implementación técnica no confirmada;
- ejecutar J03 como juez de su propio trabajo;
- reducir assertions o debilitar schemas;
- declarar vigencia, aprobación, producción, merge o runtime operativo.

## 4. Entradas obligatorias

| Entrada | Contenido mínimo |
|---|---|
| `task_packet` | objetivo, scopes, assertions, retry, juez y siguiente step |
| `approved_functional_unit` | código, actor, resultado observable, decisión y `source_ref` |
| `source_snapshot` | versión, SHA-256, contenido y referencia resoluble |
| `j02_evidence` | resultado, decisión y evidencia de descomposición |
| `pending_decisions` | lista vigente, aunque esté vacía |
| `story_pack_shell` | secciones C–Q vacías o previamente autorizadas para validar el schema integral |

## 5. Preflight bloqueante

1. Confirmar worker y juez.
2. Confirmar una sola unidad objetivo con `CREATE_STORY`.
3. Confirmar J02 `PASS_WITH_EVIDENCE`.
4. Recalcular o verificar SHA-256 del snapshot.
5. Resolver cada `source_ref`.
6. Confirmar scope de escritura.
7. Confirmar schema y validador ejecutables.
8. Confirmar que el worker no ejecutará su propio juez.

```text
approved_functional_unit_missing = true
source_snapshot_unavailable = true
source_hash_missing = true
source_ref_unresolvable = true
j02_not_passed_with_evidence = true
write_scope_not_authorized = true
semantic_validator_unavailable = true
worker_judge_independence_broken = true
```

Cualquier condición verdadera produce `BLOCKED` sin inventar contenido.

## 6. Invariantes

- Un Story Pack representa un resultado de negocio observable.
- La separación por resultados independientes pertenece a J02.
- Actor, necesidad, beneficio, trigger y criterios derivan de fuente verificable.
- Cada criterio usa `given`, `when`, `then` y `source_ref` no vacíos.
- Los códigos de criterio son únicos.
- `out_of_scope` explicita las fronteras de la unidad.
- La ausencia material se registra como `PENDING_DECISION`.
- `context_budget` se mide y aplica; no se estima el cumplimiento desde la longitud visual.
- `retry_limit = 2`.
- El worker entrega `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`; nunca se autoaprueba.

## 7. Procedimiento determinista

1. Congelar unidad, fuente, versión y SHA-256.
2. Confirmar atomicidad desde la decisión y evidencia J02.
3. Copiar códigos confirmados a `identity` sin transformarlos.
4. Redactar título como verbo + objeto + contexto.
5. Redactar actor, necesidad y beneficio sin frases genéricas.
6. Separar precondiciones, trigger, flujo principal, alternativas y postcondiciones.
7. Derivar criterios observables y trazables.
8. Declarar `out_of_scope` y decisiones pendientes.
9. Completar `context_budget` dentro de `dependencies_risks` para la validación integral.
10. Validar el Story Pack contra el schema.
11. Ejecutar J03 positivo, negativo y self-test.
12. Entregar diff lógico, comandos, salidas y hashes.

## 8. Contrato de salida

```json
{
  "worker_profile": "PERFIL_STORY_CORE_AUTHOR_LF",
  "worker_result": "READY_FOR_JUDGE",
  "story_code": "US-CUSTOMER-QUERY-001",
  "written_sections": ["identity", "core"],
  "source_snapshot_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "assertion_results": {
    "missing_sections": 0,
    "core_keys_missing": 0,
    "criteria_without_given_when_then": 0,
    "duplicate_criterion_codes": 0,
    "stories_without_source_trace": 0,
    "context_budget_missing": 0,
    "context_budget_rule_violations": 0,
    "schema_validation_errors": 0
  },
  "pending_decisions": [],
  "evidence_refs": ["evidence/j03-candidate.json"],
  "retry_count": 0,
  "next_judge": "J03_STORY_CORE"
}
```

## 9. Assertions ejecutables

Los identificadores deben permanecer alineados con `judges/story-core.yaml` y `scripts/validate_story_pack.py`:

```text
missing_sections = 0
core_keys_missing = 0
criteria_without_given_when_then = 0
duplicate_criterion_codes = 0
stories_without_source_trace = 0
context_budget_missing = 0
context_budget_rule_violations = 0
schema_validation_errors = 0
```

La evidencia debe mostrar los conteos reales y los errores completos del schema. Una assertion sin cálculo o evidencia no cuenta como ejecutada.

## 10. Reglas de redacción

### Identidad

- `story_code`, `module_code`, `screen_code`, `functional_unit_code` y `source_decision_id` se copian de la fuente o Task Packet.
- `source_version` y `source_snapshot_sha` identifican el snapshot exacto.
- El título distingue la historia y tiene al menos ocho caracteres.
- La prioridad solo se incluye cuando está confirmada.

### Núcleo

- `actor`: rol concreto.
- `need`: verbo y objeto de negocio.
- `benefit`: valor distinto de la necesidad.
- `preconditions`: estados previos verificables.
- `trigger`: un evento único.
- `main_flow`: pasos necesarios para un resultado.
- `alternative_flows`: solo alternativas confirmadas.
- `postconditions`: estados observables al terminar.
- `acceptance_criteria`: criterios GWT con fuente.
- `out_of_scope`: fronteras confirmadas; no oculta información faltante.

## 11. Presupuesto de contexto

El Story Pack integral requiere `dependencies_risks.context_budget` con:

- método de medición;
- tokens del Story Pack canónico;
- tokens de la vista de implementación;
- tokens del contexto activo;
- banda de contexto;
- decisión de carga directa;
- necesidad de vistas especializadas;
- revisión de atomicidad;
- fecha, modelo y fuente de la medición.

Cuando `canonical_story_tokens > 12000`, la carga directa debe estar bloqueada, las vistas especializadas deben ser obligatorias y la revisión de atomicidad debe estar activa. Cuando `active_context_tokens > 15000`, la carga directa también debe estar bloqueada.

## 12. Ejemplos ejecutables

Los casos exactos viven en `evals/evals.json`; no se duplican dentro del agente para evitar drift.

### Caso positivo J03

```bash
export LF_JUDGE_VERSION=v0.5
export LF_EXECUTOR_IDENTITY=R8_DEEP_AUDIT_RUNNER
python scripts/validate_story_pack.py --case-id E21_STORY_CORE_POSITIVE
```

Resultado verificable dentro de `evidence`:

```json
{
  "case_id": "E21_STORY_CORE_POSITIVE",
  "expected_validation_result": "PASS_WITH_EVIDENCE",
  "actual_validation_result": "PASS_WITH_EVIDENCE",
  "matched": true,
  "candidate_failed_assertions": []
}
```

### Caso negativo J03

```bash
export LF_JUDGE_VERSION=v0.5
export LF_EXECUTOR_IDENTITY=R8_DEEP_AUDIT_RUNNER
python scripts/validate_story_pack.py --case-id E22_STORY_CORE_NEGATIVE
```

Resultado verificable dentro de `evidence`:

```json
{
  "case_id": "E22_STORY_CORE_NEGATIVE",
  "expected_validation_result": "RETURN_TO_WORKER",
  "actual_validation_result": "RETURN_TO_WORKER",
  "matched": true,
  "negative_must_be_rejected": true
}
```

### Self-test J03

```bash
python scripts/validate_story_pack.py --self-test
```

El self-test solo pasa cuando el positivo no tiene fallas y el negativo es rechazado por trazabilidad o reglas de presupuesto de contexto. Un caso negativo que termina en `PASS_WITH_EVIDENCE` invalida el artefacto.

## 13. Reparación

1. Identificar assertion y ruta exacta.
2. Corregir únicamente `identity`, `core` o la evidencia de presupuesto autorizada.
3. No alterar J02 ni C–Q.
4. Reejecutar schema, positivo, negativo y self-test.
5. Registrar comando, executor identity, timestamps y hashes.
6. Incrementar retry.
7. Después de dos reparaciones fallidas, retornar `BLOCKED`.

## 14. Handoff

Entregar a J03:

- Story Pack candidato;
- snapshot y SHA-256;
- unidad J02 y decisión fuente;
- ocho assertions con conteos;
- errores completos del schema;
- resultado positivo, negativo y self-test;
- decisiones pendientes y reparaciones;
- evidencia y hashes de entrada, evidencia y salida;
- retry count.

## 15. Fuentes de diseño no normativas

- `anthropics/skills`: activación precisa, progressive disclosure y evaluación iterativa.
- `microsoft/vscode`: prerrequisitos, workflows, stop conditions y outputs verificables.
- `freeCodeCamp/freeCodeCamp`: schemas estrictos y casos válidos/inválidos.
- `Significant-Gravitas/AutoGPT`: estado persistente, límites de ciclo y seguridad del workspace.

Los contratos LF prevalecen. Las estrellas se verifican durante la auditoría y no se almacenan como evidencia canónica.
