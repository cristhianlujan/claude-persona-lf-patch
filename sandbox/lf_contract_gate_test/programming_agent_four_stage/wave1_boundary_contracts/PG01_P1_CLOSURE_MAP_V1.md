# PG01_P1_CLOSURE_MAP_V1

26-oct-2026. Estado: P1 ABIERTO. Base main ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267. Evidencia local y fixtures, sin admisión operativa ni persistencia C6.

## Ocho negativos principales

Los tres reales se obtuvieron mediante SELECT en Supabase RO y se reprodujeron exactamente en Postgres desechable. Los cinco restantes son fixtures sintéticos. Los nombres de casos pertenecen a test_programming_pg01_receiver_v1.py, invocados por run_programming_pg01_receiver_base_v1.py. Cada real ejecuta exercise_historical: historical_hash_<id>, historical_rejected_<id> y historical_invalid_snapshot_<id>.

| N | Input y tipo | Código BLOCK observado | Test exacto | PG-01 |
|---|---|---|---|---|
| 1 | Real 06/10, 41f0287a-c7db-4f34-b2f7-c548fa534ece | SQL PROGRAMMING_SNAPSHOT_REQUIRED_FIELD_MISSING; receptor CONTEXT_NOT_RESOLVED | historical_rejected_41f0287a-c7db-4f34-b2f7-c548fa534ece y historical_invalid_snapshot_41f0287a-c7db-4f34-b2f7-c548fa534ece | C3/C5 |
| 2 | Real 07/10, 38a8f5c8-a6f3-45d6-b1ee-823af130e647 | SQL PROGRAMMING_SNAPSHOT_REQUIRED_FIELD_MISSING; receptor CONTEXT_NOT_RESOLVED | historical_rejected_38a8f5c8-a6f3-45d6-b1ee-823af130e647 y historical_invalid_snapshot_38a8f5c8-a6f3-45d6-b1ee-823af130e647 | C3/C5 |
| 3 | Real 09/10, e5adcfbf-e53f-420d-a94a-fad553fa6e48 | SQL PROGRAMMING_SNAPSHOT_REQUIRED_FIELD_MISSING; receptor CONTEXT_NOT_RESOLVED | historical_rejected_e5adcfbf-e53f-420d-a94a-fad553fa6e48 y historical_invalid_snapshot_e5adcfbf-e53f-420d-a94a-fad553fa6e48 | C3/C5 |
| 4 | Sintético: falta handoff esperado | EXPECTED_HANDOFF_INVALID_OR_MISSING | N4_missing_handoff; N4_no_query_without_expected_receipt | C2/C5 |
| 5 | Sintético: fuente material stale | CURRENTNESS_NOT_ADMISSIBLE | N5_stale_BLOCK; N5_canonical_engine_STALE; router_v2_stale_receiver_BLOCK | C2/C5 |
| 6 | Sintético: contexto modificado frente al hash esperado | EXACT_RECEIPT_MISMATCH | N6_modified_context_vs_original_receipt | C2/C5 |
| 7 | Sintético: scope solicitado desconocido/no READY | REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN | N7_unknown_requested_scope; N7_partial_READY_never_substitutes_blocked_S2 | C3/C5 |
| 8 | Sintético: proyección pierde material | MATERIAL_PROJECTION_LOSS_OR_MISMATCH | N8_lossy_projection_BLOCK; N8_BLOCK_receipt_hashes_retained_full_projection | C1/C5 |

Los reales 07/10 y 09/10 fallan primero por campo requerido; no se los presenta como pruebas aisladas de matriz vacía o cero READY. Esos controles adicionales son sintéticos: N2_synthetic_empty_matrix_BLOCK y N3_zero_READY_code/NO_READY_SCOPE, además de router_v2_zero_ready_receiver_BLOCK. Los históricos no se reparan ni se reescriben. No se guarda el JSON crudo del contexto en el repo.

Hashes exactos del replay:

- `41f0287a-c7db-4f34-b2f7-c548fa534ece`: `9f416ce7bea29db1e80257829972251f40135ecbdd217e952115dcb18654246c`.
- `38a8f5c8-a6f3-45d6-b1ee-823af130e647`: `5ed3ffd513e4caadc65a9cbfb5991b6f8caeac8f714bec2c95fab23849a16e10`.
- `e5adcfbf-e53f-420d-a94a-fad553fa6e48`: `2bb192f4bf9b1ed2ca7133ffe50665319671945f98add6457889256974e9ebb8`.

## Positivo sintético y recibo

Caso emitter_positive_boundary con currentness y contexto sintéticos, persistidos solamente en Postgres local desechable. schema_version es el discriminador; debajo están los siete campos de negocio. No es C6 persistido ni el positivo acordado C1/PR2.

