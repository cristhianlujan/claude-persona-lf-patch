# L26 — Contrato de integración medido, límites y control de cambios

## Contexto verificable antes de CI

- **Base:** `48f1e316d81c83ca2f880372a3a050b456c6b3ab` (HEAD final de L22).
- **Origen L23:** `686cc39a7b8a9178ccf004423ba3c87131047a29` (Curator SQL determinista de PG18; 17/17 del lote aislado).
- **Origen L24:** `64764c58109345b1f086f9ebc7cc0c1040fdd656` (recibo cierre PG18; 23/23 del lote aislado).
- Se han integrado **13 archivos** de esas ramas mediante **blobs exactos**, y no mediante una modificación del código de sus respectivos lotes. Los árboles de fuente sí son nuevos al convivir en L26; no se afirma que las historias Git hayan sido fusionadas por merge commit.
- L23 y L24 **usan nombres de archivo diferentes con prefijo 15**; no existe colisión.

## Identidad de los SQL originales (readback Git blob SHA)

| Lote | SQL original | Blob origen | Blob incorporado | Estado |
|---|---|---|---|---|
| L23 | `sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/15_l23_curator_stage_pg18.sql` | `9eecdce422c45e048e1db2f11b36fc66825ddf9c` | `9eecdce422c45e048e1db2f11b36fc66825ddf9c` | **IDENTICO** |
| L24 | `sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/15_l24_verifiable_closure_pg18.sql` | `1f068829c6f4e3366687266f376188ef4b4f1360` | `1f068829c6f4e3366687266f376188ef4b4f1360` | **IDENTICO** |

## Cambios agregados por L26 (solo en rama)

- `16_l26_curator_to_closure_bridge_pg18.sql`: **nuevo**, no reemplaza L23, L24, frozen gate ni L20. Registra un recibo de promoción append-only después de L14, verifica el sello del dictamen original L23, y bloquea el INSERT del recibo L24 si no hay promoción registrada.
- `test_pg18_lote26_integrated_curator_closure.py`: **nuevo**, los escenarios positivos integran todos los pasos en el **mismo BEGIN** y luego ejecutan ROLLBACK. La matriz de privilegios comprueba roles en SQL reales con `SET SESSION AUTHORIZATION` de fixture PG18.
- `.github/workflows/l26-integrated-curator-closure-pg18.yml`: **nuevo**, ejecuta L13 28, todos los `test_pg18_*.py` de forma aislada y verifica un informe de 12 etapas medido en la transacción, sin sumar resultados históricos.

### Precisión sobre el caso LF nueva

El Curator L23 detectó una contradicción de `valor_config` al tratar `REG_SEG_004` como nueva junto a `RULE-DEPENDENCY-001` VIGENTE. L26 **no cambia la detección**. A_NEW usa un **banco PG18 inicializado de forma aislada**: antes de instalar los guards L17 se clasifica `RULE-DEPENDENCY-001` en una categoría de fixture no comparable con la futura candidata. La regla candidata `REG_SEG_004`, su `valor_config` y los inputs del gate L11B permanecen inalterados. No se desactiva ningún trigger. La preparación del banco ocurre **antes del BEGIN medido**; posteriormente solo se ejecuta la secuencia gobernada A y se descarta ese banco. B_CORRECTED y C_SALY_NEW usan un **segundo banco PG18 limpio con datos originales**, por lo que B mantiene el conflicto real y exige sucesión explícita del owner HMAC. Este preacondicionamiento se limita a la construcción de un fixture de laboratorio y no es una política ni mutación productiva.

## Secuencia que debe quedar demostrada

```text
Solicitud/fixture LF o SALY
  -> perfil/owner L13+L17 (HMAC de laboratorio; no Auth real)
  -> L23 Curator ACEPTAR + HMAC + fingerprint fresco
  -> L14 ticket ARMED (trigger L23) -> apply congelado LF / fixture SALY
  -> L14 y L20 readback READY, registro VIGENTE, fuente VIGENTE
  -> caso B: L20 sincroniza regla anterior SUCEDIDA en ambas fuentes
  -> L26 recibo de promoción separado con hash y sello original Curator
  -> L26 cierra -> L24 recibo append-only -> L24 verify SHA256
  -> SQL readback de ambos recibos y estado -> ROLLBACK
```

## Diseño del puente y su límite

El fingerprint completo L23 se vincula al candidato EN_REVISION y al conjunto VIGENTE **antes de aplicar**. No puede recalcularse después de promocionar sin producir un falso rechazo: el universo VIGENTE cambia. L26 mantiene esa evidencia previa y vuelve a verificar el HMAC, actor, código y fingerprint sellado, aprovechando que el **trigger L23 original comprobó frescura** al armar el ticket. Por ello L26 no sustituye el control de frescura L23.

El recibo de promoción persiste el readback `READY` y un hash de sus campos de autoridad estables; la inserción de L24 solo puede ocurrir cuando ambos se relacionan, el juez no está manipulado y L20 observa divergencias 0. **No es un anclaje firmado por un receptor oficial externo**.

## Método del tablero

El runner L26 construye cada una de las **12 filas por escenario a partir de RAW de la misma transacción**, sin importar tableros L23/L24 de ejecuciones previas:

`% REAL_EN_SANDBOX = 100 × n(REAL_EN_SANDBOX)/(12 × 3)`.

Cada etapa exige un campo concreto: Curator `ACEPTAR`, `WRAP.gate APPLIED`, `profile_return READY`, `l20 divergences 0`, recibo promoción 1, recibo cierre 1 y `VERIFIED_CLOSURE_HASH`, o aparece como `SINTETICO`/`NO_PROBADO`. No se contará una etapa como producción real por haber pasado PG18.

## Seguridad y límites

- Las pruebas están ejecutadas/pendientes únicamente en **PostgreSQL 18 desechable**. Supabase vivo: SELECT como máximo, cero DML/DDL.
- `SUPER_ADMIN`, roles sin grants y los demás roles deben ser denegados para INSERT/UPDATE/DELETE/TRUNCATE/ALTER DISABLE TRIGGER en dictámenes, recibo promoción y recibo cierre.
- JWT L17 es **HMAC de prueba**; Step70/IG/Router/perfil/RUN real y recepción oficial final no están simulados como nativos.
- Curator es **SQL determinista del mismo modelo GPT-6**, no independiente ni revisión semántica completa.
- Ninguna prueba de PG18 permite elevar producto/producción a READY.
- **Estado producción obligado:** `NO-GO / UNVERIFIED`, incluso con toda la CI de laboratorio en PASS.

**Estado de aceptación CI:** consultar el manifiesto L26 de ejecución y el informe de pruebas, nunca esta especificación como sustituto del readback.
