# IG-EVO — Familias dinámicas, remediación y evidencia íntegra (CANDIDATO)

**Objetivo:** corregir el límite sintáctico `RATE_LIMIT/SESSION` sin abrir autoridad indebida y evitar que un Perfil emita conclusiones a partir de resúmenes que no contienen la evidencia original.

## Autoridad existente, sin nuevos caminos

Entrada: `ACT-0001 → Perfil → Input Governance (Curator → Validator) → Perfil`. Router no ejecuta IG. Reutilizar `programacion.fn_input_validator_semantic_scope_v1(run_id)`, que resuelve familias desde el `INPUT_FAMILY_POLICY_REGISTRY` del RUN, con assessment presente y estrategia definida. Las reglas/políticas solo se consultan desde sus fuentes gobernadas.

## Comportamiento por familia, extensible

| Estado de fuente | Comportamiento de investigación | Autoridad semántica y de escritura |
|---|---|---|
| Registrada + adapter + pin Curator vigente | Paquete candidato y evidencia por fuente | NO: evaluación y Validator independientes pendientes |
| Registrada + sin adapter | `REMEDIATION_REQUIRED` + `unresolved_families[].family_code/reason/required_action` + assessment original | NO; no tratar como N/A ni omitir |
| Registrada + fuentes sin snapshot firmado | `SOURCE_SNAPSHOT_PIN_REQUIRED` + referencias pendientes | NO; obtener snapshot fresco desde Curator |
| Fuente demasiado grande para transporte | `REMEDIATION_REQUIRED` + recuperación por lotes del mismo RUN | NO; sin truncar silenciosamente |
| Familia fuera de registry/autoridad o RUN inválido | Bloqueo de autorización existente | NO; no permitir investigación con privilegios inexistentes |

**No confundir:** permitir reparar/estudiar ≠ autorizar aplicar, cerrar RUN, activar producción o acreditar PASS semántico.

## Contrato de información íntegra para el Perfil

**Índice / resumen:** `context_manifest`, `ig_evo_graph_index`, familias afectadas, hashes y `retrieval_handles`. Sirve para localizar, no sustituye lectura.

**Evidencia por familia:** `family_evidence[]` retiene referencias, explicación, bloqueos, obligaciones negativas, pruebas requeridas, cobertura, Curator/Validator originales y hashes dentro del mismo RUN. `sources[]` agrega detalle de las políticas para adapters ya implementados. `detail_manifest[]` identifica fuentes originales a recuperar mediante el contrato `REFERENCE_PLUS_JIT`.

**Obligatorio antes de un informe conclusivo del Perfil:** leer por la ruta autorizada los detalles materiales (o marcar explícitamente los que no se pudieron leer), comparar sus hashes y registrar el resultado de lectura. Un hash por sí solo, cantidad de aristas, o `PASS / VALIDATED` de integridad **no prueba comprensión semántica**.

Readback requerido por cada referencia material:

```json
{
  "run_id": "RUN_REAL",
  "family_code": "FAMILIA_REGISTRADA",
  "source_ref": "REFERENCIA_CANONICA",
  "expected_sha256": "HASH_DE_LA_FUENTE",
  "observed_sha256": "HASH_DEL_READBACK",
  "detail_read_status": "VERIFIED | MISSING | STALE | NOT_TESTED",
  "material_obligation_ids": [],
  "negative_test_refs": [],
  "raw_detail_ref": "HANDLE_GOBERNADO",
  "semantic_verdict": "NOT_TESTED",
  "semantic_pass_authorized": false
}
```

**Prohibido:** inventar recibos, transportar secretos, adjuntar datos personales sin necesidad, sustituir RAW por sinopsis, crear un Router paralelo, marcar una familia como N/A solo por no tener adapter, o adjudicar independencia sin recibo.

**Estado implementado por la migración candidata:** selección de familias dinámica para el paquete, remediación tipada, `family_evidence` y `detail_manifest` bajo el wrapper `service_role` con ticket. No modifica por sí solo el perfil emisor de reportes ni acredita lectura JIT. Ese es un control de continuación requerido para un lote posterior, con pruebas de recepción.

## Pruebas de aceptación del lote
- Validar que `SECURITY` y toda familia futura **registrada** sin adapter no produzcan la excepción `UNSUPPORTED_FAMILY_PILOT`; entregar `REMEDIATION_REQUIRED`, detalle y no-PASS.
- Fuentes faltantes, pins obsoletos y volumen excesivo no producen `READY_FOR_MODEL_CANDIDATE`.
- Escenarios positivos, negativos y adversariales por obligación, no solo por arista.
- `anon`, `authenticated`, `PUBLIC` y `service_role` siguen sin EXECUTE directo del core; usar wrapper de ticket existente.
- No afirmar que el informe final del perfil está completo hasta verificar recuperación JIT por referencia.

EKB: `GOV-010`, `GOV-032`, `SEC-011`, `IG-M46-TRUE-CROSS-FAMILY-RECOVERY-SESSION-001`. Fuente operativa: **INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4** (en particular secciones 5, 7, 8, 9, 10 y 12).
