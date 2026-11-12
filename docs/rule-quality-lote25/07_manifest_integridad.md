# Lote 25 — Manifiesto de cierre documental con adenda E/F

**Alcance:** PROPUESTAS / NO-GO / UNVERIFIED. **0 reglas VIGENTE modificadas, 0 DML/DDL, 0 RUN cerrados o reintentados, 0 cambios de producción, 0 gates editados**. Se consultó Supabase vivo solo mediante SELECT; la escritura fue exclusivamente GitHub en rama documental.

## Identidad y procedencia

- **Base exacta:** `48f1e316d81c83ca2f880372a3a050b456c6b3ab` (L22).
- **Rama nueva:** `lf/issue-3779-lote25-installment-rules-proposals-v1`.
- **Repositorio:** `cristhianlujan/claude-persona-lf-patch`.
- **Fuente gobernanza:** INPUT GOVERNANCE LF, EKB V1.4, estado CANDIDATO VERIFICADO PARCIALMENTE, SHA-256 de copia leída previamente `234fafb2b06b91e96a979feac138069ec75863aae1bd75aea93c72740c075f79`.
- **Juez/auditor:** GPT-6, **mismo modelo**, sin independencia acreditada y sin identidad Claude verificada.
- **Vivo:** Supabase `mhwmirqcgxxukpctffuv`, solo SELECT con SHA-256 servidor. No hubo PG18 nuevo en L25.

## Resultado medido y límites

| Control | Resultado | Caracterización |
|---|---|---|
| Fichas de reglas | 13 (5 nuevas, 4 cambios, 4 sin cambio) | Documental CANDIDATO o review |
| Parámetros propuestos | 1, `ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES`, inicial 12 MESES_CALENDARIO | Documental CANDIDATO; NO físico |
| Curator read-only G25_02 | 13/13 comparadas con SELECT | OBJETIVO método, sin semántica independiente |
| Códigos de reglas nuevas existentes en vivo | 0/5 | OBJETIVO |
| Duplicados exactos contra VIGENTE | 0/13 bajo igualdad literal de contenido | OBJETIVO acotado |
| Conformidad de familia L13 fixture | 13/13 mapeos coinciden | **NO verifica** owner real desplegado |
| Contradicciones acotadas de gracia/cancelación | 3 reglas VIGENTE, G25_06 | OBJETIVO búsqueda por patrones; revisión semántica necesaria |
| Claves JSONB distintas en mismo ámbito | 4 señales en 3 propuestas, G25_02 | Señales, no contradicciones certificadas |
| Canon de deuda `INCOBRABLE` | Ausente del array `states` de REG_CLIENT_DEBT_SETTLEMENT_STATUS_001 | OBJETIVO específico, no prueba de ausencia en todo sistema |
| Código de parámetro en lf_ops.reglas | 0 referencias G25_07 | OBJETIVO específico |
| Decisiones E/F | EN_PROCESO bloqueada hasta reconciliar, VENCIDA cancelable, auto edad 12m config | Declaración del dueño, **adopción pendiente** |

**Bordes pendientes de revisión:** estado/representación INCOBRABLE y destino contable; rango válido del parámetro; lógica de suma de meses para fechas fin de mes/bisiesto; conciliación y ledger reales Niubiz; owner por familia; política de mora, reintentos y recordatorios expresamente fuera del lote.

## Nueve SELECT y hashes de resultado (SHA-256 servidor de arreglo JSONB completo)

| Probe | Filas | SHA-256 |
|---|---:|---|
| G25_01 | 5 | `e062cf7af6d929a44d5ea5d07e85e8da7fe37905fa24bd559734ae83c490aa68` |
| G25_02 | 13 | `d6bd8de4ad5e4ba404e362acac25158db7e5e92030bcbe95a1a040a18defaa8f` |
| G25_03 | 16 | `f4b5c23c1e0087b398a4439ecfb413f6789d1597d02d94a2a4789b0e2fe8bb06` |
| G25_04 | 5 | `615577b24d8da32f8e8a6118ab859427fda83eaefc42e5b79bbaa266d8a2f48c` |
| G25_05 | 8 | `69562194551fcc4776e191ad35ea533d170869f3314a0cfac1dd0286a705cfb6` |
| G25_06 | 3 | `ccde80ceaafe4aa2568e204e33220fbad2d0cfc76a9f83a6eadae7508d61660f` |
| G25_07 | 1 | `65980d83241ab76857f93f98c6b623508679a44faef41537d1048ff019143a64` |
| G25_08 | 8 | `f338ec8eefbc51b7a4e93eb800f48951327cdb6342f9a413190f55bdb24b0c7f` |
| G25_09 | 0 | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |

