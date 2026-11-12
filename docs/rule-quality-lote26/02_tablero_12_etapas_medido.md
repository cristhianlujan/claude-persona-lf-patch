# Lote 26 — Tablero de 12 etapas medido en una secuencia completa por escenario

**Resultado de la CI:** `SUCCESS` en PG18 limpio; **estado productivo:** `NO-GO / UNVERIFIED`. No es un reporte acumulado de L23 + L24.

## Fórmula reproducida desde las 36 celdas RAW

```
% REAL_EN_SANDBOX =
  100 * COUNT(status == "REAL_EN_SANDBOX" en las tres matrices)
        / (12 etapas * 3 escenarios)
  = 100 * 21 / 36
  = 58.33%
```

| Estado | Filas observadas |
|---|---:|
| `REAL_EN_SANDBOX` | 21 |
| `SINTETICO` | 11 |
| `NO_PROBADO` | 4 |
| **Total** | **36** |

## Comparación de estados, sin reutilizar tableros externos

| Etapa | A LF nueva | B LF corregida | C SALY nueva |
|---|---|---|---|
| Router | `SINTETICO` | `SINTETICO` | `NO_PROBADO` |
| Perfil | `SINTETICO` | `SINTETICO` | `NO_PROBADO` |
| RUN | `SINTETICO` | `SINTETICO` | `NO_PROBADO` |
| IG | `SINTETICO` | `SINTETICO` | `NO_PROBADO` |
| Curator | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` |
| Validator | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` |
| Retorno perfil | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `SINTETICO` |
| Ejecucion | `SINTETICO` | `SINTETICO` | `REAL_EN_SANDBOX` |
| Promocion | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` |
| VIGENTE | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` |
| Readback | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` |
| Cierre | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` |

**Precisión:** `REAL_EN_SANDBOX` significa que código SQL/fixture se ejecutó efectivamente en PG18; no acredita actividad de un perfil, Curator, QA, juez o receptor nativo. En C, SALY recibió un `apply` de laboratorio: ni su sistema productivo ni su Step70 fueron ejecutados.

## A_LF_NEW — 7/12 = 58.33% real mecánico en sandbox

La evidencia de cada fila fue producida en **una única transacción**. La promoción y el cierre se observaron con **1 recibo cada uno**, luego ambos desaparecieron al ejecutar `ROLLBACK`.

| Etapa | Estado | Evidencia RAW asociada |
|---|---|---|
| Router | `SINTETICO` | L11B parent fixture, ACT-0001 no se invoco |
| Perfil | `SINTETICO` | L11B fake owner profile; no ejecucion nativa |
| RUN | `SINTETICO` | L11B system_attestation=false, no 11/11 real |
| IG | `SINTETICO` | L11B stub + IG gate status READY_FOR_PROFILE_APPROVAL |
| Curator | `REAL_EN_SANDBOX` | Misma transaccion: L23 ACEPTAR, sello HMAC 15e1e336820f1f03 |
| Validator | `REAL_EN_SANDBOX` | L7 exact capture VERIFY=VERIFIED_CAPTURE_BINDING e IG=READY_FOR_PROFILE_APPROVAL |
| Retorno perfil | `REAL_EN_SANDBOX` | Gate LF profile_return READY from frozen function |
| Ejecucion | `SINTETICO` | L11B owner RUN fixture with system_attestation=false |
| Promocion | `REAL_EN_SANDBOX` | L14 SQL gate LF APPLIED + L26 promotion receipt 7640da6071c813aa |
| VIGENTE | `REAL_EN_SANDBOX` | L13/source source=VIGENTE registry=VIGENTE |
| Readback | `REAL_EN_SANDBOX` | L20 detector target=0, L26 promotion record READY |
| Cierre | `REAL_EN_SANDBOX` | L26 closure insert + L24 VERIFY_CLOSURE_HASH=VERIFIED_CLOSURE_HASH |

**Readback de promoción:** `PROMOTION_RECEIPT_RECORDED` · SHA-256 `7640da6071c813aa2c1930134201cd3f12e36ad2f12a4a1ed2e042fda2caaf80`.

**Cierre:** `INTEGRATED_CLOSED_VERIFIED_PG18` · comprobación `VERIFIED_CLOSURE_HASH` · SHA-256 `0792a6b79e0c25f642e7effd5b7282a77d7e0ded49d6ede4f7182da7eda91823`.

**L20:** divergencia objetivo `0`; estado registro `VIGENTE`, fuente `VIGENTE`.

**Rollback:** `{"closure":0,"curator":0,"promotion":0,"quality":0,"source_count_or_active":0}`.

## B_LF_CORRECTED — 7/12 = 58.33% real mecánico en sandbox

La evidencia de cada fila fue producida en **una única transacción**. La promoción y el cierre se observaron con **1 recibo cada uno**, luego ambos desaparecieron al ejecutar `ROLLBACK`.