```json
{
  "schema_version": "PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1",
  "context_id": "c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c",
  "context_sha256": "730f1ffcb8c049c8e7e3dfa8a5a94326baed867840a32711269bd86e5d72cfd2",
  "snapshot_schema_digest_sha256": "d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8",
  "receiver_schema_digest_sha256": "d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8",
  "material_projection_sha256": "394b5a0ae95ebb12fbee32a006a48f9ee4984092815f16da62b5105a814278eb",
  "validated_material_paths": [
    "extensions.programming_context_snapshot.analysis_stop_rule",
    "extensions.programming_context_snapshot.applicable_invariants",
    "extensions.programming_context_snapshot.applicable_rules",
    "extensions.programming_context_snapshot.authority_bindings",
    "extensions.programming_context_snapshot.authority_fingerprint_sha256",
    "extensions.programming_context_snapshot.authority_state",
    "extensions.programming_context_snapshot.currentness_refs",
    "extensions.programming_context_snapshot.decision_context",
    "extensions.programming_context_snapshot.implementability_schema",
    "extensions.programming_context_snapshot.implementation_state",
    "extensions.programming_context_snapshot.material_front_coverage",
    "extensions.programming_context_snapshot.objective",
    "extensions.programming_context_snapshot.package_readiness",
    "extensions.programming_context_snapshot.preserve",
    "extensions.programming_context_snapshot.requirements",
    "extensions.programming_context_snapshot.scope_front_matrix",
    "extensions.programming_context_snapshot.scope_readiness",
    "extensions.programming_context_snapshot.snapshot_schema_digest_sha256",
    "extensions.programming_context_snapshot.source_refs",
    "extensions.programming_context_snapshot.source_snapshot_sha256",
    "extensions.programming_context_snapshot.target",
    "extensions.programming_context_snapshot.target_granularity",
    "extensions.programming_context_snapshot.unresolved_material_items"
  ],
  "verdict": "ACCEPT"
}
```

## Determinismo y niveles de prueba

emitter_repeat_entire_result_identical repite consume con el mismo handoff/contexto/scope/currentness y compara el resultado completo, incluido recibo. Ambos resultados tienen SHA256 ab8a8dda84c228f0067c89c9c79a8e9d892eb6b380e0ff4a01f325ca7a12bdf3. No es la comparación entre dos fixtures distintas ni entre dos corridas que generen UUID diferentes. preplanning_full_repeat_deterministic cubre además la proyección previa a planificación.

Resultados locales sobre el código 8422b55634f8eb345e33fc49e23117d916bd2b90: 76 unittest PG-01 y 85 unittest Router; 148 assertions SQL coincidentes (111 fundamento/emisor/preplanning, 28 Router V2, 9 históricos). Fuente detallada: pg01_router_compatibility_local_20261026.json. No son conteos de CI ni prueba de integración viva.

## Cierre pendiente

| Checkpoint | Evidencia actual | Falta |
|---|---|---|
| C1 contrato/paridad | Schema y digest exactos locales, prueba sin pérdida | Positivo acordado y mapa A9/C1-PR2 con admisión independiente |
| C2 resolución/currentness | Resolver/guard y stale locales | Proveedor real admitido y expectativas provenientes del upstream autorizado |
| C3 snapshot/READY | SQL+Python y ocho negativos | Positivo acordado, envelope ANALYSIS_IMPLEMENTATION_PACKAGE_V1 y procedencia del scope READY admitido |
| C4 marco técnico | Validadores/preplanning y exact reader locales | Manifiesto/control reales, presupuesto aprobado y autoridad/proveedor admitidos |
| C5 negativos | Ocho casos trazables; tres replay reales y cinco fixtures | Revisión independiente de la evidencia; no equivale a positivo operacional |
| C6 emisor/persistencia | Emisor determinista local de siete campos | D7, persistencia autorizada y readback independiente |
| C7 suficiencia | Validación local y positivos sintéticos | Mapa compartido acordado, readback semántico y positivo C1/PR2 |
| P1 / I0 | Abiertos | Positivo real acordado C1/PR2, D7 y cierre de las brechas Router→A9→PG-01 |

El contrato exige ACCEPT/BLOCK. ACCEPT sintético significa frontera estructural aceptada; execution_allowed=false. El Router actual solo declara PROGRAMACION_PRECHECK_DEFINICION y la continuación condicional; no emite digest, handoff, paquete admitido ni recibo persistido. La frontera permite un snapshot válido sin autenticar separadamente el paquete A9: brecha explícita, sin inventar código BLOCK. El diseño D7 está en PG01_D7_RECEIPT_PERSISTENCE_PROPOSAL_V1.md y requiere revisión antes de código.
