# L29 — Manifest SHA-256, fuente y readback del E2E PG18

**Tipo:** PG18 disposable experiment; producción NO-GO / UNVERIFIED. Auditor GPT-6, mismo modelo; no independiente. Curator L23 SQL del mismo modelo; JWT L17 HMAC de prueba, no Supabase Auth.

## Commit y cadena de evidencia

- Base Git exacta del Lote 26: `7ef5472865aaf4f86bf8491c8c7bfa82f7492309`.
- Rama: `lf/issue-3779-lote29-e2e-gap-report-v1`.
- CI positiva [#43336082581](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43336082581), job `131592483828`, commit probado `39b7ebcbf56d76f65b821376e8893650dd0e567b`.
- Resultado runner: **22/22 PASS**, tres escenarios completos, MD5 cuatro gates intactos antes/después, 21/36 etapas REAL_EN_SANDBOX, 15 sintéticas, 0 NO_PROBADO dentro de tres escenarios LF.
- JSON RAW de runner, SHA-256 `122712edfb41308417ab2a2b3f5e76089e078239e5dd161be0967c6e4e7c0ca8` (emitido por runner y verificado por CI).
- Artifact `l29-e2e-pg18-raw`, ID `13997605666`, ZIP SHA-256 `5ec6781482fcd9f5dbf97dea579c15feb9a4a0fde76f027eec748662041959dc`, retención 14 días.
- Las pruebas de las primeras versiones fallaron por evidencia de candidato cambiada después de captura; la versión exitosa sólo modifica un CANDIDATO del fixture antes de la creación de hashes, sin alterar gates. No atribuir PASS a los intentos previos.

## SHA-256 UTF-8 y Git blob SHA-1 de fuentes comprobadas

| Archivo | SHA-256 | SHA-1 Git blob |
|---|---|---|
| `sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/17_l29_e2e_request_sod_retry_pg18.sql` | `b220b04394f5f09d1fc820c8a34f6a2edbde543422468c87172a7713c9ec0e5e` | `63e3803516891b7c34fc1098d5ee750254880f49` |
| `sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_lote29_e2e_ig_gap.py` | `0a2cb9889f1ea602f35600a20d94df2eff1cb9898eeddf0e3ee15a58281984ec` | `e7748f95564d7d2610088e330370d1f55a915e7e` |
| `.github/workflows/l29-ig-e2e-gaps-pg18.yml` | `759b213dbb462f09ae0098245701f8ade1be34d6d4bb3a2897a6080921b94ce1` | `0b3f93284d528262f1d07c674d71c2e4d46dc634` |
| `docs/rule-quality-lote29/00_contrato_alcance_y_flujo.md` | `1be2ac714e70ff7cd6e667dbd4106d16900ffc1a5e97b74f060f92f78f6a757b` | `eda051222062dbf8061a20c92583be06689ef1fa` |
| `docs/rule-quality-lote29/01_matriz_brechas_b09_y_bloqueos.md` | `4bd91afcb6f6973a3ab627e969b57287341be775f1ebc488aeaa214ebd4e7a77` | `8cc752563c732df36c9a6b1dcefa05fae4b343ce` |
| `docs/rule-quality-lote29/02_resultados_e2e_pg18.md` | `338be7b5130fd8a4cf90ba40ee447d5c17b7382efb7a1391534e2c60571e27d1` | `d76ee68ed9d827f3d8eb2b4d7697db997b0300dd` |
| `docs/rule-quality-lote29/03_tablero_12_etapas_medidas.md` | `46c6f2711a20fff5780c7135f95137147867f1bdb010929f1dc4c726539059e4` | `389fc86497b3b6ef9d908be59b11f3551e8458da` |

**Nota de hashes:** los SHA-256 de fuente se calcularon sobre texto UTF-8 leído de GitHub y el cálculo se controló con SHA256('abc'). Git blob SHA-1 es otro algoritmo. La huella del JSON RAW viene directamente de CI y no se ha copiado como archivo oficial Git.

## Cuatro MD5 de PG18 sin mutación

| Función | MD5 antes y después en 3 bases PG18 |
|---|---|
| apply | `86b0494984edf95cf0f9c0a0df67000b` |
| capture_record | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| citation_verify | `773a62783baa5edbe967200cac66b8c3` |
| L8 guard | `522d12f0843be1da3c785cef3c0bf3fc` |

**No son** los MD5 de `lf_rule_promotion_apply_v1` LEGADA en Supabase vivo; se compararon dentro del PG18 independiente como funciones congeladas. No existe ejecución o readback nuevo de Supabase en este lote.

## Control de superficie autorizada

- Únicamente nuevos archivos PG18/sql/runner/workflow y documentos `docs/rule-quality-lote29/` en rama candidata.
- Sin cambios a L7/L8/L11B, L14, L17, L18, L20, L23, L24, L26, gates congelados, main, producción, ni RUN.
- Ningún certificado de actor real, fuente VIGENTE de producción ni reconciliación de 232 RUN; B02, B03, B07, B08, B09 y B12 siguen abiertos, al igual que los otros ocho bloqueos.
- Dossier L25 de decisiones documentales y L27 de elecciones en conversación: ninguno equivale a firma o GO; no se ha otorgado un permiso ni promovido una regla.

## Resultado final controlado

**B09 E2E SQL de laboratorio:** ejecutado y medido; **0/14 bloqueos productivos cerrados**. La prueba no usa Router/Perfil/RUN/IG/Step70/OIDC nativos ni juez independiente.

**Readback final:** se verificará el HEAD y el diff contra `7ef5472865aaf4f86bf8491c8c7bfa82f7492309` después de publicar el manifiesto. El estado final documentado nunca equivale a una firma.

**NO-GO / UNVERIFIED**.