| Etapa | Estado | Evidencia RAW asociada |
|---|---|---|
| Router | `SINTETICO` | L11B parent fixture, ACT-0001 no se invoco |
| Perfil | `SINTETICO` | L11B fake owner profile; no ejecucion nativa |
| RUN | `SINTETICO` | L11B system_attestation=false, no 11/11 real |
| IG | `SINTETICO` | L11B stub + IG gate status READY_FOR_PROFILE_APPROVAL |
| Curator | `REAL_EN_SANDBOX` | Misma transaccion: L23 ACEPTAR, sello HMAC 1efa6375cb19605b |
| Validator | `REAL_EN_SANDBOX` | L7 exact capture VERIFY=VERIFIED_CAPTURE_BINDING e IG=READY_FOR_PROFILE_APPROVAL |
| Retorno perfil | `REAL_EN_SANDBOX` | Gate LF profile_return READY from frozen function |
| Ejecucion | `SINTETICO` | L11B owner RUN fixture with system_attestation=false |
| Promocion | `REAL_EN_SANDBOX` | L14 SQL gate LF APPLIED + L26 promotion receipt c95462ba8a67c336 |
| VIGENTE | `REAL_EN_SANDBOX` | L13/source source=VIGENTE registry=VIGENTE |
| Readback | `REAL_EN_SANDBOX` | L20 detector target=0, L26 promotion record READY |
| Cierre | `REAL_EN_SANDBOX` | L26 closure insert + L24 VERIFY_CLOSURE_HASH=VERIFIED_CLOSURE_HASH |

**Readback de promoción:** `PROMOTION_RECEIPT_RECORDED` · SHA-256 `c95462ba8a67c336893bb90dc990ca35f970a57372a70d43592440effd5bf113`.

**Cierre:** `INTEGRATED_CLOSED_VERIFIED_PG18` · comprobación `VERIFIED_CLOSURE_HASH` · SHA-256 `df62af2bf4fed1de2f645405be2a25de1b33f6833163042fc4540a3ec5e6f4cc`.

**L20:** divergencia objetivo `0`; estado registro `VIGENTE`, fuente `VIGENTE`. Predecesora `SUCEDIDA` / fuente `SUCEDIDA`.

**Rollback:** `{"closure":0,"curator":0,"promotion":0,"quality":0,"source_count_or_active":0}`.

## C_SALY_NEW — 7/12 = 58.33% real mecánico en sandbox

La evidencia de cada fila fue producida en **una única transacción**. La promoción y el cierre se observaron con **1 recibo cada uno**, luego ambos desaparecieron al ejecutar `ROLLBACK`.

| Etapa | Estado | Evidencia RAW asociada |
|---|---|---|
| Router | `NO_PROBADO` | No router SALY invocado |
| Perfil | `NO_PROBADO` | No perfil SALY nativo |
| RUN | `NO_PROBADO` | No RUN SALY nativo |
| IG | `NO_PROBADO` | No IG nativo SALY |
| Curator | `REAL_EN_SANDBOX` | Misma transaccion: L23 ACEPTAR, sello HMAC 137828dd273f4394 |
| Validator | `REAL_EN_SANDBOX` | L13 familia preparada + L17 signed HMAC + L23 guard |
| Retorno perfil | `SINTETICO` | L14 SALY fixture READY (no transporte real) |
| Ejecucion | `REAL_EN_SANDBOX` | SQL SALY L14 adapter actually ran, not product execution |
| Promocion | `REAL_EN_SANDBOX` | SALY synthetic L14 SQL applied + L26 separate promotion receipt d4427a6117a4423c |
| VIGENTE | `REAL_EN_SANDBOX` | L13/source source=VIGENTE registry=VIGENTE |
| Readback | `REAL_EN_SANDBOX` | L20 detector target=0, L26 promotion record READY |
| Cierre | `REAL_EN_SANDBOX` | L26 closure insert + L24 VERIFY_CLOSURE_HASH=VERIFIED_CLOSURE_HASH |

**Readback de promoción:** `PROMOTION_RECEIPT_RECORDED` · SHA-256 `d4427a6117a4423c85a89739345fed78ca5d7a40cc8b0dc1064e8f5cc1ba136d`.

**Cierre:** `INTEGRATED_CLOSED_VERIFIED_PG18` · comprobación `VERIFIED_CLOSURE_HASH` · SHA-256 `3e3f8e7818b2de3f5c0240f574d3672ea65bafccbdffa93fcc11955ad864ffad`.

**L20:** divergencia objetivo `0`; estado registro `VIGENTE`, fuente `VIGENTE`.

**Rollback:** `{"closure":0,"curator":0,"promotion":0,"quality":0,"source_count_or_active":0}`.


## Controles cruzados y denominadores

Se midió desde `MEASURED` (función de solo lectura L26 autenticada bajo JWT HMAC L17) y desde salidas RAW de `CURATOR`, `WRAP`, `PROMOTION_RECEIPT`, `CLOSE` y `VERIFY_CLOSURE`, siempre **en el mismo BEGIN**. Solo después se consultó un readback tras `ROLLBACK` para descartar persistencia de prueba.

**A** usa un PG18 limpio con fixture no conflictivo preparado **antes de instalar los guards L17**. **B/C** usan otro PG18 limpio con la fuente original intacta. El preacondicionamiento A no equivale a cambiar una fuente VIGENTE operativa ni a alterar un gate.

El aumento frente a L23/L24 es cobertura **integrada y medida**, no suma aritmética de pruebas aisladas. Persisten como `SINTETICO`/ `NO_PROBADO` todos los pasos sin transporte o recibo nativo demostrado.

**Requisitos NO_PROBADOS:** ACT-0001 real, Perfil/RUN oficial completo de 11 pasos, Curator de producción, Step70/OIDC verdaderos, juez semántico independiente, Supabase Auth real y recepción oficial del cierre. JWT L17 es HMAC de prueba y Curator L23 es SQL determinista del mismo GPT-6.

**Proveniencia:** archivo `01_resultados_reales_pg18.json`, sección `actual_runner.scenarios[].board`, CI `43328149868`, SHA del JSON runtime `a03177a4a4711de4fb2e4d62387b5ea0f823fb925cfc87b5d4bf352b83e34135`. Estado productivo `NO-GO / UNVERIFIED`.
