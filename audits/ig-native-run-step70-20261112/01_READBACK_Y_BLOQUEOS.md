# LF — RUN / Step70 nativos, identidad, owners, backup | Readback 2026-11-12

**Estado: AUDITADO / BLOQUEADO PARA CIERRE TÉCNICO.** No se declara VIGENTE, producción ni motor cerrado.
**Fuente normativa:** INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4. **Proyecto inspeccionado:** `mhwmirqcgxxukpctffuv` (actual, no destino definitivo). **Repo base:** `cristhianlujan/claude-persona-lf-patch@882c7213f83887952a99ad0793174d535eb91233`.

## 1. Operación efectuada y límites

- Solo consultas `SELECT` a Supabase mediante rol `supabase_read_only_user`, inspección del código GitHub y del Edge desplegado.
- **0 INSERT / UPDATE / DELETE / DDL; 0 invocaciones a escritores; 0 modificaciones o reanudaciones de RUN históricos; 0 desplegues; 0 pruebas con HMAC de prueba.**
- La rama de auditoría contiene solo material nuevo (no reemplaza ficheros oficiales). Este documento no acredita acciones externas aún no ejecutadas.

## 2. Evidencia objetiva del entorno

| Check | Readback / evidencia | Interpretación |
|---|---|---|
| Supabase URL | `https://mhwmirqcgxxukpctffuv.supabase.co` | Proyecto actual confirmado |
| Ruta de entrada | `ACT-0001 → perfil → RUN → IG (si aplica) → Step70 → Step80` | EKB V1.4, no crear ruta paralela |
| RUN `EJECUCION_PERFIL_LF` | 61: `COMPLETED=31`, `IN_PROGRESS=12`, `CANCELLED=16`, `BLOCKED=1`, `PASS_PRE_INDEPENDENT_REVIEW=1` | Histórico observado, **no intervenido** |
| Contrato de pasos | 11 pasos en `public.lf_operation_steps` | Releer contrato por ejecución |
| Step70 en RUN de perfil | 32 `STEP_PASS_WITH_EVIDENCE`; 3 `BLOCKED_STEP_NOT_CLEAN` | No prueba independencia del proveedor por sí solo |
| RPC Step70 | `public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)` | Existe y llama al escritor `lf_record_profile_execution_step_v1` |
| RPC duplicado begin | `lf_profile_native_bridge_begin_v1` retorna `DUPLICATE_NATIVE_BRIDGE_ENTRY_RETIRED` | No reactivarlo como otra entrada |
| Grants Step70 | `authenticated=NO EXECUTE`; `service_role=EXECUTE` | RPC server-side; no usar SQL de auditoría para escritura |
| Caller desplegado | `lf-profiles-governance-caller-v1` ACTIVE, versión 70 | Valida GitHub Actions OIDC con `jose`, JWKS, issuer/audience y workflow/ref; `verify_jwt=false` no implica endpoint público sin control propio |
| IG Edge | `input-governance-agent-v1` ACTIVE, versión 18 | Control server-side `service_role` |
| Auth | 1 usuario, 1 identidad, 1 email confirmado, 0 factores MFA verificados | La cantidad **no acredita** que el usuario sea el dueño ni que tenga autoridad |
| `auth.uid()` de la inspección | NULL (`has_actor_claim=false`) | **No es prueba con una sesión real de Supabase Auth** |
| Policy de autoridad humana | `private.lf_human_decision_authority_policies_v1`: 0 registros / 0 ACTIVE | **BLOQUEO DE OWNER**; no inventar policy/identidad |
| Decisiones de autoridad | `programacion.human_decisions`: 0; `authority_attestations`: 0 | Sin recibos humanos verificables en dichas tablas |
| Perfil write authority | `public.lf_profile_write_authority_v1`: 31 ACTIVE | Control de permiso de perfil; **no** equivale a registro de owners humanos |
| Inventario backup | 2,452 RUN totales, 8,236 pasos, 578 reglas, 1 storage bucket, 1 objeto de Storage | Controles de conteo al restaurar; no constituyen backup |

## 3. Preimagen de definiciones desplegadas (SHA256 de `pg_get_functiondef` UTF-8)

- `lf_profile_execution_begin_from_handoff_v1`: `0d8ed29e64ff79a743063d68097716a1a2beed4e4afd0454af6005c1193d94a0`
- `lf_profile_native_bridge_record_semantic_v1`: `1884c34222e2cfa5516c9f295621db39ab8bcdbf81e0b9fb17a6f3fb80bd3813`
- `lf_profile_native_bridge_record_report_v1`: `592eb7c59d7a6d12507486e37c6ab160732ef1fcb216244c1dc0e3f346516cd8`
- `lf_record_profile_execution_step_v1`: `477cd1220dc1e3fe53adca1c0ddc6ac8cef4df5b6c92f9f49a76122831b48273`

