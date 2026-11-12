# L17 — Adaptador de identidad para PostgREST / PostgreSQL 18

**Estado:** `SANDBOX_VERIFIED` para controles mecánicos; **`BLOQUEA_PRODUCCION / NO-GO / UNVERIFIED`** para uso oficial.

- Rama: `lf/issue-3779-lote17-actor-identity-adapter-v1` desde `5a43176b6aa54016d61b3c9cdde261e0cb193210` (L14).
- CI: [ejecución real #43294775544](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43294775544); HEAD bajo prueba: `3d044c878dc382fbfddb6e51d2be78309e93fa10`.
- EKB leída: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, estado `CANDIDATO VERIFICADO PARCIALMENTE`; no suple contratos oficiales. Ningún Route/Gate2, Step70, OIDC, IG ni producto real fue ejecutado.
- Autoría del trabajo en este chat: **GPT-6, no Claude acreditado**. Tampoco hay juez semántico externo firmado.

## 1. Hallazgo objetivo: `session_user` de L14 no sirve como identidad final

**Reproducción V1 previa a aplicar el overlay L17:**

```text
session_user = l17_authenticator
current_user = lf_owner_role
current_setting('role') = lf_owner_role
L14 trusted_actor_role('lf') -> 42501 BLOCK_QUALITY_ROLE_UNMAPPED
```

La simulación utiliza `l17_authenticator LOGIN NOINHERIT`, con derechos de `SET ROLE` explícitos hacia `lf_owner_role`, `lf_super_role`, `lf_reader_role`, `saly_owner_role` y `saly_super_role`. Cada solicitud utiliza `SET LOCAL ROLE` y `set_config('request.jwt.claims',...,true)` dentro de una transacción; el claim desaparece tras `ROLLBACK`.

En Supabase real, el pooler/PostgREST puede usar `authenticator` como rol de sesión y `authenticated` como rol efectivo para múltiples usuarios. **Ninguno identifica por sí solo al usuario final**. El usuario debe resolverse desde un JWT verificado y la tabla de mapeo por proyecto. Los roles especializados de este ensayo son **solo un montaje de laboratorio**, no un contrato de despliegue Supabase.

## 2. Diseño de identidad y flujo de calidad

```text
Petición sintética
  ↓
l17_authenticator LOGIN NOINHERIT
  ↓ SET LOCAL ROLE (permiso real PostgreSQL)
current_user = lf_owner_role / saly_owner_role
  ↓ set_config(request.jwt.claims, JSON firmado con HMAC, true)
l17_assert_request_current_user_v2 (SECURITY INVOKER)
  ├─ compara current_user vs rol efectivo PostgreSQL
  └─ invoca l17_verify_signed_claim_v2
       ├─ firma HMAC-SHA256 válida con secreto privado efímero
       ├─ issuer, audience, iat, nbf, exp
       ├─ project_code explícito
       ├─ role del claim = rol efectivo SET ROLE
       ├─ (project_code, sub, role) = actor mapeado
       ├─ owner_profile_code + can_approve
       └─ SUPER_ADMIN → BLOCK
  ↓
quality_prepare_new_v2 / quality_apply_envelope_v2
  ↓ wrappers L14 existentes (SECURITY DEFINER)
trusted_actor_role() → trusted_actor_role_v2()
  ↓ aplica verificación JWT de nuevo con rol PG controlado
Quality trigger v2 → ticket + metadata + actor firmado
  ↓
LF apply congelado / SALY fixture sintético
  ↓
VIGENTE + reviewed_at + next_review_at + readback READY
```

**Detalle de límites SQL:** `current_user` pasa a ser el *owner* de la función dentro de `SECURITY DEFINER`; por eso la capa `SECURITY INVOKER` compara `current_user` primero. Dentro de las funciones privilegiadas, la comparación independiente usa el parámetro interno de rol de PostgreSQL (`current_setting('role')`), que refleja `SET ROLE` validado por PostgreSQL, junto con el JWT HMAC firmado. No se acepta `p_actor` libre.

El secreto HMAC se genera aleatoriamente dentro del PG18 limpio (`extensions.gen_random_bytes(32)`) y se guarda en tabla privada. No se exporta a GitHub ni se permite firmar claims desde los roles cliente. El claim **no es** un JWT compacto validado por Supabase Auth; es JSON con `test_signature` HMAC creado exclusivamente por el fixture privilegiado.

## 3. Controles negativos pareados y positivos

| Control adversarial | Resultado |
|---|---|
| Sin firma / firma manipulada | `BLOCK_L17_JWT_SIGNATURE_INVALID` |
| Firma válida de otro proyecto | `BLOCK_L17_JWT_PROJECT_MISMATCH` |
| Firma válida con sub inexistente | `BLOCK_L17_JWT_SUB_UNMAPPED` |
| Claim.role ≠ rol efectivo | `BLOCK_L17_JWT_EFFECTIVE_ROLE_MISMATCH` |
| SUPER_ADMIN firmado y rol real | `BLOCK_SUPER_ADMIN_APPROVAL` |
| Reader firmado y rol real | `BLOCK_L17_NOT_PROJECT_OWNER` |
| JWT expirado | `BLOCK_L17_JWT_EXPIRED_OR_NOT_YET_VALID` |
| Claim ausente | `BLOCK_L17_JWT_MISSING` |
| Login directo del actor (sin authenticator) | `BLOCK_L17_NOT_AUTHENTICATOR_SESSION` |
| DML de reglas sin GRANT | `permission denied for table rules` |
| Cliente intenta firmar token | `permission denied for function l17_sandbox_mint` |
| Cliente intenta DISABLE TRIGGER | Rechazado por propiedad de la tabla |
| Función L14 antigua sin JWT | `BLOCK_L17_JWT_MISSING` |
| Actualización directa del mapa de sujetos | Rechazada por GRANT |
| Actor LF firmado y perfil propietario | `JWT_HMAC_SANDBOX_VERIFIED` |
| Actor SALY firmado y perfil propietario | `JWT_HMAC_SANDBOX_VERIFIED` |
| SALY + wrapper v2 | `QUALITY_PREPARED → READY`, `next_review_at` presente |
| LF L11B mecánico + wrapper v2 | `APPLIED → VIGENTE → READY`, fecha de revisión presente; `ROLLBACK` confirmado |
| Corrección de regla existente por v2 | Sucesora con código distinto en `EN_REVISION` |
| Claims `SET LOCAL` y rollback | Contexto de sesión no persiste |

Los cuatro negativos principales están **pareados con positivos LF/SALY**, y todos los demás controles exigidos quedaron comprobados en ejecución real de PostgreSQL 18.

## 4. Conteos

| Suite | Ejecutadas | Aprobadas | Cobertura |
|---|---:|---:|---|
| L13 heredado | 28 | 28 | Ciclo, familias, detector y OWNER |
| L14 heredado | 18 | 18 | GRANT/RLS, familia, sucesión, trigger y readback |
| L17 nuevo | 25 | 25 | Actor, firma, sub, role, proyecto y flujos |
| Scripts `test_pg18_*.py` completos | 16 | 16 | Incluye todos los anteriores más L17 |

**No sumar scripts y sus casos** como si fueran pruebas independientes: los 16 scripts incluyen los tests L14 y L17.

## 5. Regresión L14: los 18 controles no se pierden

El script L14 original no fue modificado y se ejecutó como script separado sobre base PG18 limpia en el CI L17, con resultado `L14_SANDBOX_PASS tests=18`.

| ID L14 | CI L17 |
|---|---|
| `GATE_MD5_INITIAL` | PASS |
| `N1_NO_FAMILY` | PASS |
| `N2_CROSS_PROJECT_FAMILY` | PASS |
| `N3_FORGED_GUC` | PASS |
| `N4_DIRECT_DML_NO_GRANT` | PASS |
| `N5_SUPER_ADMIN_FORBIDDEN` | PASS |
| `N6_NO_QUALITY_METADATA_DIRECT_SOURCE` | PASS |
| `P1_VALID_FAMILY_REVIEW_SCHEDULED` | PASS |
| `N7_NO_TICKET_CANNOT_BYPASS_WRAP` | PASS |
| `N10_REVIEW_TIME_CANNOT_BE_SPOOFED` | PASS |
| `N11_VIGENTE_CONTENT_IS_IMMUTABLE` | PASS |
| `N8_NO_TICKET_EVEN_WITH_METADATA` | PASS |
| `P2_EXPLICIT_SUCCESSOR_NOT_EDIT_IN_PLACE` | PASS |
| `N9_CORRECTION_NO_SUCCESSOR` | PASS |
| `P3_SALY_SAME_WRAPPER_ADAPTER` | PASS |
| `P4_DUE_IS_PROPOSAL_NEVER_AUTO_MUTATION` | PASS |
| `P5_L11B_FROZEN_APPLY_WRAPPER_READY` | PASS |
| `GATE_MD5_UNCHANGED` | PASS |

## 6. Test L17: 25 resultados reales

| ID L17 | Resultado |
|---|---|
| `L17_01_V1_SESSION_USER_FAILS` | PASS |
| `L17_02_POSTGREST_CONTEXT` | PASS |
| `L17_00_FROZEN_GATE_MD5_BEFORE` | PASS |
| `L17_03_LF_SIGNED_SUB_ROLE_PASS` | PASS |
| `L17_04_SALY_SAME_VERIFIER_PASS` | PASS |
| `L17_05_BAD_HMAC` | PASS |
| `L17_06_OTHER_PROJECT` | PASS |
| `L17_07_UNMAPPED_SUB` | PASS |
| `L17_08_ROLE_MISMATCH` | PASS |
| `L17_09_SUPER_ADMIN_DENIED` | PASS |
| `L17_10_READER_DENIED` | PASS |
| `L17_11_EXPIRED_JWT` | PASS |
| `L17_12_CLAIMS_MISSING` | PASS |
| `L17_13_DIRECT_LOGIN_NOT_POSTGREST` | PASS |
| `L17_14_DIRECT_DML_BLOCKED` | PASS |
| `L17_15_SIGNING_ORACLE_BLOCKED` | PASS |
| `L17_16_SOURCE_TRIGGER_DISABLE_BLOCKED` | PASS |
| `L17_17_LEGACY_DEFINER_NO_JWT_BYPASS` | PASS |
| `L17_18_ROLE_ALONE_NOT_AUTHORITY` | PASS |
| `L17_19_DIRECT_ACTOR_MAP_DML_BLOCKED` | PASS |
| `L17_20_TRANSACTION_LOCAL_CLAIMS_RESET` | PASS |
| `L17_21_SALY_PREPARE_APPLY_READY` | PASS |
| `L17_22_EXPLICIT_VERSION_REVIEW` | PASS |
| `L17_23_L11B_SIGNED_SUB_WRAP_READY` | PASS |
| `L17_24_FROZEN_GATE_MD5_AFTER` | PASS |

## 7. Inventario exhaustivo de los 16 scripts PG18 anteriores y actuales

| Script | Resultado | SHA-256 del log |
|---|---|---|
| `test_pg18_lote10_owner_declared_e2e_attestation_limits.py` | PASS | `38acafe8ad6b986933cf3a8c09d31795d5d938275e39ca38b016df66ffe11cc1` |
| `test_pg18_lote11_synthetic_positive_reachability.py` | PASS | `7e1adbf2ba08aba771f1217aba2ec44449d093f6730ebe71f48fd3a7e6d64112` |
| `test_pg18_lote11b_mechanical_positive.py` | PASS | `1838ae8506f82d66accee399dbd8471b96e7ccebb57a3c652713af699a1110f3` |
| `test_pg18_lote14_quality_wrapper.py` | PASS | `3e5fe0ba3755d6850a9542eecb5254747a180151021c1347cb62a7be49719e1d` |
| `test_pg18_lote17_actor_identity_adapter.py` | PASS | `eca47cd67c90efc483789fd3f2ceb9d87fbef9edd6c17c32aa7f56381cab62b4` |
| `test_pg18_lote4_mutation_measurement.py` | PASS | `37145e146930f0ac78357b8d1c298c51db852dccf48491604fa377bc4b6241b6` |
| `test_pg18_lote4_semantic_gate.py` | PASS | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4b_validator_reuse.py` | PASS | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4d_profile_owner_approval.py` | PASS | `32a38d6c68d16cfffc39509d60af3090374a6fb3d5d01a258031b66b5caf1a7a` |
| `test_pg18_lote5_real_verdict_profile_return.py` | PASS | `0455e266085b6579c5ca09c97b618c4e9b0f1abaf6c9e61883c31ced930ab8e0` |
| `test_pg18_lote6_claude_blind_5pass_uncited.py` | PASS | `f04e7b0f2d50c21395f11dff95029297b6a0fbc87b60f7f23bb0fdcb0a777680` |
| `test_pg18_lote7_exact_citation_capture.py` | PASS | `f33594571d0f411a1bf9eda5adcbe32b36a66bb35727c9ea7759888d1981e2b9` |
| `test_pg18_lote8_quote_reuse_scoped.py` | PASS | `15f076c5623ea208dae9422d3c8efed0256a86c180aad904ee21762e176fce0b` |
| `test_pg18_lote9_real_chat_export_citation_measurement.py` | PASS | `bd58aeefa9374a829b3e6f785b02318309a555cf07db3dab9789d8ff1341f4b5` |
| `test_pg18_one_rule_promotion.py` | PASS | `fc760d8ba60afeae4abbbbfb96b1e0d0284b53c70c0ad84cc43aea28bf0dbf91` |
| `test_pg18_step40_rule_scope.py` | PASS | `0d6abe0e13835bec20df46bb41ba832d4b4e58644ea1a1f4037274c6dae533d5` |

## 8. Gates congelados: MD5 antes y después, calculados en PG18

| Gate | MD5 antes = después |
|---|---|
| `apply` | `86b0494984edf95cf0f9c0a0df67000b` |
| `capture_record` | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| `citation_verify` | `773a62783baa5edbe967200cac66b8c3` |
| `l8 guard` | `522d12f0843be1da3c785cef3c0bf3fc` |

La comparación Git desde el commit L14 confirma que **no se modificó ninguna migración ni SQL de estos gates**. Los únicos reemplazos `CREATE OR REPLACE` están dentro de funciones del esquema de calidad `rule_quality_l13`.

## 9. SHA de fuentes y prueba

| Artefacto | SHA-256 |
|---|---|
| `08_l17_postgrest_roles_fixture.sql` | `3ddf86b0d082ad76ea2f4f0815e26b415274cc642d8d27477d0ffa3819a17707` |
| `09_l17_verified_actor_v2.sql` | `c2b5b9150106a03ac5703d4957a9d664c47b2512bdb98ab42d6593ab59f1c709` |
| `10_l17_quality_trigger_acl.sql` | `63f9b77561587b4f1bda1c2bf1a61711e26479d22c7969918afa34e90fa9158c` |
| `test_pg18_lote17_actor_identity_adapter.py` | `9e3ec18b37d26541b209a3ca587e8ac797342e099e4963808cc4695fe8d93684` |
| `l17-actor-identity-adapter-pg18.yml` | `e3b1b094077c8f548c92908314c0b06698e8bdd6740b5f6babc49433421f3ee1` |

- SHA-256 del JSON original de ejecución L17 registrado por runner: `7bf2b65394385b89ba8c3cb732915688c22f1098194dc425f0a55adb79244b2d`.
- Evidencia exhaustiva: `01_pg18_real_results.json` (25 resultados con bloqueos reales y 16 hashes de logs).
- Readback: `02_source_sha_readback.json` (Git blob + SHA-256 de fuentes y diff estricto).
- Workflow: `.github/workflows/l17-actor-identity-adapter-pg18.yml`.

## 10. Decisiones pendientes — **BLOQUEA_PRODUCCION**

1. **Identidad real:** el HMAC efímero del sandbox NO es Supabase Auth ni valida un JWT auténtico de Supabase. Con PostgREST real las claims son ingresadas tras validación externa, y los GUC son configurables por SQL en otros contextos. Falta enlazar a una autenticación verificada real por el servidor, comprobando issuer, audience, JWKS/firmas, revocación/caducidad y límites de conexión; no afirmar que `request.jwt.claims` por sí mismo es confiable.
2. **Modelo de roles real:** en Supabase `current_user` suele ser `authenticated` para múltiples usuarios. Se necesita una derivación de autorización del `sub` a perfil/owner oficial, sin usar roles de laboratorio `lf_owner_role` como si fueran roles de producción.
3. **Confianza en funciones:** `SECURITY DEFINER` se simuló como superusuario del cluster. En un despliegue se requieren grants/RLS robustos, dueño de privilegio mínimo y auditoría de llamadas; los triggers y wrappers siguen siendo candidatos.
4. **Ejecución oficial:** no se ejecutó Router, RUN real, Step70, OIDC, IG independiente ni decisor/owner oficial. El positivo LF de L11B usa datos sintéticos de procedencia y no autoriza una promoción real.
5. **Gobernanza:** no existe Merge Train/PR de aplicación ni permisos de producción; no se hizo DDL/DML en Supabase vivo, merge ni alteración del SQL del gate. La definición debe ser revisada por el dueño antes de cualquier operación gobernada.
6. **No acreditación Claude:** el modelo que implementó el ensayo fue GPT-6, no una ejecución Claude atestada.

**Cierre operativo:** diseño y test de sandbox 100% completado; autorización de despliegue 0%. Estado global `NO-GO/UNVERIFIED`. No reemplazar los recibos oficiales con hashes de test.
