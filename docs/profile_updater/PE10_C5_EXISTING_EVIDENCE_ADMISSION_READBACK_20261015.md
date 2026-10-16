# PE10_C5 — cotejo de evidencia existente y contrato de admisión

**Fecha:** 2026-10-15 · **Plan:** `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1` · **Unidad:** PE10 · **Operación:** `ACTUALIZACION_PERFIL_LF`.

**Naturaleza:** evaluación de evidencia **ya producida** (READ ONLY). No es una nueva evaluación independiente, un nuevo productor, un recibo de admisión ni una activación de producción.

## Resultado observado

- `PE10_C3=DONE`: evaluación **realizada y reconciliada**, resultado `NOT_ADMITTED_NO_CURRENT_PASS_RECEIPT`; evento `public.lf_eventos.id=21093`; no representa `independent_assurance=PASS`.
- `PE10_C4=DONE`: cero ejecuciones `ACTUALIZACION_PERFIL_LF` en `IN_PROGRESS`, cero no clasificadas; evento `public.lf_eventos.id=21174`.
- `PE10_C5=PENDING`: la consulta del contrato devuelve `admissible_events=0` frente a `pass_when.admissible_events=1`. No emitir recibo `PASS`.
- **Estructura candidata v0.2:** dos pasos nuevos existentes e `inactive` (`method_selection`, `evolution_decision`), una política `POL-PROFILE-UPDATE-PASS/v1.4-evolved-routing-candidate` en `CANDIDATE`, cero contratos v0.2 publicados, `lf_operation_registry.ACTUALIZACION_PERFIL_LF=v0.1/PRODUCCION_CONTROLADA`.
- PR [#2619](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2619) ya **merged**, con staging gobernado. PR [#2748](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2748) (correcciones acotadas de despliegue) sigue **draft/open**; sus cambios NO se presumen aplicados.

## Evidencia favorable existente (no repetirla)

| Evidencia | Resultado observado | Alcance / techo explícito |
|---|---|---|
| `PE10_C2` — corpus pareado 24 casos | baseline **0.250000** → candidato **1.000000**; IC95 delta [0.583333, 0.916667], regresiones críticas 0 | `DECISION_POLICY_AND_COMPOSITION`; recibo `cutover_eligible=false`, no certificado comportamiento pleno por este solo puntaje |
| `PE10_C2B` — 21 casos GPT Native | baseline **0.285714** → candidato **0.971429**; IC95 delta [0.533333, 0.828571], false-pass 6→0, regresiones críticas 0 | `FULL_PROFILE_EVOLUTION_BEHAVIOR`; recibo `independent_assurance=NOT_EXECUTED` y `cutover_eligible=false` |
| `PE10E_C4` — piloto cualitativo | `ACCEPTED_QUALITATIVE_FIRST_EVOLUTION`, 5 requisitos observados en evolucionado vs 2 en original | Admisión de la **primera evolución**; no verifica aislamiento, experto estadístico, runtime normal ni activación v0.2 |
| `PE10_C3` — comparación semántica existente | Casos 206 (preferencia semántica acotada) y 212 (empate); evidencia congelada conciliada | Evento 21093: `independent_review_pass=false` y `operational_cutover_allowed=false`; ningún `INDEPENDENT_REVIEW_RECEIPT PASS` de este sujeto |

Estos resultados **sí acreditan mejora en los alcances medidos**; `NOT_ADMITTED` **no los invalida**. Lo que no acreditan es una mejora experta general ni una aprobación independiente para activar la operación completa.

## Problemas precisos del contrato/ejecutor PE10_C5

1. **Bloqueo admisorio verdadero:** El contrato vigente exige evento `PROFILE_EVOLUTION_CUTOVER_ADMITTED` con `benchmark_ref`, `safe_change_admission_ref`, `independent_assurance_ref` y `independent_assurance=PASS`. Evento real admisible: **0**. El dictamen C3 conciliado es **NO ADMITIDO**, y no debe convertirse en `PASS` retroactivamente.
2. **Control de referencias incompleto:** La consulta exacta C5 usa `nullif(payload->>'..._ref','') IS NOT NULL` para las tres referencias. Eso prueba **presencia de texto**, no existencia, identidad del sujeto, vigencia, integridad, independencia ni estado `VERIFIED` en el ledger. Antes de cualquier admisión debe haber verificación positiva/negativa de la procedencia y hashes exactos; el resultado de la query actual **no basta** para certificar fuentes.
3. **Tipo de evento no habilitado:** Lectura de `private.lf_event_type_contracts_v2` no devuelve un contrato activo para `PROFILE_EVOLUTION_CUTOVER_ADMITTED`. El canal de eventos es `default-deny`: no inventar inserción ni saltar gobernanza. Si se decide admisión, tramitar el tipo mediante el procedimiento existente y Train, luego prueba con rollback.
4. **Alcance mezclado:** C2/C2B miden mejora de políticas y comportamiento en casos, pero los recibos declaran `cutover_eligible=false`; PE10E_C4 fue aceptación de **primera evolución**. No sustituir sin más una certificación de experto/general por esos scores, ni hacer que una conclusión administrativa `DONE` de C3 implique `independent_assurance=PASS`.
5. **Correcciones del despliegue:** PR #2748 sigue en borrador. Sus cambios deben reconciliarse con `main` y el candidato exacto de v0.2 para evitar dejar errores conocidos en una posible activación.

## Disposición propuesta (sin ejecutar cutover)

**No hay necesidad de reconstruir v0.2 ni repetir 24+21 casos.** Se propone una **admisión acotada por capacidades demostradas**, a tramitar como cambio explícito al contrato de despliegue, no como falsificación del gate actual:

- Alcance candidato: **decisión/composición/método de routing probados**. No certificar autonomía experta, especialización por dominio, aprendizaje sostenido ni adaptación operacional fuera de los resultados observados.
- Condición para un piloto controlado: anclar sujeto y versión exacta a C2/C2B, verificar ausencia de regresiones conocidas y las correcciones del PR #2748, prueba transaccional C6 **positiva y negativa** sobre SQL de candidato exacto y rollback sin residuo; ejecutar controles operativos mínimos de rollback/fail-closed. No alterar `independent_assurance` histórico ni usar `PROFILE_EVOLUTION_CUTOVER_ADMITTED` sin su contrato.
- **Dos decisiones separadas:** (a) admisión limitada de las mejoras medidas, si la gobernanza redefine explícitamente esa modalidad y verifica sus fuentes; (b) admisión de evolución experta general, que permanece no demostrada. La opción (a) NO habilita automáticamente activación irrestricta de (b).
- C5 **sigue PENDING**. Cambiar el contrato o habilitar una admisión limitada requiere una propuesta acotada y validación de los controles; mientras tanto v0.1 sigue activa y v0.2 permanece candidato.

## Criterio de continuación

1. Conservar este diagnóstico y los hashes/resultados de C2/C2B/PE10E/C3 ya existentes, sin nuevas campañas semánticas.
2. Resolver exclusivamente las fallas verificadas del transporte de admisión y limitar el alcance certificable (no exigir dominio experto a la mejora de decisión comprobada, pero no eliminar el control de seguridad).
3. Ejecutar primero rollback positivo/negativo de la eventual modificación contractual y luego registrar lo aplicado con readback Git=ledger=DB. C6/C7 sólo tras C5 realmente admisible.

**Fuente:** lecturas de Supabase de `engineering_work_checkpoints`, `engineering_plan_units`, `lf_operation_registry`, `lf_operation_steps`, `lf_policy_versions`, `lf_eventos`, `private.lf_evidence_ledger_v1` y catálogo de tipo de evento; revisión de PR #2619/#2748 y scripts `20261013090000` / `20261014221001` en GitHub.

**Estado final de esta revisión:** `C5_ADMISSION_NOT_MET`; mejoras medidas preservadas; **no** se modificó producción, política activa, checkpoint ni ledger.
