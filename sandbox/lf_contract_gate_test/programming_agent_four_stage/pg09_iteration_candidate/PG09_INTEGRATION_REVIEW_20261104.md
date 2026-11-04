# Revisión de integración PG-09_C1–C5 — 2026-11-04

**Dictamen:** SOURCE_REVIEW_WITH_FIX / INTEGRATION_NOT_QUALIFIED / OFFICIAL_PENDING.

Se verificó por lectura directa que existen cinco productores candidatos y que C2→C1, C3→C2, C4→C1/C2/C3 y C5→C4 conservan huellas de fuente declaradas. No se ejecutó el pipeline, ninguna herramienta de prueba ni el Worker real.

## Hallazgo y corrección
**INTEGRATION-PG09-01 (resuelto en fuente):** C5 podía aceptar para `BUDGET_80_WARNING` una respuesta C4 genérica `RETURN + REVIEW_REQUIRED`, aunque C1 no hubiera reportado aviso al 80 %. Se añadió el sobre C1 a cada fixture de C5, vinculándolo con `source_pg09_c1_sha256` de C4, `run_ref` y el diagnóstico correspondiente. Ahora la coincidencia estructural del escenario del 80 % exige `request_diagnostic=WARN_80_PERCENT`, `eighty_percent_warning_reported=true` y ausencia de decisión requerida. También se verifican señales C1 para los escenarios de costo desconocido, 100 % e intentos agotados.

**Límite:** los sobres C1/C4 y los fixtures siguen siendo declaraciones no autenticadas. La corrección no demuestra que el costo real alcanzara el umbral ni que se haya detenido un Worker. Para el 100 %, una medición auténtica debe demostrar el límite contra el importe real y descartar un `REQUIRES_DECISION` provocado por otra razón. Esta distinción permanece abierta.

## Estado por checkpoint
- C1: proyección de costo con aritmética decimal y decisiones tipadas, sin verificación de consumo real.
- C2: comparación declarada de hallazgos/evidencias; no certifica equivalencia semántica ni detención del ejecutor.
- C3: clasifica cambios de reglas, supresiones y pruebas; no inspecciona realmente el diff ni valida waiver.
- C4: sintetiza RETURN/BLOCKED; no entrega ni ejecuta el escalamiento.
- C5: matriz adversarial obligatoria de nueve casos, con comprobaciones estructurales mejoradas; ninguna ejecución, recibo ni veredicto.

## Riesgos y requisitos para GO
Se requieren fixtures auténticos, invocación de C1–C4 con historia real, pruebas negativas del Worker, recibos de uso/costo, comprobación de equivalencia de findings, detección de cambios de reglas sobre diff real y calificador independiente. El estado oficial sigue PENDING.

**Siguiente desarrollo candidato:** PG-10_C1, tipificación de conflicto entre requisito, estándar, contrato y REUSE_AS_IS. El trabajo permanece en PR #3528 draft sin tocar main, Análisis, Supabase o producto.
