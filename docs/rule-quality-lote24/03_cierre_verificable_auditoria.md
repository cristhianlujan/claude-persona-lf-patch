# LOTE 24 — Recibo verificable de cierre · PG18 sandbox

**Estado de ejecución:** `SANDBOX_VERIFIED`, **producción:** `NO-GO/UNVERIFIED`. Solo gobernanza de reglas, sin ledger/producto, sin escrituras en Supabase vivo.

**Base exacta:** `48f1e316d81c83ca2f880372a3a050b456c6b3ab`. Rama `lf/issue-3779-lote24-closure-receipt-v1`. Commit que pasó CI: `cd8f7d4fc1cd1340edcdf82772a88d258e8f51b6`.

## 1. Flujo realmente probado

```text
L11B sintético: Router/Perfil/RUN/Step70 (no nativos)
 → LF: L7 captura cita, L8, IG prueba y owner/permiso sintéticos
 → SALY: adaptación sintética del producto (no gates LF)
 → L17: authenticator + SET LOCAL ROLE + HMAC JWT firmado de prueba
 → L13: familia y preparación
 → L14: promoción wrapper; LF apply congelado / SALY apply de laboratorio
 → L20: fuente VIGENTE == registro L13 VIGENTE, divergencias de regla = 0
 → L24: verificar aprobación L18 + ticket CONSUMED + READBACK READY
       ├─ propuesta: hash SHA256 de snapshot L13 + promoción/owner
       ├─ readback: SHA256 de respuesta SQL y bindings reales del gate LF
       ├─ versión: sha256:<hash propuesta> (NO versión semántica canónica)
       ├─ owner: JWT/HMAC firmado + evidencia de aprobación del perfil
       ├─ juez: mismo modelo/veredicto anterior, SIN independencia
       └─ recibo append-only: hash propio SHA256 + timestamp + actor
 → L24 verificador lee recibo y recalcula 3 hashes
 → VERIFIED_CLOSURE_HASH (solo PG18)
```

**No existe receptor oficial conectado a este recibo L24**. Supabase vivo, consultado exclusivamente por SELECT con `supabase_read_only_user`, expone `public.lf_profile_execution_terminal_authority_receipt_v1(text)`, pero **no se invocó**. El recibo SHA es una cadena comprobada internamente por SQL, no un acuse de recepción del perfil ni una atestación externa.

## 2. Recibo emitido

La tabla `rule_quality_l13.l24_closure_receipts` queda exclusivamente dentro del sandbox de PG18. Contiene:

`receipt_id`, `project_code`, `rule_code`, `promotion_id`, `owner_run`, `version`, `final_state`, `proposal_payload`, `proposal_sha256`, `readback_payload`, `readback_sha256`, `owner_approval`, `judge_evidence`, `actor_code`, `actor_sub`, `closed_at`, `receipt_sha256`, procedencia y `native_receiver_attested=false`.

La identidad y los hashes son resueltos por el servidor: **el invocador no aporta hash, estado READY ni identidad de actor**. El emisor exige coincidencia `VIGENTE` entre L13 y fuente, ticket consumido, **detector L20=0** y readback LF del gate congelado en `READY` con tres vinculaciones SHA-256.

La consulta de verificación `l24_verify_closure_v1` recalcula los hashes de propuesta/readback y del cuerpo del recibo almacenado; detecta cambios no autorizados incluso cuando se elude deliberadamente el trigger bajo superusuario de prueba.

**Versionado limitado:** `version=sha256:<proposal_sha256>` es identificador de contenido, **no** revisión oficial de la propuesta. `proposal_sha256` deriva del snapshot L13 conservado durante la operación, no de una firma de propuesta externa. La evidencia posterior a `APPLIED` se valida contra vínculos SHA del frozen `profile_return READY`; las APIs que verificaban la intención antes de aplicar pueden cambiar de estado después. Su resultado posterior se guarda solo para auditoría, sin tratarlo como una nueva aprobación.

