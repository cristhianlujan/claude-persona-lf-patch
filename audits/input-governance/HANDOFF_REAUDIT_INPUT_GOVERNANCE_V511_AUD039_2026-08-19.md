# Handoff — Reauditoría independiente Input Governance v5.11 / AUD-039

Fecha: 2026-08-19
Repositorio: `cristhianlujan/claude-persona-lf-patch`
PR: `#179`
Rama: `audit/input-governance-v55-sync-20260818`
Supabase project: `mhwmirqcgxxukpctffuv`
Agente: `INPUT_GOVERNANCE_AGENT`
`version_id`: `19`
Contrato: `INPUT_READINESS_CONTRACT` revision `5.11`

> El auditor debe resolver y fijar el HEAD exacto del PR #179 al iniciar la auditoría y no cambiarlo durante la ejecución. El SHA objetivo final también queda registrado en el cuerpo del PR después de publicar este handoff.

## Restricciones de auditoría

- Auditoría independiente: no corregir código ni datos durante la auditoría.
- No mergear PR #179.
- No promover el agente, no Golden/Human promotion y no activar EKB.
- No autorizar producción.
- No reabrir Challenge6 ni exigir usuarios/credenciales PostgreSQL retirados.
- No usar ZIP.
- Terminar únicamente con `PASS` o findings reproducibles.

## Estado candidato a verificar directamente

Pantallas activas del módulo `B2B_AUTENTICACION`: 5.

| pantalla | código | run actual esperado |
|---:|---|---:|
| 51 | B2B-AUTH-001 | 140 |
| 52 | B2B-AUTH-002 | 141 |
| 53 | B2B-AUTH-003 | 142 |
| 54 | B2B-AUTH-004 | 146 |
| 56 | B2B-AUTH-006 | 144 |

`B2B-AUTH-005` / pantalla 55 permanece inactiva, `RETIRED_LEGACY_TRACE_ONLY`, fuera del universo activo.

Todos los runs anteriores deben ser no-current según lineage/source freshness.

## Evidencia interna previa — no sustituye auditoría independiente

- 47 familias por pantalla; 235 assessments totales.
- 313 assertions totales.
- 313/313 reejecutadas `PASS` contra fuente viva.
- 313/313 resultados persistidos `PASS`.
- 313/313 `source_observed_sha256` coinciden con la reejecución.
- Module Health V3 después del refresh visual de AUTH-004:
  - `mechanics_pass=true`
  - `story_health_pass=true`
  - `health_pass=true`
  - `promotion_authorized=false`
  - `mechanics_healthy_screen_count=5`
  - `story_healthy_screen_count=5`
  - health SHA `ecb5f919b4caad7671388dac4c60de1efe91c33e0899603e8483894d01496b6e`

Health PASS significa salud mecánica + cierre del stage Story; no implica Implementation/QA/Production readiness ni promoción.

## Hallazgo nuevo AUD-039

EKB:
- `AUD-039` — Recuración semántica podía producir una assertion incompatible con su propio contrato de relevancia.
- `PRV-AUD-039` — el builder debe validar `source_ref/path` contra relevancia semántica de la familia; no se relaja el guard.

Caso reproducible previo: `PROFILES` de pantalla 56 se construía con una fuente/ruta incompatible y luego con `expected` histórico obsoleto. Los intentos de successor fallaron transaccionalmente y no dejaron runs parciales.

Remediación registrada en Supabase y sincronizada como migraciones exactas:

1. `20260819232840_input_governance_r5_11_aud039_profiles_relevance_fix_20260819.sql`
2. `20260819233124_input_governance_r5_11_aud039_profiles_semantic_fix_20260819.sql`
3. `20260819233346_input_governance_r5_11_aud039_profiles_expected_recuration_20260819.sql`
4. `20260819233400_input_governance_r5_11_semantic_assertion_recuration_successors_20260819.sql`
5. `20260819234045_input_governance_r5_11_auth004_visual_source_successor_20260819.sql`

La quinta migración responde a una actualización canónica posterior y legítima del artefacto TABLET de B2B-AUTH-004. El latch hizo run143 no-current automáticamente; se registró como nueva ocurrencia de `AUD-019` (frecuencia incrementada a 4) y se creó run146, sin reescribir historia.

## Controles adversariales internos ya ejecutados

Todos fail-closed y sin residuos permanentes:

1. `severity=UNRESOLVED` rechazado.
2. Story abierto con severidad no P0 rechazado.
3. QA READY sin Implementation READY rechazado.
4. Implementation READY con coverage/well-defined incompletos rechazado.
5. `NOT_APPLICABLE` sustentado solo por `CAPABILITY_ABSENCE` rechazado.
6. source ref screen-scoped sin `pantalla_id` rechazado.
7. control positivo con assessment válido aceptado.
8. stale Context Manifest para run143 rechazado con `INPUT_CONTEXT_MANIFEST_REQUIRES_CURRENT_RUN:143`.
9. handle JIT/retrieval fabricado para run146 rechazado con `INPUT_RETRIEVAL_HANDLE_NOT_AUTHORIZED_FOR_RUN`.
10. `PROFILES` con `SCREEN_RULE_SET + observed/rules` es no relevante.
11. `PROFILES` con `SCREEN_CANONICAL_GRAPH + observed/canonical_contract/profiles` es relevante.
12. `CONTRACT` no puede servir como autoridad independiente para `SOURCE_AUTHORITY_PROVENANCE`.

## Reauditoría requerida

Verificar desde cero, sin confiar en este handoff:

1. Fijar HEAD exacto del PR #179 y comprobar que no cambia durante la auditoría.
2. Consultar EKB y contrato 5.11 directamente en Supabase.
3. Confirmar universo activo exacto: pantallas 51,52,53,54,56; pantalla55 excluida.
4. Confirmar currentness exacto de runs 140,141,142,146,144 y no-current de sus predecesores.
5. Reejecutar las 313 assertions y comprobar `result` + `source_observed_sha256`.
6. Recalcular `fn_input_governance_module_health(19,'B2B_AUTENTICACION')`.
7. Repetir negativos de severidad, stage hierarchy, coverage monotonicity, N/A authority, source scoping, stale Context Manifest y JIT fabricado.
8. Probar mismatch de receipt Curator/Validator, contract revision obsoleta y assertion result/hash adulterado si el harness de auditoría permite rollback seguro.
9. Verificar que Curator y Validator conservan execution IDs distintos y binding explícito Validator→Curator.
10. Verificar semántica stage-aware: gaps P1/P2 posteriores no deben inflarse a Story P0.
11. Verificar Design/Security contextual depth y que falsos `COMPLETE/READY` continúan fail-closed.
12. Comparar byte/contenido de las cinco migraciones listadas con `supabase_migrations.schema_migrations.statements`; no reconstruir SQL histórico manualmente.
13. Distinguir este delta del gate histórico separado `GITHUB_SUPABASE_HISTORY_SYNC_INCOMPLETE` y del clean bootstrap aún no probado.

## Criterio de salida

- `PASS`: solo si todos los controles anteriores son reproducibles sobre el HEAD fijado y la fuente Supabase vigente.
- En caso contrario: findings reproducibles con prioridad, evidencia, SQL/comando de reproducción y alcance.

No convertir un PASS de Story Health en autorización de promoción o producción.