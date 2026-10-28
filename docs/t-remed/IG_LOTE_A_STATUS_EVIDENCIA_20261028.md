# LF Input Governance — Lote A, acta de progreso 2026-10-28

> **CONTINUIDAD (2026-10-28):** Se suspende la reclasificación de reglas. Este documento es evidencia de levantamientos anteriores, no metodología aprobada. Primero ratificar estrategia, definiciones y H01–H15, y verificar G0–G4: [contrato director v2](./IG_N4_TREMED_CONTRATO_ESTRATEGIA_DEFINICIONES_REGLAS_V2_20261028.md) y [protocolo preclasificación](./IG_N4_TREMED_PRECLASS_GATES_Y_CASOS_V2_20261028.md). La reclasificación real G5 queda bloqueada.

**Alcance:** P00, P01, P02, P07; rama `dev/ig-n4-tremed-cascade-governed-20261028`, PR #3269 DRAFT / NO-GO. Sin Router, sin cambios Supabase, sin merge ni CI certificada.

| Punto | Estado exacto | Evidencia | Dependencia para cerrar |
|---|---|---|---|
| P00 Baseline | Snapshot de datos y hashes congelado y registrado; inventario transitivo de consumidores parcial | `IG_LOTE_A_P00_BASELINE_EVIDENCIA_20261028.md` | Verificar vistas/API, currentness final y hashes canónicos |
| P01 Contraste semántico | **12 reglas con hipótesis observacionales**: cinco casos base + siete adversariales; NO veredicto autorizado | `IG_LOTE_A_P01_CASOS_OBSERVADOS_20261028.md`, `IG_LOTE_A_P01_ADVERSARIAL_CROSS_DOMAIN_20261028.md` | Evidencias independientes, owner, negativos y resolución de 241 reglas |
| P02 Contexto opcional | 14 selectores ACTIVE / 17 cláusulas auditados; cuatro destinos y operadores probados; 16 pantallas sin módulo | `IG_LOTE_A_P02_CONTEXTO_OPCIONAL_PRUEBAS_20261028.md` | Atributos bajo demanda por regla, fuentes verificables; permiso de función de seguridad no concedido |
| P07 Herencias | **241/241 filas inventariadas y 8.852/8.852 relaciones clasificadas estructuralmente**; cero decisiones de alcance | CSV `IG_LOTE_A_P07_INVENTARIO_241_EVIDENCIA_20261028.csv`, SQL `ig_lote_a_p07_alcance_readonly_20261028.sql`, informe `IG_LOTE_A_P07_COHORTES_VERIFICADAS_20261028.md` | Análisis semántico, excepciones y autorización antes de cortar herencias |

## Métricas P07 observadas y reejecutadas

- 2.201 herencias a 16 pantallas cuyo shell se desconoce, por carecer de módulo.
- 42 herencias cuyo origen no tiene shell verificable (entre destinos de shell conocido).
- 5.230 relaciones a destinos fuera de los shells observados en los vínculos físicos de la regla.
- 1.379 relaciones dentro de shells observados.
- **Partición: 2.201 + 42 + 5.230 + 1.379 = 8.852; PASS de integridad de partición.**
- Las cuatro clases son señales de procedencia, no equivalen a aplicabilidad autorizada o denegada.

## Riesgo nuevo de dependencia

`programacion.fn_input_security_capability_profile` emplea códigos de reglas en la lógica y consume el resolvedor efectivo que hoy incorpora globalidad por frecuencia. Es una función existente; **no** debe reutilizarse como autoridad universal de contexto sin auditoría. La llamada de solo lectura fue denegada por permisos, así que su resultado no está verificado. No ampliar permisos para esta auditoría.

## Reglas del programa

No ejecutar el SQL de desarrollo que elimina `DERIVED_GLOBAL` en bloque hasta conservar mediante selectores las herencias legítimas y documentar las exclusiones. El selector N-4 es responsable del matching; Curator/Validator/gerencia de investigación, evidencia y decisiones; T-REMED conserva su naturaleza reparadora.

**Estado de cierre del lote:** PARCIAL. El inventario estructural es exhaustivo y probado; la validación semántica, recibos gerenciales y pruebas de producción siguen PENDING.
