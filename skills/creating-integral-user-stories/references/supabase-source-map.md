# Mapa operativo de fuentes Supabase

Versión operativa: `v0.5`. Jueces asociados: `J01_SOURCE_INTEGRITY`, `J12_GITHUB_INTEGRITY` y `J13_INTEGRATION_CLOSE`.

## 1. Propósito

Definir qué objetos se leen, cómo verificar su existencia y cómo preservar la autoridad canónica durante la reauditoría profunda A01–A62.

## 2. Contrato de entrada

| Entrada | Valor vigente |
|---|---|
| `project_id` | `mhwmirqcgxxukpctffuv` |
| `operation_code` | `BUILD_INTEGRAL_STORY_CREATOR_LF` |
| `execution_id` | `EXEC-BISC-005-DEEP-AUDIT` |
| `artifact_store` | `private.lf_skill_artifacts` |
| `event_store` | `public.lf_eventos` |
| `destination_registry` | `public.v_lf_artifact_destination_registry` |
| `repository` | `cristhianlujan/claude-persona-lf-patch` |
| `target_branch` | `fix/deep-audit-a01-a62` |
| `draft_pr` | `57` |

## 3. Preflight

1. Consultar `information_schema.columns`, `pg_constraint` y `to_regclass` antes de depender de un objeto.
2. Leer el último evento y detectar concurrencia.
3. Confirmar inventario actual, rutas únicas y hashes internos.
4. Confirmar feature branch, PR borrador y alcance de escritura.
5. Detener con `BLOCKED` ante objeto ausente, conflicto de destino, rama distinta o readback incompleto.

## 4. Procedimiento obligatorio

1. Leer artefactos `is_current=true` desde `private.lf_skill_artifacts`.
2. Verificar UTF-8, LF, newline final y SHA-256 sobre contenido real.
3. Auditar un artefacto por vez con ejemplo positivo, negativo y bloqueo aplicable.
4. Escribir únicamente a `fix/deep-audit-a01-a62`.
5. Releer GitHub y comparar contenido/hash por ruta.
6. Crear nueva versión Supabase sin sobrescribir historial.
7. Releer versión actual, SHA, evidencia y unicidad.
8. Registrar un evento por checkpoint y un cierre solo al final.

## 5. Reglas e invariantes

- Supabase conserva historial y estado canónico; GitHub contiene la propuesta auditada.
- Los 62 artefactos permanecen `NOT_VALIDATED` hasta su sincronización exacta y checkpoint individual.
- Prohibido inventar tablas, columnas, eventos, hashes o conteos.
- Prohibido actualizar `main`, hacer merge, release, tag o habilitar runtime.
- Cada checkpoint conserva contenido SHA-256, Git blob, notas, corridas y referencias.
- Una diferencia produce `RETURN_TO_WORKER` o `BLOCKED`; nunca una reconciliación silenciosa.

## 6. Contrato de salida

```text
artifact_code, relative_path, version, content_sha256, git_blob,
claude_score, github_score, technical_score, final_score,
positive_results, negative_results, blocked_results,
source_refs, evidence_refs, event_id
```

## 7. Assertions de paso

```text
canonical_store_exists = true
event_store_exists = true
destination_registry_exists = true
current_artifact_count = 62
current_distinct_paths = 62
canonical_sha_mismatches = 0
current_duplicate_paths = 0
github_readback_mismatches = 0
unexpected_written_files = 0
direct_main_write_detected = false
```

## 8. Condiciones de bloqueo

```text
canonical_store_unavailable = true
destination_registry_conflict = true
target_branch_conflict = true
write_scope_not_authorized = true
concurrent_event_requires_reconciliation = true
github_readback_incomplete = true
```

## 9. Readback verificado de arranque

Verificación del `2026-07-30`:

```text
artifact_store = private.lf_skill_artifacts
event_store = public.lf_eventos
destination_registry = public.v_lf_artifact_destination_registry
current_artifacts = 62
distinct_paths = 62
sha_mismatches = 0
latest_event_id = 856
```

Este bloque es evidencia de arranque; debe volver a ejecutarse antes de cada escritura posterior.

## 10. Reparación

Corregir únicamente el objeto, ruta o hash discrepante. No reducir umbrales, borrar evidencia, reutilizar un PASS histórico ni alterar el inventario para cerrar. Tras `retry_limit = 2`, devolver `BLOCKED`.

## 11. Handoff

Entregar consultas ejecutadas, resultados, versión y SHA anterior/nueva, Git blob, evento, paths tocados, fallas abiertas y restricciones preservadas.

## 12. Fuentes de diseño no normativas

- **anthropics/skills:** evidencia progresiva, evals objetivas y reparación iterativa.
- **microsoft/vscode:** workflows, outputs y stop conditions.
- **freeCodeCamp/freeCodeCamp:** constraints y rechazo determinista.
- **Significant-Gravitas/AutoGPT:** persistencia y límites operativos.

Los contratos LF y la fuente operativa prevalecen.
