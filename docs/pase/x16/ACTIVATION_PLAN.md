# F09-X16 — plan deliberado de activación gradual

Este plan no activa checks ni cambia `protect-main`. La activación, si se autoriza después de que X16 salga de BACKLOG, es por control y orden fijo. Se preserva **NEW_ACTIVATION_PER_CONTROL_ONLY**: un cambio de required check por vez; no activar en bloque las 25 capacidades ni agrupar estos tres controles.

## Precondiciones comunes

- X16 sigue `BACKLOG` hasta que Cristhian active; shadow de los cinco tipos terminado y sin falso bloqueo; los siete canarios con evidencia PASS; post-PASE verifica el recibo `LF_MIGRATION_TRAIN_RECEIPT_V1`.
- La paridad lee solo el changeset; la deuda histórica 66/17 queda fuera del veredicto del PR.
- Aviso entre equipos enviado antes del cambio de cada check. Los borradores están al final; esta entrega no los envía.
- #2676 (parche fail-closed del owner del Train) integrado por el camino autorizado y validado por su owner. Este plan no lo aplica ni edita workflows.
- El ruleset final se obtiene por GET/readback antes y después de cada modificación. No usar una actualización masiva de checks.

## Precondición F07-X01

El admin compara en una misma ventana los contexts que el Train revisa antes del apply y el set requerido final del ruleset:

1. Leer `protect-main` con `GET /repos/cristhianlujan/claude-persona-lf-patch/rulesets`; localizar por nombre y confirmar id `20571741`.
2. Leer `GET /repos/cristhianlujan/claude-persona-lf-patch/rulesets/20571741`. Extraer y ordenar `rules[].parameters.required_status_checks[].context` (el readback observado hoy es solo `lf-merge-train/verified`).
3. En el SHA de una rama de prueba, inspeccionar `Verify exact-head PASE checks before apply in REAL mode` en `.github/workflows/lf-migration-merge-train.yml`. Extraer el set de contextos en el filtro del API de `check-runs` (`lf-independent-change-admission`, `ig-runtime-candidate-judge`) y revisar cómo trata `success`, `skipped`, `neutral`, `pending`, además de la exigencia `present >= 2`.
4. Antes de cualquier check requerido, exigir que la versión de Train propiedad del owner valide fail-closed la presencia/conclusión exacta de los contextos del set final sobre el head que va a aplicar. Ordenar ambos sets; deben ser iguales, sin faltantes, extras, alias de `name`/`context` ni estados `skipped`/`neutral`. El Train actual no cumple esto: sus dos nombres no son los tres contextos de PASE y permite `skipped`/`neutral`. Resultado de hoy: **NO LISTO**, bloqueado hasta readback y validación de la solución de F07-X01/#2676 por Cristhian. No tocar el workflow en esta unidad.
5. Guardar salida GET, SHA revisado, versión del Train, fecha/actor de revisión y diff vacío del ruleset para el expediente; repetir después de cada activación.

Contexts propuestos para el estado final: `lf-merge-train/verified` (existente), `PASE`, `pase-merge-gate`, `PASE / MIGRATION_SOURCE_PARITY`. Confirmar los tres nombres contra check-run API antes de editar; no inferirlos de un label de UI.

## Secuencia de control

| Orden / control | Precondición específica | Cambio exacto que hace el admin en `protect-main` | Reversión exacta y objetivo | Señal de rollback | Observación antes del siguiente |
|---|---|---|---|---|---|
| 1. `PASE` | Precondiciones comunes; resultado shadow sin falsos bloqueos; 7/7 canarios; Train/F07-X01 compara el set final exacto; aviso 1 enviado. | En ruleset id `20571741`, añadir solo context `PASE` a `required_status_checks`; conservar todos los otros campos. Guardar y GET de readback exacto. | Quitar solo `PASE` de `required_status_checks`, guardar y GET; objetivo ≤5 min desde señal. Mantener el resto idéntico. | PASE falta, no termina, da veredicto distinto para mismo head, falso bloqueo, divergencia de aplicabilidad o Train no lo reconoce antes del apply. | 7 días y ≥20 PRs con cobertura de casos variados; si no se alcanza, continuar observando, no avanzar. |
| 2. `pase-merge-gate` | Control 1 estable durante ventana completa; sin rollback; canarios activos verdes; aviso 2 enviado. | Añadir solo context `pase-merge-gate`; confirmar GET que `PASE` continúa y no cambió ningún otro enforcement. | Quitar solo `pase-merge-gate`; GET y comparar con snapshot previo; objetivo ≤5 min. | Bloqueo por base currentness incoherente, head/repo drift falso, fallo sobre control no aplicable, o diferencia con shadow aprobado. | 7 días y ≥20 PRs después de habilitar el segundo control, con al menos uno de cada tipo aplicable. |
| 3. `PASE / MIGRATION_SOURCE_PARITY` | Controles 1–2 estables; parity live sobre migración/no-migration; pruebas de changeset confirman 66/17 no bloquea; aviso 3 enviado. | Añadir solo context `PASE / MIGRATION_SOURCE_PARITY`; readback exacto. No ampliar scope a runner histórico. | Quitar solo `PASE / MIGRATION_SOURCE_PARITY`; readback, conservar PASE/gate/Train. Objetivo ≤5 min. | Cualquier bloqueo causado por deuda fuera del diff, falsa mutación histórica, migración nueva mal clasificada o fallo de fuente/contexto que afecta PR sin cambio de migración. | 14 días y ≥20 PRs con al menos 5 cambios migratorios y 5 sin migración; si no hay volumen, observar hasta cubrir muestra antes de valorar el próximo control. |

El admin anota hora, SHA de ruleset antes/después, set exacto y contexto que produjo rollback. Si una condición requiere cambios de código o workflow, el admin solo revierte y escala al owner; no la corrige en caliente.

## Avisos a equipos — borradores listos para enviar

### Aviso 1 — PASE

> Asunto: PASE requerido en protect-main, fase 1
>
> Vamos a añadir únicamente `PASE` como check requerido de `protect-main`. El shadow exact-head y los siete canarios se revisaron antes del cambio. No se activan los otros checks ni capacidades en este paso. Si el resultado se desvía del shadow, se detiene la cola y se retira solo `PASE`; canalizar evidencia por PR, SHA, check-run y motivo. Observación: 7 días y al menos 20 PRs antes de evaluar la fase 2.

### Aviso 2 — pase-merge-gate

> Asunto: pase-merge-gate requerido en protect-main, fase 2
>
> `PASE` completó su ventana de observación. En una modificación separada se añadirá solo `pase-merge-gate`. Se conserva el set ya vigente y no se activa paridad de migraciones todavía. Ante un falso bloqueo por base/head/alcance, se quita solo `pase-merge-gate` y se registra el SHA/readback del ruleset. Observación: 7 días y al menos 20 PRs antes de evaluar la fase 3.

### Aviso 3 — paridad de migraciones

> Asunto: paridad de migraciones requerida en protect-main, fase 3
>
> Se propone añadir solo `PASE / MIGRATION_SOURCE_PARITY`, tras probar no-migration y migration sobre cambios exactos. La paridad está limitada al changeset; la deuda histórica 66/17 nunca bloquea el PR. Si un bloqueo procede de un path histórico fuera del diff, se revierte solo este check y se conserva evidencia del PR/base/head. Observación: 14 días y al menos 20 PRs, incluidos 5 con cambios migratorios y 5 sin ellos.

Los avisos son borradores; su envío y toda modificación de reglas corresponden al admin/equipos autorizados antes de cada fase.