**Append-only:** trigger que rechaza UPDATE/DELETE; RLS `FORCE`; REVOKE de DML para roles de aplicación. `SECURITY DEFINER` del fixture opera con superusuario PG18: **no es patrón autorizado para producción**.

## 3. Resultados de los escenarios

| Escenario | Regla que recibe cierre | Estado L13/fuente | Resultado del verificador |
|---|---|---|---|
| A: LF nueva | `REG_SEG_004` | VIGENTE/VIGENTE | `VERIFIED_CLOSURE_HASH` |
| B: LF corregida | `REG_SEG_004` (sucesora) | VIGENTE/VIGENTE; anterior SUCEDIDA en ambas | `VERIFIED_CLOSURE_HASH` |
| C: SALY nueva | `SALY-L14-NEW` | VIGENTE/vigente=true sintético | `VERIFIED_CLOSURE_HASH` |

Hash de recibo registrado en cada corrida:

- A: `59e42279d6e06ba5fb1cefb9872b3032a39ae05566fd22179365335e999acfe6`.
- B: `6598b97fa8ae2bccf17d1fa74313ca831ba2361cdd365dda2096f7f2ab26b3f8`.
- C: `cabc310e0944530c44570ce8b31c56a40d7fd1b735e10adf5ae6d8c772d15ccc`.

La fecha y los hashes específicos son **dependientes de la ejecución**. Los escenarios positivos se probaron en transacciones revertidas; el runner conserva un recibo adicional solo dentro de PG18 efímero para ensayar permisos, tamper e idempotencia.

## 4. Tablero de 12 etapas, sin inflar

La etiqueta `REAL_EN_SANDBOX` significa **SQL/fixture realmente ejecutado en PG18**, no ejecución nativa. En particular, `Cierre` pasa del `SINTETICO` de L18 a un nuevo **recibo PG18 realmente emitido y verificado**, pero **cierre oficial sigue NO_PROBADO**.

| Etapa | LF nueva | LF corregida | SALY nueva |
|---|---|---|---|
| Router | SINTETICO | SINTETICO | NO_PROBADO |
| Perfil | SINTETICO | SINTETICO | NO_PROBADO |
| RUN | SINTETICO | SINTETICO | NO_PROBADO |
| IG | SINTETICO | SINTETICO | NO_PROBADO |
| Curator | NO_PROBADO | NO_PROBADO | NO_PROBADO |
| Validator | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| Retorno perfil | REAL_EN_SANDBOX | REAL_EN_SANDBOX | SINTETICO |
| Ejecucion | SINTETICO | SINTETICO | REAL_EN_SANDBOX |
| Promocion | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| VIGENTE | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| Readback | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |
| Cierre | REAL_EN_SANDBOX | REAL_EN_SANDBOX | REAL_EN_SANDBOX |

**Sin acreditación nativa:** Router ACT-0001, Perfil, RUN principal completo con once pasos, Step70 real, juez independiente, Curator y receptor oficial de cierre. Retorno LF = función SQL readback real sobre upstream sintético; Retorno SALY = fixture READY, no transporte real.

## 5. Pruebas adversariales

