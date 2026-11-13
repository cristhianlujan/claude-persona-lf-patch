# L29 — Tablero ajustado: 12 etapas × 49 reglas REALES B2B

**CI:** [#43340333844](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43340333844), PG18. SHA-256 RAW: `a898a38cb6f8cedaf1271e7390df7517ef8bd3cfce63c60997ae097edd05b08f`. Ninguna regla aprobada o promovida.

| Etapa | REAL_EN_SANDBOX | SINTETICO | NO_PROBADO | Motivo |
|---|---:|---:|---:|---|
| Router | 0 | 0 | 49 | ACT-0001 no ejecutado; B09 |
| Perfil | 0 | 0 | 49 | No se invocó perfil oficial |
| RUN | 0 | 0 | 49 | No se creó, reanudó ni cerró ningún RUN nativo; B02/B03 |
| IG | 0 | 49 | 0 | Loop de revisión SQL del sandbox, no dependencia IG nativa |
| Curator | 49 | 0 | 0 | Mini-Curator determinista ejecutado contra 49 copias reales |
| Validator | 49 | 0 | 0 | SHA de fuente, diff, duplicidad exacta, umbral central y pruebas de bloqueo |
| Retorno perfil | 0 | 0 | 49 | No hubo handoff/retorno del perfil |
| Ejecucion | 0 | 4 | 45 | Cuatro parches solo en draft: AUTH-018/019/020/033 |
| Promocion | 0 | 0 | 49 | Falta firma; sin registrador oficial |
| VIGENTE | 0 | 0 | 49 | 9 VIGENTE de origen, cero transición nueva acreditada |
| Readback | 49 | 0 | 0 | SHA idéntico al SELECT vivo y 49 preimágenes intactas |
| Cierre | 0 | 0 | 49 | Sin Step70 ni recibo terminal oficial |

## Recuento real del nuevo experimento

| Estado | Celdas | Porcentaje |
|---|---:|---:|
| REAL_EN_SANDBOX | **147** | **25,00%** |
| SINTETICO | **53** | **9,01%** |
| NO_PROBADO | **388** | **65,99%** |
| **TOTAL** | **588** | **100%** |

**Fórmula:** 49 × 12 = 588; 100 × 147/588 = **25,00%** de etapas mecánicas dentro del alcance de revisión de las 49 reglas. Dos códigos ausentes NO integran este denominador.

## Comparación explícita: cohortes distintas, NO sumables

| Lote | Cohorte | Real PG18 | Sintético | No probado |
|---|---|---:|---:|---:|
| L26 base | LF nueva, LF corregida y SALY nueva (fixtures) | 21/36 = 58,33% | 11 | 4 |
| L29 previo | 3 variantes LF sobre reglas de muestra | 21/36 = 58,33% | 15 | 0 |
| **L29 ajustado** | **49 reglas reales de Login B2B copiadas** | **147/588 = 25,00%** | **53** | **388** |

Estos porcentajes **no son directamente comparables**: difieren las cohortes, denominadores y fases ejecutadas. No supone una regresión de producto ni puede presentarse como avance productivo de IG. Los 9 registros originalmente VIGENTE no fueron promovidos ni modificados.

## Flujo realmente observado

```text
SELECT vivo solo lectura + SHA → copia íntegra PG18 (49)
  → Curator 1.ª vuelta: 23 ACEPTAR preliminar / 22 ESCALAR / 4 DEVOLVER
  → 4 diffs aplicados solo a drafts PG18 (AUTH-018/019/020/033)
  → Curator 2.ª vuelta: 4 ESCALAR
  → 23 preliminares / 26 escaladas / 2 ausentes
  → NO HAY FIRMA → BLOQUEO PROMOCIÓN → NO-GO
```

Cuatro propuestas de políticas 3,19,20,25 también se aplicaron a drafts independientes del sandbox (4/4), no al origen. Se detuvo la revisión sin vueltas artificiales donde dependía de decisiones no confirmadas o pruebas externas.

## B09 y las 14 condiciones de producción

El runner NO ejecutó ACT-0001, perfil real, RUN, IG nativo, Step70, OIDC, promoción ni cierre terminal. B07 (columnas lifecycle), B08 (identidad), B12 (funciones legacy) y B02/B03 (RUN existentes/efectos) permanecen pendientes. **Bloqueos cerrados 0/14**.

**Gates:** no se editaron funciones congeladas; MD5 de la prueba PG18 previa: apply `86b0494984edf95cf0f9c0a0df67000b`, capture `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, L8 guard `522d12f0843be1da3c785cef3c0bf3fc`. **No se recalcularon en este runner real**, ya que no hubo promoción.

**Curator:** SQL determinista del mismo GPT-6; no juez independiente. **JWT:** no se probó autenticación real; el HMAC de laboratorio es del L29 previo. **NO-GO / UNVERIFIED.**
