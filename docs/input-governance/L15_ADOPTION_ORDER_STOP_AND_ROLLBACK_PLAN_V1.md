# LF — Lote 15 · Plan de adopción y reversión · DRAFT / NO-GO

**Alcance**: preparación y verificación exclusiva en PG18 limpio. **NO EJECUTAR en Supabase vivo ni producción.** Base L15: HEAD verificado 11C `5f768b56964f8566195500a08c833f422678b023`; L13 de rama aislada fuente fijada por SHA; L14 en paralelo **FUERA DE ALCANCE**. Las fuentes de gobernanza se examinaron antes de actuar (EKB V1.4).

## 1. Inventario migraciones y dependencias

Fuente verificable exhaustiva: `sandbox/lf_contract_gate_test/lote15_adoption_rollback_v1/01_inventory.json`. Seis archivos de migración más un modelo de L13 **exclusivo sandbox**, no siete migraciones oficiales.

| Etapa | Fuente | Depende de | Toca y control post | Parada obligatoria |
|---|---|---|---|---|
| A01 (prerrequisito L3) | `20261111182000_...deterministic_judge_governed_v1.sql` | Siete funciones heredadas, tabla `lf_rule_promotion_v1`, perfil RUN/IG | Reemplaza `request_v1/decide_v1/apply_v1`; crea 2 funciones, 3 columnas; mantener `guard_v1` | Algún MD5 de las 7 funciones no coincide con baseline aprobado |
| A02 (L4B) | `20261111191000_...native_semantic_review_gate_v1.sql` | A01 y API #3682 de IG | Añade 13 columnas de IG y un índice único; crea 3 funciones, reemplaza 2; verificar recibo/packet y no autoridad automática | Fuente de recibo o API IG no autenticada/contrato distinto |
| A03 (L4D) | `20261111212500_...profile_owner_authority_v1.sql` | A02, propiedad canónica aprobada | Crea `lf_rule_promotion_profile_owner_v1` y 2 funciones; añade columnas de autoridad; owner no es IG ni SUPER_ADMIN | Falta dueño real o permisos efectivos |
| A04 (L5) | `20261111224500_...real_verdict_profile_return_v1.sql` | A03 | Crea `blind_verdict_verify/pin`, `rule_readback`, `profile_return_readback`; añade columnas de readback/retorno | No hay Step70/recibo coherentes o retorno READY |
| A05 (L7) | `20261111235500_...exact_citation_capture_v1.sql` | A04, hashes vigentes, bridge oficial | 2 roles NOLOGIN, 2 tablas de citas inmutables, triggers anti DML, 5 funciones nuevas; refuerza `apply`, IG y veredicto | Emisor de procedencia y OIDC no acreditados |
| A06 (L8) | `20261112004000_...citation_reuse_scoped_v2.sql` | A05 exacto y MD5 guard | Elimina UNIQUE global, crea índice único PROPOSAL + trigger de ámbito; 1 función nueva | Citas entre reglas o propuestas indebidamente reutilizadas |
| A07 (L13 SOLO PG18) | `pinned_l13/01_schema.sql` + seed/tests 02–04 | Independiente del motor de promoción; depende de L12 analítico | Esquema aislado `rule_quality_l13`; 28 pruebas del ciclo familiar | **NO migrar a Supabase** sin diseño y aprobación nuevos |

L6, L9, L10, L11, L12 no tienen migraciones de este paquete: representan fixtures, Evals y auditorías. L13 es un diseño de sandbox, no una migración de producción. Los seis SQL oficiales contienen sus propios `BEGIN; COMMIT;`, por lo que el ensayo de reversión usa el **mismo DDL** pero administra fuera las envolturas transaccionales para permitir `SAVEPOINT`.

## 2. Compatibilidad con las 7 funciones ya existentes (solo lectura al catálogo vivo)

| Función antigua | MD5 observado (prefijo) | Comportamiento candidato |
|---|---|---|
| `lf_rule_promotion_request_v1(text,text,text)` | `2fcac9f1` | **REPLACE**, A01 |
| `lf_rule_promotion_decide_v1(text,text,text,text)` | `16e45f40` | **REPLACE**, A01 |
| `lf_rule_promotion_apply_v1(text)` | `d7fe763c` | **REPLACE** progresivo, A01–A05; final esperado `86b04949` |
| `lf_rule_promotion_guard_v1()` | `ee782e4b` | **COEXIST**, NO reemplazar |
| `lf_rule_promotion_apply_batch_v1(text[])` | `4e98f486` | **COEXIST** pero llama al `apply_v1` reemplazado |
| `lf_rule_promotion_decide_batch_v1(text[],text,text,text)` | `6cdf2aa9` | **COEXIST** pero llama al `decide_v1` reemplazado |
| `lf_rule_promotion_report_v1(integer,integer)` | `e3e521aa` | **COEXIST**, depende de estados/semántica heredados |

**Riesgo**: compatibilidad de interfaces batch/consulta no acreditada en producción; incluso si el MD5 no cambia, el resultado funcional sí puede variar por la función llamada. Supabase vivo: tabla `public.lf_rule_promotion_v1` con 11 columnas; ninguna de las dos tablas nuevas de citas estaba presente al readback de este lote. Estado de las promociones leídas: sin filas agrupadas por estado. El sandbox usa **4 definiciones antiguas exactas con sus MD5 vivos** y **3 stubs identificados** para simular las otras firmas; no afirmar una restauración exacta de código vivo para esos tres.

## 3. Reversión por etapa (alcance real probado)