| Control | Evidencia | Bloqueo / expectativa |
|---|---|---|
| `N1_NO_READBACK_READY` | **PASS** | BLOCK_L24_READBACK_NOT_READY |
| `N2_L13_SOURCE_DIVERGENCE` | **PASS** | BLOCK_L24_DIVERGENCE_REGISTER_SOURCE |
| `NEGATIVE_FIXTURE_PERSISTED_PG18` | **PASS** | 1 real PG18 closure receipt for attack tests, never live |
| `N3_BAD_JWT_SIGNATURE` | **PASS** | BLOCK_L17_JWT_SIGNATURE_INVALID |
| `N3B_MISSING_JWT` | **PASS** | 42501 no signed request.jwt.claims |
| `N4_SUPER_ADMIN_CANNOT_CLOSE` | **PASS** | L17 forbids signed SUPER_ADMIN closure |
| `N5_APP_ROLE_DIRECT_DML_DENIED` | **PASS** | app actor has no UPDATE permission on receipt |
| `N6_APPEND_ONLY_UPDATE` | **PASS** | BLOCK_L24_APPEND_ONLY_RECEIPT |
| `N6_APPEND_ONLY_DELETE` | **PASS** | BLOCK_L24_APPEND_ONLY_RECEIPT |
| `N7_IDEMPOTENT_DUPLICATE_NOOP` | **PASS** | no duplicate receipt and identical receipt id |
| `N8_HASH_TAMPER_DETECTED` | **PASS** | BLOCK_L24_HASH_OR_RECEIPT_TAMPER |
| `N8B_TAMPER_ROLLBACK_RESTORES` | **PASS** | original persisted receipt remains valid after forensic test rolled back |
| `N9_FAIL_MIDWAY_ROLLBACK` | **PASS** | L24_INJECTED_AFTER_INSERT_ROLLBACK_ALL |
| `N9B_ATOMIC_POST_FAILURE_READBACK` | **PASS** | no partial receipt; no SALY activation or owner intent, one LF fixture unchanged |

Resultados adicionales: `NEGATIVE_FIXTURE_PERSISTED_PG18` acreditó una fila únicamente en PG18. `N8B_TAMPER_ROLLBACK_RESTORES` acredita que el recibo original volvió a `VERIFIED_CLOSURE_HASH` tras revertir la corrupción simulada. `N9B_ATOMIC_POST_FAILURE_READBACK` confirmó **sin recibo parcial**, sin activación SALY ni aprobación residual. La duplicación retorna `ALREADY_CLOSED_NOOP` y 0 escrituras, conservando el mismo ID.

## 6. CI, hashes y regresión

