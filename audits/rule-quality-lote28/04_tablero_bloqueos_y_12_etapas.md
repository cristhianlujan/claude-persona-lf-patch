# Tablero de producción (14 bloqueos) y 12 etapas PG18

## Semáforo de bloqueos
**Cerrados: 0/14 (0%). Pendientes de evidencia y recibo válido: 14/14.** `NO-GO`. No confundir avance del plan documental con cumplimiento del gate de producción.

| Bloqueo | Responsable(s) de evidencia / decisión | Depende de | Gate | Estado |
|---|---|---|---|---|
| B01_MFA | Seguridad, IAM, dueño, Brevo/SMS | B08 | G05 | ABIERTO / NO_VERIFICADO |
| B02_RUN_SCOPE | Dueño, Operaciones | — | G01 | ABIERTO / NO_VERIFICADO |
| B03_RUN_EFFECTS | Operaciones, DBA, custodios | B02 | G02 | ABIERTO / NO_VERIFICADO |
| B04_FAMILY | Dueño LF/SALY, Gobernanza | B06 | G06 | ABIERTO / NO_VERIFICADO |
| B05_RULES | Dueño, Seguridad, Legal/Producto | B04, B01 ref MFA | G07 | ABIERTO / NO_VERIFICADO |
| B06_OWNER | Dueño LF/SALY, IAM | B06-D → B08 → B06-A | G03 | ABIERTO / NO_VERIFICADO |
| B07_SCHEMA | Dueño LF/SALY, Infra/DBA | B04, B08, B12, B14 | G11 | ABIERTO / NO_VERIFICADO |
| B08_IDENTITY | Seguridad/IAM, dueño | contrato B06-D | G04 | ABIERTO / NO_VERIFICADO |
| B09_E2E | IG, Plataforma, Seguridad, dueño | B03, B06, B08, B01 si Login, B07 | G12 | ABIERTO / NO_VERIFICADO |
| B10_BUSINESS | Producto, Finanzas, Operaciones, dueño | B08, B05; B09 antes de operar | G13 | ABIERTO / NO_VERIFICADO |
| B11_LEGAL | Legal, UX, Negocio, dueño | B05 | G14 | ABIERTO / NO_VERIFICADO |
| B12_LEGACY | Arquitectura, Infra/DBA, dueño | B08, B05 | G08 | ABIERTO / NO_VERIFICADO |
| B13_BACKUP | Infra/DBA, Continuidad, dueño | — | G09 | ABIERTO / NO_VERIFICADO |
| B14_RESTORE | Infra/DBA, Continuidad, dueño | B13 | G10 | ABIERTO / NO_VERIFICADO |

### Regla mecánica de actualización (no aplicada en L28)
Un bloqueo cambia de ABIERTO a CERRADO **solo** si existe recibo auténtico firmado por facultados, evidencia RAW y hashes, readback, pruebas negativas, no hay dependencias pendientes y G asociado acreditado. Mantener registro de versión, identidad/sub, as_of y origen. Las plantillas de este lote **no cuentan como recibos**.

## 12 etapas × 3 escenarios — reproducción del L21, no prueba nueva

| Etapa | A LF nueva | B LF corregida | C SALY nueva |
|---|---|---|---|
| 01 Router | SINTETICO | SINTETICO | NO_PROBADO |
| 02 Perfil | SINTETICO | SINTETICO | NO_PROBADO |
| 03 RUN | SINTETICO | SINTETICO | NO_PROBADO |
| 04 IG | SINTETICO | SINTETICO | NO_PROBADO |
| 05 Curator | NO_PROBADO | NO_PROBADO | NO_PROBADO |
| 06 Validator | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| 07 Retorno perfil | REAL_EN_SANDBOX | REAL_EN_SANDBOX | SINTETICO |
| 08 Ejecución | SINTETICO | SINTETICO | REAL_EN_SANDBOX |
| 09 Promoción | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| 10 VIGENTE | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| 11 Readback | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| 12 Cierre | SINTETICO | SINTETICO | SINTETICO |
| **Total 12** | **5 real /6 sint /1 no** | **5 real /6 sint /1 no** | **5 real /2 sint /5 no** |

**Totales:** 15/36 REAL_EN_SANDBOX (41,7%), 14/36 SINTETICO, 7/36 NO_PROBADO. 0/36 celdas E2E de producción acreditadas **en estos lotes**. PG18: 18/18 scripts reportados PASS L20, no independencia ni GO productivo. No extrapolar a todo el producto.

**Fuente verificable:** L21 `03_tablero_12_etapas.md` @ `4c3e376c`, blob `bb3faa6b6412b5c540ff0670fb0de0166809e9a6`. Recalcular solo si se aporta nueva evidencia y se registra comparación; no reemplazar estados históricos silenciosamente.

