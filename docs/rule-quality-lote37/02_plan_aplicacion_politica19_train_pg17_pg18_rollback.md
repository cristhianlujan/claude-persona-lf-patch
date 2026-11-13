# LF L37 — preparación del cambio política central 19, SIN DISPARO

**Fuente:** readback vivo Supabase PostgreSQL 17.6, L36 policy19 patch; EKB V1.4; CLAUDE.md/AGENTS.md y docs/migrations/MIGRATION_MERGE_TRAIN_V1.md en main.

## Alcance autorizado
Solo preparar la aplicación de la **descripción** de `lf_ops.politicas_seguridad` ID 19 `SEC-B2B-MFA-FACTOR-ELIGIBILITY`. Usuarios perfiles 1 y 2: usuario+contraseña servidor → OTP por correo/Brevo si MFA aplica; perfiles 3–6 conservados; sin FIDO2; riesgo phishing aceptado en conversación, pendiente de firma. **No ejecutar escritor, no tocar Supabase, no promover.**

## Autoridad y ruta exacta
| Gate | Ruta | Resultado actualmente comprobado |
|---|---|---|
| Router de escritura | `public.lf_router_resolve_v1(text)` para operación `ACTUALIZACION_DB_LF` con objetivo y alcance positivo/negativo atestados | `BLOCK_SCOPE_SEMANTICS_UNATTESTED` en la consulta de preparación; NO autorización de efectos |
| Selección transporte | `DB_WRITE_TRANSPORT` con `--target-type MIGRATION --router-operation ACTUALIZACION_DB_LF` | Solo ruta canónica `MIGRATION_VIA_MERGE_TRAIN`; no direct SQL ni Supabase `apply_migration` |
| Código SQL que escribiría | `UPDATE lf_ops.politicas_seguridad SET description=<texto exacto> WHERE security_policy_id=19 AND policy_code=...` dentro de DO con preimagen, readback y fallo cerrado | Código preparado como **`apply_preparation/policy19_description_only_candidate.sql`**, NO bajo `supabase/migrations/` |
| Transporte real autorizado posterior | Un PR contra main con una sola migración clasificada `lf_b2b_policy19_admin_otp_description_v1`; checks `PASE`, `lf-independent-change-admission`, `ig-runtime-candidate-judge`, revisión, etiqueta `ready-to-merge`, cola exclusiva `lf-migrations`; Train asigna versión, preflight, `DB_WRITE_TRANSPORT`→`lf_migration_exact_apply.py` y ledger, parity, exact-head merge/readback | **NO PR, NO etiqueta, NO Train iniciado** |
| Trigger DB en aplicación | `lf_ops.touch_updated_at()` cambia timestamp. También ejecuta `programacion.fn_guard_input_parameter_provenance_v1()`, que exige nuevos provenance si cambia `policy_config` (este draft NO lo toca). | Solo fuente/funciones vivas revisadas SELECT |
| Aprobación | Confirmación exacta del dueño de ejecutar **la migración** sobre el HEAD con evidencias; identidad del dueño aún no verificada | **PENDIENTE** |

## Controles de preimagen
- Política 19 original: `f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07` SHA-256 `to_jsonb(p)::text`; estado CANDIDATO. Si difiere en una sola propiedad, el SQL aborta.
- Texto propuesto SHA-256 UTF-8: `0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b`.
- Full patch documental L36: `4e2156de362f377ace9a0aef758a136501c9530ca02f7ee20691f38494b021f7`; **NO** se corresponde con la migración description-only porque ese patch también proponía `policy_config`. Usar SHA propios y scopes separados.
- Rollback de laboratorio: transacción `BEGIN` + aplicar DO + readback + `ROLLBACK`, verificar que el full-row SHA vuelve exactamente a la preimagen; drift negativo debe detener con `LF_POLICY19_SOURCE_PREIMAGE_DRIFT`.
- Rollback de una migración YA confirmada no es equivalente a un `ROLLBACK` de laboratorio: exige compensación/forward-only o inversa por la MISMA ruta gobernada, con nueva preimagen, aprobación y readback. No prometer reversibilidad directa después del commit.

## Pruebas requeridas antes de elevar el PR
| Test | Preparado | Ejecutado | Estado |
|---|---|---|---|
| PostgreSQL 17.6 Docker: fuente snapshot, migración, readback, rollback, drift negativo | fixture + arnés real | NO | **NOT_TESTED** |
| PostgreSQL 18.7 Docker: fuente snapshot, migración, readback, rollback, drift negativo | fixture + arnés real | NO | **NOT_TESTED** |
| Integración con constraints/triggers completos, PASE y Merge Train | solo plan / snapshot constraints | NO | **NOT_TESTED** |
| Base viva, solo SELECT: política 19, hash y forma documental | L36 48/48 | SÍ | **PASS SELECT-ONLY**, NO aplicación |
| Identidad, frase literal, juez semántico independiente, RUN | no se ha generado recibo oficial | NO | **BLOCKED** |

**Entorno disponible:** runtime sin Docker, Podman ni psql y SentinelX sin hosts conectados (solo offline). Supabase actual indica PostgreSQL **17.6**; acceder por SELECT no sustituye probar migración en PG17.6 ni PG18.7.

## Bloqueo material anterior al disparo
- El cambio de **texto solamente** no reconcilia ocho valores discordantes en `policy_config` (PHISHING_RESISTANT, Google SAML, passkey, etc.), ver L36 `nine_fields`; `admin_profile_ids=[1,2]` sí es correcto.
- Si el dueño decide aplicar los valores de configuración también, ese es un **cambio de alcance**: requiere migración/patch específico con proveniencia renovada para cada clave alterada, modelado de nuevas claves/valores, QA y aprobación gobernada separada.
- En estado actual **NO-GO de aplicación** aunque la sintaxis del draft esté preparada; falta reconciliación semántica, pruebas duales y Router con alcance atestado.

## Artefactos
- `apply_preparation/policy19_description_only_candidate.sql` — solo borrador, ejecutor SQL dentro del Train, sin disparo
- `apply_preparation/policy19_pg_isolated_fixture.sql` — snapshot 19 y columna/timestamp, no full parity de triggers
- `apply_preparation/test_policy19_pg17_pg18_rollback.py` — dos versiones Docker, positivos/negativos, rollback, **NO EJECUTADO**
- `01_frases_exclusivas_firma_documental_login.json` — frases copia por documento, SHA de documento ≠ SHA del patch de la función V2
