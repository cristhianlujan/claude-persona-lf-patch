# Mapa operativo de fuentes Supabase

Versión operativa: `v0.3`. Juez asociado: `J01_SOURCE_INTEGRITY y J12/J13 para transporte y cierre`.

## 1. Propósito

Definir qué objetos deben leerse, cómo verificar su existencia y cómo preservar la autoridad canónica de los artefactos.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `project_id` | mhwmirqcgxxukpctffuv. |
| `operation_code` | BUILD_INTEGRAL_STORY_CREATOR_LF. |
| `execution_id` | Identificador vigente de cada ejecución. |
| `artifact_store` | private.lf_skill_artifacts. |
| `event_store` | public.lf_eventos. |
| `destination_registry` | public.v_lf_artifact_destination_registry. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Consultar information_schema.columns y pg_constraint antes de depender de un objeto.
2. Leer contratos, steps, perfiles, jueces y ejecución vigente.
3. Resolver destino por operation_code y artifact_type.
4. Leer artefactos actuales desde private.lf_skill_artifacts.
5. Verificar UTF-8, LF, newline final y SHA-256.
6. Transportar solo a feature branch autorizada.
7. Releer GitHub y comparar hash por cada ruta.
8. Registrar evidencia en lf_eventos.
9. Versionar artefactos sin sobrescribir historial.
10. Cerrar la ejecución solo con readback completo y sin mismatches.

## 5. Reglas e invariantes

- Supabase es fuente canónica de contenido; GitHub es transporte y espejo.
- Las rutas del registro vigente prevalecen sobre handoffs históricos.
- Prohibido inventar tablas o columnas.
- Una tabla ausente produce hallazgo; no se sustituye silenciosamente.
- Nunca se actualiza main ni se hace merge sin autorización nueva.
- Cada versión conserva content_sha256, source_refs, dependencies y evidencia.
- Los eventos usan entidad_codigo de la ejecución correspondiente.

## 6. Contrato de salida

Salida principal: `Artefactos versionados, eventos de evidencia y readback verificable.`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
canonical_sha_mismatches = 0
github_readback_mismatches = 0
current_paths_unique = true
unexpected_written_files = 0
direct_main_write_detected = false
```

## 8. Condiciones de bloqueo

```text
canonical_store_unavailable = true
destination_registry_conflict = true
target_branch_conflict = true
write_scope_not_authorized = true
```

## 9. Ejemplo mínimo completo

```text
private.lf_skill_artifacts
  -> content UTF-8/LF/newline
  -> SHA-256 canónico
  -> feature branch
  -> Git blob readback
  -> comparación byte a byte
  -> public.lf_eventos
```

## 10. Reparación

Cuando una assertion falle, reparar exclusivamente el objeto asociado; no reducir el umbral, borrar la assertion ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con la evidencia acumulada.

## 11. Handoff

Entregar al juez: versión de fuente, SHA-256, objetos procesados, conteos, assertions, fallas, decisiones pendientes, reparaciones aplicadas y evidence_refs resolubles.

## 12. Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.

Estas fuentes aportan patrones de ejecutabilidad, validación y pruebas. Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