**Condición obligatoria:** si se propone modificar alguna de estas funciones, releer definición y SHA256 inmediatamente antes de operar, guardar RAW y volver a comprobarlos; abortar con drift. Estos hashes se preservan como evidencia de **lectura**, no como copia restaurable del SQL ni como prueba de backup físico.

## 4. Natividad, HMAC y Step70

- La **ruta actual** de ejecución de perfiles usa GitHub Issue → GitHub Actions → OIDC real → Edge `lf-profiles-governance-caller-v1` → RPC nativa, no un HMAC de prueba para admitir el perfil. Las cuatro funciones listadas no mencionan HMAC en su definición vigente. Existen HMAC en **otros subsistemas históricos** (p. ej. reconciliación): no eliminarlos fuera de alcance.
- `scripts/lf_profile_native_resume.py` **consume** un objeto `semantic_judge_review` proporcionado; **no realiza por sí solo una llamada de modelo independiente**. `profile_continuation.ts` registra el resultado por RPC.
- La RPC exige `model_call_count=1` y `producer_independence_proven=true` para el modo independiente, pero esa comprobación es sobre **campos declarados**; no acredita una llamada independiente al proveedor ni la identidad del revisor.
- El modo `CURRENT_CONTEXT_REVIEW` sólo puede ser lectura con `no_write=true` y `no_promotion=true`. No reutilizarlo como autorización para edición/promoción.
- No existe prueba nueva, en este lote, de autor de Step70 mediante una sesión Supabase Auth real. El servicio Edge OIDC y el actor humano son autoridades distintas.

## 5. Gates para habilitar cierre real (todos obligatorios)

| Gate | Verificación exigida | Estado 2026-11-12 |
|---|---|---|
| G01 NATIVE_TRANSPORT | OIDC real, issuer/audience/repo/ref/workflow, sin HMAC de test; canary negativo de emisor inválido | PARCIAL: fuente/verificador observados; **sin canary nuevo** |
| G02 HUMAN_AUTH | Sesión real Supabase Auth, `auth.uid()` no null, verificada por backend; sin impersonación de service_role | BLOQUEADO: no hay sesión real en esta conexión |
| G03 OWNER_REGISTRY | Vinculación owner ↔ `auth.users.id` ↔ rol/alcance ↔ vigencia; política/recibo autorizados y readback | BLOQUEADO: policy 0, attestation 0 |
| G04 STEP70_JUDGE | Llamada de modelo/revisor realmente independiente con evidencia externa, candidato/scope SHA exactos, 12 checks, negativos | PARCIAL: contrato de consumo existe; no invocación nueva acreditada |
| G05 READBACK | Nuevo RUN sintético autorizado, 11/11, Step70 y Step80, recibo terminal READY, negativos fail-closed | NO EJECUTADO, por bloqueo de autoridad |
| G06 BACKUP_RESTORE | Backup real cifrado fuera del proyecto, inventario, restauración aislada, hashes, roles/Auth/Storage/Edges y prueba de recuperación | SOLO PLAN; falta ejecución externa |

**Prohibido:** marcar `READY`, `VIGENTE`, `PASS_INDEPENDENT`, `PROMOTED` o `RESTORE_VERIFIED` solo por esta auditoría.

## 6. División de responsabilidad

**Cerrado por la auditoría:** lectura del EKB, inventario vivo, comprobación del bridge y permisos, identificación del hueco entre OIDC actor máquina y Supabase Auth actor humano, preimágenes SHA256, paquete SQL reproducible y plan de backup/restauración.

**Externo / dueño:** autenticar y vincular la identidad del owner con recibo gobernado; activar policy de autoridad con alcance; autorizar y ejecutar migraciones/deploy por escritor oficial/CI; proporcionar juzgador independiente y traza verificable sin credenciales en prompts; habilitar export/backup y restauración aislada; aprobar promoción solo tras evidencia.

**Siguiente lote autorizado:** ejecutar `02_PREFLIGHT_SOLO_LECTURA.sql`, verificar drift; el operador designado completa los recibos externos, después prepara cambio acotado en rama separada con pruebas negativas y backup verificable **antes del deployment**, sin tocar RUN históricos.