**Workflow real con resultado SUCCESS:** [GitHub Actions #43313871802](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43313871802), job `131516674312`, tested HEAD `cd8f7d4fc1cd1340edcdf82772a88d258e8f51b6`.

| Bloque | Resultado |
|---|---|
| L13 calidad y familias | **28/28** |
| L14 wrapper | **18/18** |
| L17 actor JWT/HMAC | **25/25** |
| L18 ciclo integrado | **16/16** |
| L20 sincronización de estados | **17/17** |
| L24 recibo/verificador | **23/23** |
| Scripts `test_pg18_*.py` totales | **19/19 PASS** |

Estos conteos se solapan: los scripts contienen los casos previos. Algunos scripts de medición L4 son solo observación y **no prueban fiabilidad del juez semántico**.

MD5 congelados **antes/después** del runner PG18:

| Gate | MD5 |
|---|---|
| `apply` | `86b0494984edf95cf0f9c0a0df67000b` |
| `capture_record` | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| `citation_verify` | `773a62783baa5edbe967200cac66b8c3` |
| `l8 guard` | `522d12f0843be1da3c785cef3c0bf3fc` |

**SHA-256 original del JSON de resultados emitido por el runner:** `6885e4b2d025788378a256bc72a98d0a5094bd5ca3432b30ee01a51f792031e6`.

### Inventario de 19 scripts y SHA-256 de cada log

| Script | Estado | SHA-256 del log |
|---|---|---|
| `test_pg18_lote10_owner_declared_e2e_attestation_limits.py` | PASS | `38acafe8ad6b986933cf3a8c09d31795d5d938275e39ca38b016df66ffe11cc1` |
| `test_pg18_lote11_synthetic_positive_reachability.py` | PASS | `7e1adbf2ba08aba771f1217aba2ec44449d093f6730ebe71f48fd3a7e6d64112` |
| `test_pg18_lote11b_mechanical_positive.py` | PASS | `1838ae8506f82d66accee399dbd8471b96e7ccebb57a3c652713af699a1110f3` |
| `test_pg18_lote14_quality_wrapper.py` | PASS | `fac5762220a401ab781a0303d30f4cf1ff90fac7665f18ca3161367a74f8e586` |
| `test_pg18_lote17_actor_identity_adapter.py` | PASS | `4f540e9f5d86c35f6fa310244c304af04b82d52f600451049fbdd85860aeaee4` |
| `test_pg18_lote18_integrated_cycle.py` | PASS | `72f6ad41865a1210f76b84c607b984ae31ff0840dc919ab66038778e8dd058e2` |
| `test_pg18_lote20_source_sync.py` | PASS | `0513e0f26d006d5121d26f46c528c936cf0438307e9a8cc59eb03885bd9fe3d6` |
| `test_pg18_lote24_closure_receipt.py` | PASS | `1795a8bba7da0fc86c9e7c25045ccfa0909d68c0689e1d5e3cab1532a75aa443` |
| `test_pg18_lote4_mutation_measurement.py` | PASS | `37145e146930f0ac78357b8d1c298c51db852dccf48491604fa377bc4b6241b6` |
| `test_pg18_lote4_semantic_gate.py` | PASS | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4b_validator_reuse.py` | PASS | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4d_profile_owner_approval.py` | PASS | `32a38d6c68d16cfffc39509d60af3090374a6fb3d5d01a258031b66b5caf1a7a` |
| `test_pg18_lote5_real_verdict_profile_return.py` | PASS | `0455e266085b6579c5ca09c97b618c4e9b0f1abaf6c9e61883c31ced930ab8e0` |
| `test_pg18_lote6_claude_blind_5pass_uncited.py` | PASS | `f04e7b0f2d50c21395f11dff95029297b6a0fbc87b60f7f23bb0fdcb0a777680` |
| `test_pg18_lote7_exact_citation_capture.py` | PASS | `f33594571d0f411a1bf9eda5adcbe32b36a66bb35727c9ea7759888d1981e2b9` |
| `test_pg18_lote8_quote_reuse_scoped.py` | PASS | `15f076c5623ea208dae9422d3c8efed0256a86c180aad904ee21762e176fce0b` |
| `test_pg18_lote9_real_chat_export_citation_measurement.py` | PASS | `bd58aeefa9374a829b3e6f785b02318309a555cf07db3dab9789d8ff1341f4b5` |
| `test_pg18_one_rule_promotion.py` | PASS | `d26536606b84c74c716d98c7534ae74938576b7806d0cf7655a55d94a7fe4054` |
| `test_pg18_step40_rule_scope.py` | PASS | `0d6abe0e13835bec20df46bb41ba832d4b4e58644ea1a1f4037274c6dae533d5` |

## 7. Riesgos y criterio de producción

1. **Supabase Auth real no probado:** L17 es simulación de autenticador, rol y HMAC de prueba, no JWT/OIDC validado por Supabase.
2. **Receptor oficial ausente del circuito:** L24 no llama al registrador gobernado del RUN ni demuestra `lf_profile_execution_terminal_authority_receipt_v1` con un `execution_id` nuevo, COMPLETED y 11/11 pasos. **La existencia de la función en vivo por SELECT no prueba recepción.**
3. **Juez no independiente:** mismo modelo/fixture sintético L11B, sin revisor Claude externo independiente ni Step70 nativo.
4. **SALY simulado:** no hay promoción real de SALY ni su retorno nativo; el READY es derivado de L14 SQL fixture.
5. **No ejecutar migración:** SQL, roles y triggers de L24 son exclusivamente de sandbox y no tienen autorización para desplegarse.
6. **Hash es prueba de consistencia interna:** no garantiza firma de propuesta canónica, archivo WORM externo ni recepción por una entidad oficialmente facultada.

**Conclusión:** `SANDBOX_VERIFIED` para el recibo verificable SQL y negativos. `NO-GO/UNVERIFIED` para afirmar cierre gobernado real. No se modifica Router, reglas oficiales, gates ni producto. Ejecutor: GPT-6, **no Claude atestado**.
