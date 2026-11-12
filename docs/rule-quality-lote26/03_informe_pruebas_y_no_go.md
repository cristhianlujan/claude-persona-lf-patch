# Lote 26 — Auditoría del ciclo completo PG18 y límites

## Dictamen

**SANDBOX_VERIFIED** en PostgreSQL 18 aislado: tres secuencias completas medidas desde **Curator → promoción → readback → sincronización → recibo de promoción → cierre verificado**. El cierre, modelo, autoridad y receptor productivos permanecen **NO-GO / UNVERIFIED**.

**No se implementa producto/ledger; no se cambia Router ni gates.** Integración nueva, no modificación de SQL de L23/L24.

## 1. Resultado de CI reproducido

GitHub Actions [#43328149868](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43328149868) — job `131565766208` — commit probado `a16bf36dcb8032f077eb5dd9be7a2a4164956fd2` — conclusión `success`.

| Bloque | Resultados reales |
|---|---:|
| L13 calidad/lifecycle | 28/28 PASS |
| L14 wrapper de promoción | 18/18 PASS |
| L17 JWT/HMAC de laboratorio | 25/25 PASS |
| L18 escenarios previos | 16/16 PASS |
| L20 sincronización | 17/17 PASS |
| L23 Curator aislado | 17/17 PASS |
| L24 recibo aislado | 23/23 PASS |
| **L26 integrado en una transacción por escenario** | **36/36 PASS** |
| **Scripts `test_pg18_*.py` totales** | **21/21 PASS** |

Estos conteos **se solapan** y no son pruebas independientes sumables. Algunas pruebas de L4 solo miden defectos semánticos y un PASS del script no significa sensibilidad adecuada de un juez nativo.

**SHA-256 del JSON RAW del runner L26:** `a03177a4a4711de4fb2e4d62387b5ea0f823fb925cfc87b5d4bf352b83e34135`.

## 2. Ruta observada con controles efectivos

```text
HMAC owner L17 / L13 fuente y familia [sandbox]
  → L23 Curator ACEPTAR, fingerprint, sello HMAC
  → L23 trigger de ticket exige ese sello y huella fresca
  → L14 apply con gate LF congelado / adaptador SALY sintético
  → L14 READY + L20 VIGENTE en registro y fuente, divergencia = 0
  → B: L20 sincroniza predecesora SUCEDIDA en ambas fuentes
  → L26 guarda comprobante append-only de promoción (SHA + Curator)
  → L26 exige ese comprobante y revalida sello + readback
  → L24 guarda recibo append-only y verifica sus tres hashes
  → ROLLBACK; el estado de todos los componentes vuelve a cero
```

El flujo A se mide como **regla nueva sin conflicto** porque su banco PG18 fue inicializado con una categoría distinta para una fuente VIGENTE no relacionada **antes de instalar L17**. La candidata `REG_SEG_004` conserva sus datos del gate congelado. B/C utilizan otro PG18 limpio con el contexto original. **No se desactivó ningún trigger** para lograr ACEPTAR. Este procedimiento es específico de fixture, no de producción.

La función privada `l26_measured_readback_v1` se ejecuta dentro de la sesión HMAC/owner y entrega solamente el readback necesario; no se concedieron SELECT directos a tablas de evidencia a roles de aplicación.

## 3. Negativas de integración, observadas

| ID | Resultado | Contrato probado |
|---|---|---|
| `N1_PROMOTION_WITHOUT_CURATOR_BLOCKED` | PASS | BLOCK_L23_CURATOR_NOT_ACCEPTED |
| `N2_CLOSURE_WITHOUT_PROMOTION_RECEIPT` | PASS | BLOCK_L26_PROMOTION_RECEIPT_REQUIRED |
| `N3_TAMPERED_CURATOR_BLOCKS_CLOSURE` | PASS | BLOCK_L26_CURATOR_SEAL_TAMPERED |
| `N4_DIVERGENCE_BLOCKS_INTEGRATED_CLOSE` | PASS | BLOCK_L24_DIVERGENCE_REGISTER_SOURCE |
| `N5_ACCEPT_REPLAY_ANOTHER_RULE_BLOCKED` | PASS | BLOCK_L23_CURATOR_SEAL_INVALID |
| `N6_MID_SEQUENCE_ROLLBACK_TRIGGERED` | PASS | L26_INJECTED_AFTER_PROMOTION_BEFORE_CLOSURE |
| `N6B_ROLLBACK_TOTAL_READBACK` | PASS | injected fault after frozen promotion and L26 promotion receipt leaves zero persisted source, verdict, receipts |

La prueba de fallo entre promoción y cierre termina en error SQL y un SELECT posterior comprobó `candidate=0`, `quality=0`, `curator=0`, `promotion=0`, `closure=0` y `owner_intents=0`. **No quedó recibo parcial ni promoción persistida.**

La prueba de reutilización de ACEPTAR creó otro candidato en fixture PG18 y reprodujo su sello HMAC de la regla original: el trigger L23 rechazó la nueva promoción antes de aplicar.

## 4. Privilegios PostgreSQL observados (no inferidos)

Se intentaron **INSERT, UPDATE, DELETE, TRUNCATE y ALTER TABLE DISABLE TRIGGER** contra las tres tablas `l23_curator_verdicts`, `l26_promotion_receipts` y `l24_closure_receipts`, desde siete roles, con `SET SESSION AUTHORIZATION` de fixture como rol de aplicación.

| Rol | Tablas revisadas | Operaciones denegadas | Resultado |
|---|---:|---:|---|
| `lf_owner_role` | 3 | 15/15 | PASS |
| `lf_super_role` | 3 | 15/15 | PASS |
| `lf_reader_role` | 3 | 15/15 | PASS |
| `lf_no_grant_role` | 3 | 15/15 | PASS |
| `saly_owner_role` | 3 | 15/15 | PASS |
| `saly_super_role` | 3 | 15/15 | PASS |
| `l17_authenticator` | 3 | 15/15 | PASS |

**Total: 105/105 denegaciones reales**. No se incluyeron usuarios de producción, no se habilitaron grants de DML ni se manipularon roles reales. No se confunde la prueba de permiso con la autenticación Supabase Auth.

## 5. MD5 exactos congelados

| Gate PG18 | MD5 antes = después |
|---|---|
| apply | `86b0494984edf95cf0f9c0a0df67000b` |
| capture_record | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| citation_verify | `773a62783baa5edbe967200cac66b8c3` |
| l8 guard | `522d12f0843be1da3c785cef3c0bf3fc` |

**Integridad:** `gate_md5_before` = `gate_md5_after` en cada runner; L26 no modifica SQL de gates. Los SQL originales L23 y L24 mantienen identidad de Git blobs con sus respectivos commits de origen. Este dato está separado del MD5 de una función del Supabase vivo, que no se ha pretendido equiparar a PG18.

## 6. Definición precisa del tablero y sus límites

Ver `02_tablero_12_etapas_medido.md`. Resultado RAW: `REAL_EN_SANDBOX=21`, `SINTETICO=11`, `NO_PROBADO=4`, total 36. **Porcentaje mecánico medido = 21/36 × 100 = 58,33%**. No suma de tableros anteriores, ni indicador de cumplimiento productivo.

La etiqueta `REAL_EN_SANDBOX` solo acredita ejecución PG18: el Curator L23 es SQL determinista escrito por el mismo GPT-6, el juez no es independiente, el JWT L17 es una firma HMAC sintética, el Step70 y dueño son fixtures y SALY usa un adaptador `apply` sintético.

## 7. Supabase vivo, recepción oficial y no-go

SELECT exclusivamente con `supabase_read_only_user`: `public.lf_profile_execution_terminal_authority_receipt_v1(text)` está catalogada y hay 578 reglas en `lf_ops.reglas`. **No se invocó** el recibo terminal ni se escribió en Supabase. La presencia en catálogo no demuestra que un RUN real haya cerrado.

Pendiente para afirmar cierre oficial:

- Autenticación real Supabase Auth/OIDC y vinculación del actor/owner al RUN.
- Ruta ACT-0001 → Perfil → RUN nativo con 11/11 pasos válidos; no reemplazarla por el bridge experimental.
- Curator real y juez semántico independiente, con evidencia y firma.
- Recibo de promoción/registro y cierre emitidos por los escritores oficiales autorizados.
- Recepción y readback terminal del mismo RUN mediante `lf_profile_execution_terminal_authority_receipt_v1(text)`.

**Ninguna tabla ni función L26 se despliega en producción. No existe autorización para hacerlo.** Ejecutor GPT-6; no se acredita un auditor Claude independiente. **NO-GO / UNVERIFIED** en producto/producción.

Fuente detallada: `01_resultados_reales_pg18.json`, contiene todas las 36 filas PASS y hashes SHA de los 21 scripts.
