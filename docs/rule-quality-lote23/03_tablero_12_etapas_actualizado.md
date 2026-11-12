# Lote 23 — Tablero de 12 etapas actualizado a partir de L21

Se conserva el criterio de L21: REAL_EN_SANDBOX = SQL real ejecutado PG18, SINTETICO = stub/fixture, NO_PROBADO = ninguna ruta equivalente. **Solo Curator cambia en 3 escenarios**, de NO_PROBADO a REAL_EN_SANDBOX. El resto se conserva sin crédito adicional.

| Etapa | A: LF nueva | B: LF corregida | C: SALY nueva | Límite |
|---|---|---|---|---|
| Router | SINTETICO | SINTETICO | NO_PROBADO | L18: ACT-0001 no invocado |
| Perfil | SINTETICO | SINTETICO | NO_PROBADO | Perfil no nativo |
| RUN | SINTETICO | SINTETICO | NO_PROBADO | RUN fixture en PG18 |
| IG | SINTETICO | SINTETICO | NO_PROBADO | L11B IG stub; no Input Governance nativo |
| Curator | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | L23 Curator SQL en PG18; A solo dictamen; B y C también apply |
| Validator | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | L18/L17 SQL/familias, no validador productivo nativo |
| Retorno perfil | REAL_EN_SANDBOX | REAL_EN_SANDBOX | SINTETICO | LF SQL readback; SALY fixture |
| Ejecución | SINTETICO | SINTETICO | REAL_EN_SANDBOX | LF parent stub; SALY SQL fixture |
| Promoción | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | L18 LF A/B y SALY; L23 solo B y C con Curator+apply |
| VIGENTE | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | Estados PG18 transitorios, ROLLBACK |
| Readback | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX | SQL estado/recibos, no terminal nativo |
| Cierre | SINTETICO | SINTETICO | SINTETICO | Solo fixture L18 CLOSED_SANDBOX_SIMULATION |

## Porcentaje con fórmula explícita

| Escenario | REAL L21 | REAL L23 | Sintético L23 | No probado L23 |
|---|---:|---:|---:|---:|
| A LF nueva | 5/12 = 41,7% | **6/12 = 50,0%** | 6 | 0 |
| B LF corregida | 5/12 = 41,7% | **6/12 = 50,0%** | 6 | 0 |
| C SALY nueva | 5/12 = 41,7% | **6/12 = 50,0%** | 2 | 4 |
| **Total** | **15/36 = 41,7%** | **18/36 = 50,0%** | **14** | **4** |

Fórmula: sum(celdas REAL_EN_SANDBOX)/(12 etapas × 3 escenarios) ×100 = 18/36 ×100 = **50,0%**. Cambio = 3/36 = **+8,3 puntos porcentuales**. No se cuenta PASS de scripts como avance de etapas.

### Advertencia contra falsos E2E

A LF nueva: L23 probó únicamente preparación de candidata y dictamen Curator, no apply en la misma secuencia. Promoción A sigue REAL_EN_SANDBOX **por L18, antes del Curator**, por lo tanto 50% es cobertura acumulada por etapa, no recorrido E2E A completo.
B LF corregida: Curator ACEPTAR seguido del apply LF congelado y readback READY, pero owner Step70 era fixture HMAC y no nativo.
C SALY nueva: Curator ACEPTAR seguido de apply SALY sintético, sin los gates LF L7/L8 de producción.

**Producción:** 0/36 celdas de flujo E2E nativo acreditadas en estos lotes. No inferir estado general del producto. El Curator productivo sigue NO_PROBADO. Juez/autor GPT-6 es el mismo modelo; independencia NO_ACREDITADA.

**Fuentes:** tablero L21 audits/rule-quality-lote21/03_tablero_12_etapas.md blob bb3faa6b6412b5c540ff0670fb0de0166809e9a6; L18 reporte blob 64f763defa2e929e87539a5507126860ffd61577; L20 reporte blob 4b28a22978061bb049c541a0713636597e830d3b; L23 CI https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43313398467 y runtime SHA-256 2540e2d4ff8ab31b938ff118cfb03fba33f42388b4c10c0bd64c201b7e6665a5.

NO-GO / UNVERIFIED para producción.
