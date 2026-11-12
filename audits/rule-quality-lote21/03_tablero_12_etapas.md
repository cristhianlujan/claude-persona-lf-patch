# Lote 21 — Tablero honesto 12 etapas (L18 + L20)

**Definiciones:** `REAL_EN_SANDBOX` = SQL/función efectivamente ejecutada en PG18 aislado, no control real de producción. `SINTETICO` = fixture/stub/handoff fabricado expresamente para la prueba. `NO_PROBADO` = ruta equivalente no ejecutada. La reclasificación que sigue preserva los estados publicados por L18; L20 añade evidencia de sincronización a VIGENTE y Readback, no convierte Router, perfil ni Step70 en reales.

| Etapa | A — LF nueva | B — LF corregida | C — SALY nueva | Evidencia/limitación |
|---|---|---|---|---|
| Router | SINTETICO | SINTETICO | NO_PROBADO | A/B fixture, ACT-0001 no invocado; SALY sin Router |
| Perfil | SINTETICO | SINTETICO | NO_PROBADO | Perfil/owner inyectados; no ejecución nativa |
| RUN | SINTETICO | SINTETICO | NO_PROBADO | RUN de sandbox sin registro nativo |
| IG | SINTETICO | SINTETICO | NO_PROBADO | IG L11B stub, Step70 sintético |
| Curator | NO_PROBADO | NO_PROBADO | NO_PROBADO | No hubo Curator auténtico |
| Validator | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | L7/L8 LF SQL; SALY valida identidad/familias, no gate LF |
| Retorno perfil | REAL_EN_SANDBOX | REAL_EN_SANDBOX | SINTETICO | SQL readback LF, SALY fixture READY; sin transporte real |
| Ejecución | SINTETICO | SINTETICO | REAL_EN_SANDBOX | Stub LF, apply SQL SALY sintético en PG18 |
| Promoción | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | Apply LF congelado en transacción; SALY fixture |
| VIGENTE | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | L20 prueba SYNC fuente LF/SALY en PG18 solo para regla objetivo |
| Readback | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | L18/L20 verifican source/registry, tras ROLLBACK |
| Cierre | SINTETICO | SINTETICO | SINTETICO | CLOSED_SANDBOX_SIMULATION, NO nativo |

## Conteo y fórmula (no sumar suites como pruebas independientes)

| Escenario | REAL_EN_SANDBOX | SINTETICO | NO_PROBADO | Cobertura etapa real PG18 |
|---|---:|---:|---:|---:|
| A_NEW | 5 | 6 | 1 | 41.7% = 5/12 |
| B_CORRECTED | 5 | 6 | 1 | 41.7% = 5/12 |
| C_SALY_NEW | 5 | 2 | 5 | 41.7% = 5/12 |
| **TOTAL** | **15** | **14** | **7** | **41.7% = 15/36** |

**Fórmula de cobertura de etapas:** `real_en_sandbox / 12 × 100` por escenario, o `sum(real_en_sandbox) / (12×3) ×100` consolidado. Cada etapa vale una unidad, sin ponderación ni incluir estados sintéticos. **Resultado 41.7%** no es una tasa de éxito ni de readiness de producción.

**Pruebas mecánicas PG18 L20:** 18/18 scripts `test_pg18_*.py` PASS = **100% ejecución de scripts**, pero hay solapamiento entre L13(28), L14(18), L17(25), L18(16), L20(17): **no sumar recuentos**. Fuente L20 commit probado `b7e362b36e82b4075bc9effc363ec777c6756d87`, CI #43305361826, reporte blob `4b28a22978061bb049c541a0713636597e830d3b`.

**Producción real acreditada:** `0 / 36 = 0%` de celdas con flujo nativo real firmado (Router, perfil, RUN, IG, Step70/OIDC, Curator, juez, cierre). Es **0% de evidencia E2E de producción acreditada por estos lotes**, no una medición de cobertura general del producto.

**Aprobación del dueño sobre adopción:** 0/32 = **0% decisiones firmadas**. No equivale al 0% de funcionalidad implementada.

## L20 mejora localizada sin falsear las 12 etapas
En PG18 L20 (17/17 controles) ejecutó tres escenarios (SUCEDIDA LF, CADUCADA LF, CADUCADA SALY) con sincronización `l20_owner_decide_and_sync_v1` y readback 1→0 divergencias de **la regla objetivo**, rollback verificado. El detector no acredita convergencia global. SALY usa marcador `metadata.l20_lifecycle_state` solo laboratorio y sigue sin IG/Step70 nativos.

**Fuente L18:** `docs/rule-quality-lote18/03_integrated_cycle_audit.md` blob `64f763defa2e929e87539a5507126860ffd61577`, CI HEAD `abeea154a559759dcf2f56f42c8fd106ca768b64`, CI #43299324221.
**Fuente L20:** `docs/rule-quality-lote20/03_resultado_y_limites.md` blob `4b28a22978061bb049c541a0713636597e830d3b`, CI HEAD `b7e362b36e82b4075bc9effc363ec777c6756d87`.

Todas las asignaciones de relevancia productiva y fórmulas son **SUGERENCIA / REQUIERE_REVISION_SEMANTICA**. No hay juez independiente; GPT es el mismo modelo.
