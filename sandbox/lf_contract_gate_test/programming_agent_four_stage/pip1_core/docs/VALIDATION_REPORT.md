# Informe de validación — PIP-1 D-01/D-03

Fecha: 2026-10-28. Estado: EXPERIMENTAL, no aprobado operacionalmente.

## Fuentes verificadas
- PR #3220: HEAD `eb0e4f3f912538b1cd2f2c9635854cbf86aeb783`, draft/open.
- LF main `38e69fde901806977818de10db06d3912f315814` al momento de la consulta.
- `PROGRAMMING_SIMPLE_EXECUTOR_V1` reconsultado, incluyendo política DAG/same-plan, current-run receipt y no reuse PASS.
- `AGENTS.md` y autoridad de `CLAUDE.md` revisadas en inspección del Carril D.
- Se releyeron los seis artefactos locales anteriores (disponibles en `/mnt/data/pip1_carril_d`).

## Ejecución
- `PYTHONPATH=. python -m unittest discover -s tests -v`: 17/17 PASS.
- No DB, migraciones, Worker, API de modelos ni escrituras remotas.
- Rama Git local aislada: `lf/pip1-d01-d03-isolated`.
- No push, PR, etiquetas, merge ni modificación de #3220.

## PASE
**NOT_RUN**. El entorno de implementación no tiene checkout del repositorio LF ni acceso de red desde el contenedor, por lo que no existe base/HEAD local de PR para `emit_ci_execution_plan_v2.py`. No se declara PASS de PASE. Antes de publicar se deberá ubicar el código en paths autorizados, ejecutar clasificación PASE sobre candidato real y entregar el plan, diff y evidencia exact-head.

## Límites que bloquean promoción
1. El inventario real #3220 se leyó a través del conector GitHub, pero no pudo materializarse byte a byte en el contenedor local. El loader no fue ejecutado contra su archivo exacto; solo contra fixture explícita sintética estructural.
2. Los 108 checkpoint IDs no están hardcodeados: el loader los deriva de la entrada. La fixture genera IDs por conteos, sin reproducir los scopes/criterios reales.
3. El closure positive es sintético (`SYNTHETIC_CLOSURE`). No se prueba estado operacional, integridad de proveedor, ni readback desde ledger.
4. `Receipt.valid` no recomputa digest semántico. El adapter de evidencia real deberá verificarlo.
5. `NOT_APPLICABLE_JUSTIFIED` permite transición con razón/referencia, pero closure lo bloquea hasta añadir verificación independiente de esa autoridad.
6. `PG-00` se lee como prerrequisito externo y no puede cerrarse desde este motor.
7. No hay correspondencia aún entre estos estados candidatos y los estados persistidos existentes.

## Siguiente revisión
- Claude: validar la semántica exacta de `inventory_core` y ejecutar CLI con el archivo real; comprobar digest documentado y proyecciones.
- Owner: definir ubicación en repo autorizada, si existe GO al R-01, y política de evidencia/autoridad N/A.