Script reproducible: `sandbox/lf_contract_gate_test/lote15_adoption_rollback_v1/test_pg18_lote15_adoption_rollback.py`.

Para cada etapa A01–A07:
`PG18 limpio → baseline/anteriores → hash catálogo BEFORE → SAVEPOINT → aplicar etapa → verificar objetos → ROLLBACK TO SAVEPOINT → hash catálogo AFTER → assert BEFORE=AFTER → ROLLBACK exterior → assert ROOT=BASELINE`.

El hash del catálogo se divide en **schemas, functions, tables, columns, constraints, indexes, triggers, roles y grants**: incluye OIDs, definiciones de funciones, columnas, roles/LOGIN y ACL. La segunda prueba aplica A01–A07 completa en **una sola transacción**, verifica y revierte, exigiendo el mismo catálogo inicial. El test aborta ante cualquier divergencia.

**Limitación inequívoca:** esto prueba **reversión ANTES de commit**, no un downgrade después de aplicar y confirmar la migración. PostgreSQL conserva atributos físicos `attisdropped` al eliminar columnas después de commit, así que un `DROP COLUMN` inverso no produce un `pg_catalog` idéntico. Tampoco se debe `DROP TABLE CASCADE` sin análisis de consumidores. **Un undo post-commit idéntico exige backup físico/PITR** y restauración en una instancia independiente, con comparación y aprobación del dueño; esa prueba aún no se ha ejecutado. `BLOQUEA_PRODUCCION`.

## 4. Precondiciones NO automatizables — todas BLOQUEA_PRODUCCION

| Control | Evidencia indispensable y quién la aporta |
|---|---|
| Identidad real del autor/emisor del Step70 | Dueño acredita OIDC y bridge ligado a RUN, NOLOGIN sin login y sin service_role en Router |
| Procedencia de citas / IG | Recibo #3682 nativo, hashes de fuente y proceso, no confiar en el literal `OFFICIAL_STEP70_VERIFIED_NATIVE_IG` aportado por una fila editable |
| Dueños y cadencia de revisión | Dueño define perfil por familia/proyecto e intervalos (L13 usa 90 LF/60 SALY **solo como datos sintéticos**, no como política vigente) |
| 32 RUNs atascados | Dueño decide reconciliación, reintento y cierre con recibos; cifra declarada por el dueño, no inventar lista ni cerrar RUNs |
| PASE global rojo | CI de todas las PR y pruebas especializadas deben estar verdes; ningún `success` aislado sustitute PASE |
| Compatibilidad legada | Dueño/gerencia valida batch apply/decide, report, ACL, dependencias y consumidores con snapshot/contract |
| Backup + restore | Operador autorizado entrega backup físico + WAL/PITR, prueba de recuperación en clon y hashes de catálogo |
| Aprobación de fuentes oficiales | Dueño aprueba explícitamente cualquier futura edición o adopción real; L14 queda excluido |

## 5. SIMULACIÓN DE VENTANA (PLAN, NO EJECUTADO)

**Previo (T−48h a T−1h)**: asignar responsables, congelar cambios de esquema de promoción, verificar PR base sin 66 archivos acoplados, acordar RTO/RPO, medir carga/consumidores y compatibilidad; respaldo físico consistente + WAL y prueba PITR de restauración en clon. Generar manifiesto firmado: SHA de seis migraciones, catálogo `pg_catalog`, grants/roles, políticas, estado de RUN y lectura EKB. Detener si PASE/autoridad/backup no acreditados.

**Ventana candidata**: D1 A01 → readback de tres funciones reemplazadas y guard → GO parcial firmado; D2 A02 → validar integración #3682; D3 A03 → autoridad del propietario; D4 A04 → veredicto/retorno; D5 A05 → OIDC NOLOGIN y fuentes inmutables; D6 A06 → unicidad por origen. Cada etapa dentro de transacción única: **postcheck ANTES de COMMIT**; ante anomalía `ROLLBACK` y parada total. **A07 nunca forma parte de la ventana productiva**.

**Postventana simulada**: reconciliar función/snapshot/grants/roles y RBAC, medir latencia/errores, validar flujos existentes de los 7 servicios, observar readback del RUN y cierre nativo; vigilancia y soporte disponibles. Si una etapa ya hizo COMMIT y falla: **NO ejecutar DROP CASCADE como reparación**; congelar, aislar el incidente y evaluar restauración PITR a clon; decidir reversión real con dueño.

**GO/NO-GO que firmaría el dueño**: `GO` únicamente con 100% precondiciones acreditadas, 0 efectos en Router/L14, catálogo y funciones esperadas, autoridad propietaria autenticada, CI global y PASE verde, backup/PITR probado, CIs PG18 reproducidos y protocolo de parada aprobado. Cualquier faltante → **NO-GO**. Firma requerida: `[Dueño / fecha UTC−5 / commit / manifiesto SHA / decisión / observaciones]`. **No existe firma ni ventana aprobada hoy.**

## 6. Evidencia / cierre

- Fuente y diff: migraciones originales **sin modificar** en `supabase/migrations/`; L13 copiado/fijado exclusivamente en `sandbox/lf_contract_gate_test/lote15_adoption_rollback_v1/pinned_l13/`.
- RAW PG18: `l15_pg18_raw.log` y `l15_adoption_rollback_runtime.json` desde la acción `l15-rule-adoption-rollback-pg18.yml`.
- **NO-GO** hasta readback completo de tests + respaldo/autoridad/compatibilidad y firma del dueño; PASE rojo y L14 paralelo no se modifican.
