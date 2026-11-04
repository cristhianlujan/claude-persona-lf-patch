# PROGRAMMING_ANALYSIS_LF — Skill única de Análisis

**Estado:** `CANDIDATE_SOURCE_ONLY_NOT_REGISTERED`. **Una skill** para toda la etapa, con **15 pasos internos A1–A15**. Nunca registrar A1 como habilidad individual.

## Consumo
El perfil del Agente de Programación selecciona la única skill `PROGRAMMING_ANALYSIS_LF`. El perfil conserva el control de autorización, transporte OIDC, identidad, registros y readback. Análisis administra la secuencia interna y entrega un resultado consolidado al mismo perfil. Router solo encamina; no invoca la skill.

## Estructura canónica
El manifiesto `contracts/analysis_skill_manifest_v1.json` enumera y referencia sin copiar los contratos de los 15 pasos.

- **A1:** interpretación/normalización de prompt y contexto, código local migrado a `steps/a1/`; `REQUEST_CONTEXT_V1`.
- **A2–A3:** clasificación (profundidad y alcance) y fuentes EKB/autoridades/estado de implementación.
- **A4–A6:** impacto transversal, decisiones/ADR e implementabilidad.
- **A7–A9:** frentes materiales, STOP de investigación y paquete/snapshot/handoff consolidado.
- **A10–A15:** evidencia histórica, adversarial, benchmark, reparación, holdout y freeze. Son controles de calificación del mismo paquete; **no** mutaciones automáticas en cada solicitud.

La definición exacta A1–A9 sigue en `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_procedure_v1.json`; A10–A15 se enlazan a sus fuentes canónicas ya existentes. Nada de copiar fuentes oficiales ni motores paralelos.

## Entradas y resultado
Entrada literal + contexto transportado por el perfil. A1 preserva códigos/nombres/refs disponibles sin inventar. Análisis debe consolidar `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` y `PROGRAMMING_CONTEXT_SNAPSHOT_V1`, con estado por scope, evidencias, decisiones y hashes. Un PASS interno de A1 **no** equivale a `ANALYSIS_READY`.

## Control de ejecución
Este PR corrige el **paquete y el alcance de la skill**; solo A1 dispone de implementación local candidata. A2–A15 tienen referencias de contrato y **no están cableados ni calificados** como módulos operativos de la skill. Sin modelo/juez independiente real, transporte/readback del mismo RUN y validación de todos los pasos necesarios, `SKILL_READY` y `SKILL_INTEGRATED` están prohibidos. No ejecutar SQL desde rol read-only, no ampliar ACL, no cambiar Router, no usar `lf_record_creacion_skill_step_v1` para un step de ejecución y no reutilizar `DONE` históricos de A1/A1Q.
