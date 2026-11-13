# L29 — Manifiesto de integridad de la REVISIÓN REAL del Login B2B

**Resultado actual:** revisión real fuente 49/49 en PG18: SHA origen igual, 53 evaluaciones, 4 DEVOLVER, 23 aceptaciones preliminares, 26 escaladas, 2 códigos ausentes. **Cero firmas, cero reglas aprobadas, cero promociones, cero escrituras de producción/RUN.**

## Ruta de ejecución y autoridad

- **EKB**: INPUT GOVERNANCE LF V1.4, CANDIDATO VERIFICADO PARCIALMENTE. Arquitectura objetivo ACT-0001→PERFIL→RUN→pasos→IG→validador→juez→registro→cierre; esta ejecución no usó esa ruta nativa.
- Base Git L26: `7ef5472865aaf4f86bf8491c8c7bfa82f7492309`; branch de trabajo `lf/issue-3779-lote29-e2e-gap-report-v1`.
- **CI vigente:** [#43340333844](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43340333844), job `131606765364`, commit probado `7ba1d3b38bd63b0e69ac96a1fd90bf2ebc6befb1`, `SUCCESS` en PG18.
- **SHA-256 real de SELECT de 49 reglas:** `4959cfd6d9319ea26b60f9a21a1751c674e06c4417fb4d589f3665424d539bd3`; comprobado idéntico dentro de PG18.
- **SHA-256 JSON RAW CI último:** `a898a38cb6f8cedaf1271e7390df7517ef8bd3cfce63c60997ae097edd05b08f`, artifact `13998749112`, ZIP sha256 `c82bdb62c7b270ade62a9082413bc68f84fb243d67502259351dbdb845502cac`, retención 14 días.
- **Revisión por código:** `08_login_b2b_vueltas_curator_51.json` es reconstrucción determinista de las salidas del Curator SQL, cotejada con agregados CI; no es el RAW del artifact. El RAW contiene todos los resultados y 588 celdas individuales.
- **Autor/Curator:** GPT-6, mismo modelo, mini-Curator SQL determinista; independencia NO ACREDITADA. Auth/JWT productivos no probados; HMAC anterior del L29 no forma parte de esta nueva ejecución.

## SHA-256 contenido UTF-8 y Git blob SHA-1 verificados

| Archivo | SHA-256 | Git blob SHA-1 |
|---|---|---|
| `.github/workflows/l29-ig-e2e-gaps-pg18.yml` | `91e8bb3b393927b9fc37d56d23a8b5aafa8b50473620bb380d85b5f6c4ce890f` | `bc281b27bdb7c43c7ef6d883ebdae174f1814c9f` |
| `docs/rule-quality-lote29/00_contrato_alcance_y_flujo.md` | `0e1d4926e59e100653f923df2f3480959edf1bc8ac628377009198221adc1141` | `81d1a4787ae572964ed8933aefeacd47941c1a19` |
| `docs/rule-quality-lote29/01_matriz_brechas_b09_y_bloqueos.md` | `4c17a230684bcf0681e71ea873113a93e5b0ac8e6123d13ef197fe74be0e4ff8` | `3fcbe658d5c7894a3c609800811ca9f77a395fa7` |
| `docs/rule-quality-lote29/02_resultados_e2e_pg18.md` | `896dd1b615f43f102280d6c20a3db15d8ab5e95747f5b312baf26c320dff751c` | `ef1c10e99cb6254111ddf3515ca6956abc3c28e1` |
| `docs/rule-quality-lote29/03_tablero_12_etapas_medidas.md` | `74fcc22fb51eb1b8b66629f62a86c7ac37ad014555cfa8f193dc687c319379c0` | `a624788bdee63f55ff6315385d1aca917a724a9e` |
| `docs/rule-quality-lote29/05_login_b2b_reglas_origen_49.json` | `d41e843c32f4f2518da8c5cf1669a4d2f95a01e19382b8bb54dcaef3654587f2` | `b64400f7c33db22f5002df50d4b372ca47e2086b` |
| `docs/rule-quality-lote29/06_politicas_centrales_mfa_origen.json` | `152969f84a0ccadc27e3d7d260264c26b5e6ae8ed033cb5a689a1a12bd4edbd0` | `70890face3dfe2e2be12dd656e8fb6ea3875177f` |
| `docs/rule-quality-lote29/07_login_b2b_matriz_diffs_51.json` | `d9bd7cce16d0cbc72b3d0f823c7de106f1a4211861979329feb06b47c7c5d303` | `948cac85748125ad9be1c72a65307df3d62146ab` |
| `docs/rule-quality-lote29/08_login_b2b_vueltas_curator_51.json` | `977015f24456a0835fa8a6cdf37116afa3cbf1b3947680dda694c1b3e4056a18` | `a390030f2f1661f6bec34e44b82e7154ae526acc` |
| `docs/rule-quality-lote29/09_matriz_humana_51.md` | `13f0ac49390f5f62a7e078366174de48d7f6e5b350b47a7744a9c4a1bad7de9d` | `d7751395e37c538f7a88353b6113123caff493e2` |
| `sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_lote29_actual_login_b2b_49.py` | `69c18f06b12b60f9a48302bced1fc82e2b3f5b092b84d1b8b7ccda1d238f7453` | `1bf40f5c84d315ed6cb6d7ea381f048710fb0428` |
| `sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_lote29_e2e_ig_gap.py` | `0a2cb9889f1ea602f35600a20d94df2eff1cb9898eeddf0e3ee15a58281984ec` | `e7748f95564d7d2610088e330370d1f55a915e7e` |
| `sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/17_l29_e2e_request_sod_retry_pg18.sql` | `b220b04394f5f09d1fc820c8a34f6a2edbde543422468c87172a7713c9ec0e5e` | `63e3803516891b7c34fc1098d5ee750254880f49` |

La suma SHA-256 se hizo sobre texto UTF-8 leído de GitHub, comprobando el algoritmo con `SHA256('abc')`. El hash JSON de SQL proviene de PostgreSQL y no se calcula como suma de una reserialización arbitraria.

## Gates y scope de código

- **MD5 históricos PG18 comprobados en el L29 anterior:** apply `86b0494984edf95cf0f9c0a0df67000b`; capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`; citation_verify `773a62783baa5edbe967200cac66b8c3`; L8 guard `522d12f0843be1da3c785cef3c0bf3fc`.
- **Este ajuste no reejecutó esos gates**; no afirmar md5 reevaluados. Git compare desde L26 debe confirmar que sólo se añaden archivos L29; ningún gate/Router/RUN/B07/B12 fue editado.
- Se conservan por trazabilidad dos archivos de la prueba anterior de fixtures: `sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_lote29_e2e_ig_gap.py`, `sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/17_l29_e2e_request_sod_retry_pg18.sql`. **No los ejecuta la CI actual**.
- Modelo de ejecución: lectura Supabase con SELECT, copias/fuentes PG18 inmutables, propuestas en drafts, comparador determinista, sin permiso de promoción ni configuración real de políticas.

## Aprobación y resultado final

- Las decisiones MFA OTP Brevo, SMS contingencia sin proveedor, disparadores 30d/3m y recuperación Q11 están `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. Otros disparadores MFA y proveedor SMS sin decisión; no se inventan.
- Los cambios de `AUTH-018/019/020/033` se aplicaron sólo a drafts; cuatro políticas 3/19/20/25 sólo en PG18 drafts. Nueve reglas VIGENTE de fuente no se alteran.
- Cuadro medido: 147/588 `REAL_EN_SANDBOX`, 53/588 `SINTETICO`, 388/588 `NO_PROBADO`. **No comparable** con 21/36 del ensayo anterior.
- **0/14 bloqueos productivos cerrados; B02/B03/B07/B08/B09/B12 siguen abiertos.** No hay firma formal, Go/No-Go sigue NO-GO/UNVERIFIED.

**Readback final tras commit:** confirmar HEAD y 14 archivos nuevos limitados a branch L29, más igualdad de hashes. No inferir SHA del propio manifiesto en su interior.
