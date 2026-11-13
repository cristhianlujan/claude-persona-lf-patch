# Lote 29 — Tablero 12 etapas, medido exclusivamente en la CI de PG18

**CI:** GitHub Actions #43336082581, **SUCCESS**, test `test_pg18_lote29_e2e_ig_gap.py` con tres escenarios LF y 22/22 controles PASS. Resultado productivo: **NO-GO / UNVERIFIED**. Fuente RAW: `lote29_e2e_runtime.json` SHA-256 `122712edfb41308417ab2a2b3f5e76089e078239e5dd161be0967c6e4e7c0ca8` (artifact `13997605666`).

## Estados de las 36 celdas medidas

| Etapa L26 | A: nueva LF | B: modificada CANDIDATO LF | C: corregida VIGENTE LF | Evidencia / limitación |
|---|---|---|---|---|
| Router | `SINTETICO` | `SINTETICO` | `SINTETICO` | No ACT-0001; solicitud de laboratorio L29 no equivale a Router |
| Perfil | `SINTETICO` | `SINTETICO` | `SINTETICO` | L11B owner profile fixture y HMAC L17; no perfil nativo |
| RUN | `SINTETICO` | `SINTETICO` | `SINTETICO` | EXEC-PARENT-TEST-001 / EXEC-OWNER-L11B-001 fixtures, system_attestation=false |
| IG | `SINTETICO` | `SINTETICO` | `SINTETICO` | L11B stub de Input Governance; sin ticket Edge real |
| Curator | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | L23 Curator SQL ACEPTAR+HMAC, guarda de activación ejecutada |
| Validator | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | L7/L8 captura/cita/binding bajo SQL real de PG18, provenance sintética |
| Retorno perfil | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | L14 profile_return READY verificado por función PG18, no transporte nativo |
| Ejecución | `SINTETICO` | `SINTETICO` | `SINTETICO` | Perfil/Step70 RUN del fixture no completó 11 pasos oficiales |
| Promoción | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | Gate congelado APPLIED + recibo L26 y replay L29 NOOP |
| VIGENTE | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | Fuente y quality registry PG18 VIGENTE; C anterior SUCEDIDA |
| Readback | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | L20 divergence=0, L26 receipts/readback y L29 request count |
| Cierre | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | `REAL_EN_SANDBOX` | L24/L26 closure hash VERIFIED, doble close NOOP y rollback |

## Recuento verificable

| Grupo | Base L26 (LF nueva + LF corregida + SALY nueva) | L29 (tres LF) |
|---|---:|---:|
| REAL_EN_SANDBOX | 21/36 = **58,33%** | **21/36 = 58,33%** |
| SINTETICO | 11/36 | **15/36** |
| NO_PROBADO | 4/36 | **0/36** |
| Total | 36 | 36 |

**Fórmula:** `100 × COUNT(REAL_EN_SANDBOX) / 36 = 100 × 21 / 36 = 58,33%`. **Incremento real de la cobertura medida: 0 puntos porcentuales.** No contar los 22 tests como 22 etapas.

**Precisión importante:** el paso de 4 `NO_PROBADO` a 0 en L29 es consecuencia del **cambio de composición de escenarios**: se sustituyó la trayectoria SALY por una tercera LF para demostrar modificación de candidata. **No significa que se cubrieran Router/Perfil/RUN/IG de SALY**, que permanecen NO_PROBADOS en producción y fuera de este runner. Es engañoso afirmar que se cerraron cuatro brechas de SALY.

## Readbacks adicionales del usuario (no son filas nuevas del tablero original)

| Checkpoint requerido | Evidencia L29 | Realidad limitada |
|---|---|---|
| Solicitud | `l29_submit_request_v1` y `REQUEST_RECEIVED_PG18` | `REAL_EN_SANDBOX` solo del wrapper, no Router |
| Propuesta | CANDIDATO origen, source SHA-256, versión B modificada pre/post | `REAL_EN_SANDBOX` fixture |
| Perfil dueño | OWNER HMAC L17, `l18_owner_intents`, creator≠owner | `REAL_EN_SANDBOX` sólo verificador de prueba, no perfil/identidad productiva |
| Revisión Curator | L23 `ACEPTAR`, sello HMAC y familia fixture | `REAL_EN_SANDBOX`, no motor semántico independiente |
| Ejecución y validación | L11B run fixture + L7/L8 + ticket L23 + L14 | Ejecución `SINTETICO`, validador SQL `REAL_EN_SANDBOX` |
| Promoción/VIGENTE/readback/cierre | Gates PG18, L20 VIGENTE, L24/L26 SHA y NOOP de L29 | `REAL_EN_SANDBOX`; `ROLLBACK` revierte todos los cambios |

**Estado de validación por escenario:** `A_NEW` PASS, `B_MODIFIED_CANDIDATE` PASS (hash de candidato antes≠después, antes de captura), `C_CORRECTED_VIGENTE` PASS (sucesora y anterior SUCEDIDA). Todos sin escritura productiva.

## Qué significa para los 14 bloqueos

El laboratorio acredita funciones SQL sintéticas/aditivas, no la ruta oficial ACT-0001→Perfil→RUN→IG→juez→Step70→cierre. B07 (esquema de lifecycle) sigue pendiente de DDL autorizado; B08 (Supabase Auth/owner real) sigue HMAC fixture; B12 (compatibilidad legacy) no fue ensayada contra esquema migrado; B02/B03 no reconciliaron los RUN reales. **Bloqueos cerrados = 0/14**.

**No cambiar en el dashboard oficial los resultados L21/L26 ni marcar GO.** Este tablero L29 tiene su propia composición de casos, y los % son sólo cobertura de laboratorio.

**Auditor:** GPT-6 (mismo modelo), sin juez independiente; Curator L23 determinista, JWT L17 HMAC test. **NO-GO / UNVERIFIED.**