Las consultas están completas y son reproducibles en `02_curator_live_readonly.sql`; las filas capturadas en `03_curator_readback.json`. La búsqueda de configuración física G25_07 no acredita que exista una tabla/vía de mantenimiento apta para el parámetro.

## SHA-256 UTF-8 del contenido y readback de blobs Git

| Archivo L25 | SHA-256 | Git blob SHA-1 |
|---|---|---|
| `01_propuestas_reglas.json` | `083081773b299893f611cbd407ba772334edce3962c43cb5e1864fedd5262084` | `d3d1fb7e537e74b17c2d5ba0e993ea7e77e3eac7` |
| `02_curator_live_readonly.sql` | `7ba7dd1f137c7df787bbdafc0b524bb617ad63a35608bfe982ad244a33ab20d4` | `fe63aa07ea3b4a0a981d3ee85e7572735d520841` |
| `03_curator_readback.json` | `610e5aba90dc0e3fd690c7f1ca3b69ff9d25281c0fb93a2ad1699fc570abf4e6` | `2f5654371da45bf274742503cb991a9b3577df87` |
| `04_diffs_literal_pre_post.json` | `b687f3d1c98d46508d78260206a1a3bf24ab11484d668d7358536561f2ae15f2` | `39c1ae3df96f2ee2af6ac364d55e00d8bc1cd9cb` |
| `05_informe_propuestas_y_conflictos.md` | `c6cb63879bf99399315ee7718f51662948ef17a56d94286c745f702d3d9127a1` | `4698d11b4d6acb9ad8e967793b22efc49478e174` |
| `06_parametro_antiguedad_candidato.json` | `e0faefc18ed7f5a0e5a75d32535a1541d3b5d743aee2ea4aa6b55abac965de11` | `e06bb51f25e662fa33ead3c2a9fc5f81342d2f32` |

Los SHA-256 de archivos se calcularon del contenido GitHub UTF-8 y se comprobó el cálculo con vector conocido `SHA256('abc')`. Los hashes SELECT los generó PostgreSQL vivo sobre JSONB completo; no son hashes de un CSV reserializado.

## Gate MD5: no confundir legado con sandbox

- **Vivo, SOLO SELECT G25_04:** `public.lf_rule_promotion_apply_v1` **LEGADA** md5 `d7fe763c999db6f6259b6b1e2bd69644`. También aparecen `apply_batch_v1=4e98f486f5ff65b596e5999f22cc8dde`, `decide_batch_v1=6cdf2aa9a03c6abc7315b7ebc9d2f3ce`, `report_v1=e3e521aaa933604de88d697196f54564`, `guard_v1=ee782e4bd0128c80ee13881899c0d74e`.
- **PG18 L23 anterior, NO ejecutado en este lote:** nuevo gate apply `86b0494984edf95cf0f9c0a0df67000b`, capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, l8 guard `522d12f0843be1da3c785cef3c0bf3fc`. Distinto objeto/entorno respecto al apply legado en vivo.
- **Git compare:** debe acreditar únicamente nuevos documentos bajo `docs/rule-quality-lote25/`; no se emite claim de md5 PG18 calculado en L25.

## Índice del paquete

`01_propuestas_reglas.json` (13 fichas y parámetro); `02_curator_live_readonly.sql` (9 SELECT); `03_curator_readback.json` (filas y SHA); `04_diffs_literal_pre_post.json` (antes/después literal); `05_informe_propuestas_y_conflictos.md` (humano E/F); `06_parametro_antiguedad_candidato.json` (config y pantalla Producto fuera de IG); `07_manifest_integridad.md` (este manifiesto).

**Próximo cambio permitido:** solamente después de aceptación/firmas y una operación gobernada específica. Este dossier no autoriza adopción, migración, alerta operativa real, procesamiento de pagos ni cambio de fuente.

**Readback GitHub final:** confirmar HEAD después de publicar este manifiesto, y verificar archivos, hashes y base. Sin readback no declarar cierre.

**Estado final de producción: NO-GO / UNVERIFIED.**
