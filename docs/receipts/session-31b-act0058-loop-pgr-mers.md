# S31B — ACT-0058 LOOP_CONTROLADO con PGR/MERS

## Alcance

Registrar en GitHub el ajuste operativo preparado para ACT-0058 después de la corrida que falló por captura web.

## Contexto

- Skill: `ACT-0058` / `SKILL_ORQUESTADOR_PIPELINE_LF`
- Operation code vigente: `ORQUESTACION_PIPELINE_LF`
- Evento Supabase de trazabilidad: `lf_eventos.id = 496`
- Estado de aplicación: `PREPARADO_NO_PRODUCTIVO`
- Modo objetivo: `LOOP_CONTROLADO`

## Ajuste operativo

La regla madre del loop queda definida así:

```text
Falla por URL ≠ falla total del ciclo
```

## Guardrails aplicados

| Guardrail | Uso operativo |
|---|---|
| PGR | Validación de gobierno, fuente vigente, readback y cierre trazable |
| MERS | Manejo de error por URL, retry, seguimiento y continuidad del lote |

## Reglas de parada del ciclo

| Caso | Acción |
|---|---|
| Supabase MCP no disponible | Detener ciclo y reportar `FAILED_TOOL_UNAVAILABLE` sin declarar ejecución |
| Router no verificable | Detener ciclo |
| Fuente operativa no verificable | Detener ciclo |
| Error SQL/schema | Detener ciclo |
| Falla de captura web en una URL | Registrar URL como `FALLIDO` y continuar |
| URL sin evidencia suficiente | Registrar URL como `FALLIDO` y continuar |
| KB sin evidencia literal | Bloquear solo esa URL; no escribir KB |

## Comportamiento esperado

```text
MCP OK
→ Router OK
→ Fuente operativa OK
→ ACT-0058
→ tomar URLs pendientes
→ procesar URL 1
   si falla captura: registrar FALLIDO y seguir
→ procesar URL 2
→ procesar URL N
→ cierre resumen del lote
```

## Impacto

- No cambia schema.
- No cambia triggers.
- No cambia runtime productivo.
- No fuerza `impacto_automatico`.
- Sirve como receipt operativo para PR/merge y trazabilidad de S31B.

## Referencias

- PR previo relacionado: `#52`
- Evento Supabase relacionado: `lf_eventos.id = 496`
