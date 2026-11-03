# A9 Snapshot Assembler V1 — contrato de integración

**Alcance:** Python stdlib, sin red, BD ni ejecución de modelos. Implementación candidata para revisión independiente; no implica operación gobernada, aprobación, registro ni entrada a PG-01.

## Entrada y autoridad

- `candidate`: `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`, salida **no calificada** del modelo. Se usan el objetivo, granularidad y los identificadores de scopes para correlación. Los indicadores `READY_CANDIDATE`, la clasificación de autoridad, las reglas y los frentes del modelo **no** son autoridad.
- `artifacts`: A3 `TARGETED_EVIDENCE_SET_V1`, A4 `SHARED_CHANGE_IMPACT_MAP_V1`, A5 `ANALYSIS_DECISION_CONTEXT_V1`, A6 `IMPLEMENTABILITY_SCHEMA_V1`, A7 `MATERIAL_FRONT_COVERAGE_V1`, A8 `ANALYSIS_STOP_RULE_V1`. Los suministra el ejecutor tras leer los artefactos oficiales. Se conservan A5, A6, A7, A8 íntegros en el snapshot.
- `authority_inputs`: `target_identity`, `product_rules`, `currentness_receipts`, `applicable_invariants`, `preserve`, `source_refs`, más pruebas explícitas de independencia para `PARTIAL_READY`. Los obtiene y certifica quien invoca el ensamblador, no el modelo.
- `entry_contract_digest`: huella de bytes del contrato vigente, suministrada por el llamador y comprobada por igualdad exacta.

## Mapa de procedencia de los 23 campos

| Campo | Fuente |
|---|---|
| `objective`, `target_granularity` | candidato de A1/A2, sin autoridad |
| `target` | A3 `target_resolution` + `authority_inputs.target_identity`, con huella de fuente |
| `authority_state`, `implementation_state` | A3 |
| `requirements`, `authority_bindings`, `implementability_schema` | A6, con bindings canónicos cotejados contra A3 |
| `applicable_rules`, `applicable_invariants`, `preserve` | `authority_inputs` canónicos, nunca inferidos del candidato |
| `material_front_coverage` | A7 completo |
| `decision_context` | A5 completo |
| `analysis_stop_rule` | A8 completo |
| `scope_readiness` | scopes de A6; decisiones A5; frentes A7; unresolved A3–A8/candidato |
| `scope_front_matrix` | función existente `assemble_scope_front_matrix_v1` |
| `package_readiness` | estados derivados, A8, completitud A7 y prueba de independencia |
| `unresolved_material_items` | unión con etiqueta de procedencia A3–A8 + preguntas del candidato |
| `source_refs` | refs de A3–A8 + refs oficiales; unión ordenada |
| `currentness_refs` | recibos oficiales + refs A3–A8; unión ordenada |
| `snapshot_schema_digest_sha256` | digest del contrato de entrada provisto por el llamador |
| `authority_fingerprint_sha256` | propuesta `A9_FINGERPRINT_RULE_V1` |
| `source_snapshot_sha256` | propuesta `A9_FINGERPRINT_RULE_V1` |

## Derivación

Cada scope declara en A6 su clase, dependencias, refs de frentes y autoridades. Las decisiones A5 no estables, los bloqueos de A7 y los ítems materiales abiertos impiden `READY`. Se comprueba la clausura de dependencias. Un `READY_CANDIDATE` no altera el resultado. La matriz es una proyección bidireccional A7↔scope por la función existente; el validador existente cierra el proceso. `STOP` por sí solo no equivale a `READY`.

El estado global es `READY` solo si todos los scopes están READY y A8 permite STOP estable, con A7 completo. `PARTIAL_READY` exige scopes READY y no READY, junto con evidencia **explícita** del llamador de límite independiente y ausencia de bloqueo transversal. Si no se prueban ambas, queda `BLOCKED`; nunca se presume independencia.

### Corrección de revisión (Claude, 26-oct)

- Un ítem sin resolver **sin `scope_id`** (por ejemplo, una pregunta de A8 que puede cambiar la decisión o una señal material de A7 sin mapear) ahora bloquea **todos** los scopes. Antes dejaba el scope en READY.
- El paquete no es READY si A8 trae preguntas que cambian la decisión o evidencia adicional capaz de cambiarla, aunque declare STOP.
- Los errores del validador existente se devuelven como `A9AssemblyError` con el mismo código.

## Huellas — propuesta, NO aprobada

`A9_FINGERPRINT_RULE_V1`: SHA256 de JSON UTF-8 canónico Python (`sort_keys=True`, `separators=(',', ':')`, `ensure_ascii=False`, `allow_nan=False`). La huella de autoridad cubre la lista ordenada `(binding_id, canonical_ref, currentness_ref)` más identificadores, estado y referencias canónicas de reglas e invariantes. La huella fuente cubre `repo_full_name`, `base_head_sha` y `source_refs` ordenadas. **No es equivalente a PostgreSQL `jsonb::text` y no sirve para recalcular `context_sha256`.** Ambas reglas requieren aprobación de Cristhian antes de persistir datos reales.

## Envoltorio as-of

`build_asof_record_input(...)` valida estructura `LF_DECISION_CONTEXT_ASOF_INPUT_V1`, IDs, autoridad y gobernanza sin payload embebido, tres capacidades obligatorias con SHA256, y timestamps con zona. Deja el snapshot en `extensions.programming_context_snapshot`. No calcula `context_sha256`: lo hará PostgreSQL durante `public.fn_lf_decision_context_asof_record_v1` por la operación gobernada.

## Excluido de este PR

Lectura real de fuentes, confirmación de vigencia y autoridad, escritura a Supabase, invocación de `record_v1`, revisión independiente, contrato V2, desbloqueo de PG-01, cambios Router y ejecución de negocio.

## Preguntas para Cristhian

1. ¿Se aprueba `A9_FINGERPRINT_RULE_V1` o hay canon previo?
2. ¿Qué esquema y fuente oficial emiten `scope_definitions` de A6, `preserve`, `applicable_invariants` y el límite de ejecución independiente? Este ensamblador exige esos datos explícitos para no inventarlos.
3. ¿Cuáles son las claves concretas de vacíos materiales de A3 y A6? Se usan `unresolved_material_gaps` y `unresolved_material_items` **solo si están presentes**, conservando la etiqueta de origen. Confirmar nombres antes de autorizar runtime.
4. ¿Las reglas e invariantes canónicas usan exactamente `code`, `status`, `canonical_ref`? Son supuestos de interfaz requeridos para la propuesta de huellas.
5. ¿Quién acredita que los `source_refs` de A3–A8 son completos y vigentes? El ensamblador no puede comprobarlo sin el resolver gobernado.

**Estado:** entregable para revisión de Claude, sin PR ni Train ni persistencia.
