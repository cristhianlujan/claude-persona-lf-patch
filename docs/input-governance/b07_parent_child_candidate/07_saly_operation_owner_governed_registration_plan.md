# B07 SALY — alta gobernada de operación y owner (preparación, NO deploy)

**Estado:** CANDIDATO DOCUMENTAL / BLOCKED. No hay autorización ni evidencia de una alta efectiva. **No ejecutar escritores V2, registrar owners mediante DML directo, tocar RUN ni activar Merge Train desde este PR.**

## Autoridad y alcance
- Mandato del dueño 2026-11-13: **preparar**, no ejecutar el alta. Fuente documental #3821 `DEC-B07-PADRE-HIJA-001` integrada a main; `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `identity_verified=false` (NO firma autenticada).
- Dependencia: PR #3818 (función candidata `public.lf_ig_saly_rule_finalize_b07_v1(text)`, blob `ff6d47c70f42f5fb2ad6f8b132caf278ec16c79d`), SIN Train ni DDL autorizado.
- Supabase temporal: `mhwmirqcgxxukpctffuv`, solo SELECT de descubrimiento. EKB INPUT GOVERNANCE LF V1.4: Router ACT-0001 → perfil → RUN → IG → validación/juez/registro/cierre, sin bypass ni escritura directa.

## Readback previo de catálogo (solo SELECT, no cierre)
- `public.lf_operation_registry` NO registra `ACTUALIZACION_REGLA_SALY`.
- `public.lf_ig_project_owner_v2` contiene LF y NO contiene SALY. Tabla obliga `project_code IN ('LF','SALY')`, `owner_name='Cristhian Luján'`, `identity_mode='UNVERIFIED_CHAT_DECLARATION'`, receipt SHA-256 válido y `status IN ('CANDIDATE','TEMP_DOCUMENTARY_ACTIVE','SUSPENDED')`.
- La LF registrada usa un `owner_sub` explícitamente **placeholder interno, no Supabase Auth**; no reutilizarlo automáticamente como identidad/credencial SALY.
- En `public.lf_activos`, el filtro PERFIL con código SALY/PRODUCT-DIRECTOR solo retornó `PERFIL-PRODUCT-DIRECTOR-LF`. No se acreditó perfil SALY oficial. No fabricar `owner_profile_code`.

## Lote de alta oficial futuro (NO materializado)
1. **Autoridad SALY separada:** recibir decisión específica de alta SALY, alcance, perfil owner SALY válido, identificador interno obtenido del registrador oficial y recibo de autoridad SHA-256 verificable. Un chat sin autenticación NO eleva `identity_verified`.
2. **Operación:** bootstrap oficial con ejecución/procedencia y verificación del contrato y del registro `public.lf_operation_registry`; operación exacta `ACTUALIZACION_REGLA_SALY`; fuentes efectivas `saly.reglas`, `saly.decisiones`, historial B07 y finalizador oficial. El writer exige `status='SANDBOX_ACTIVE'` y child `COMPLETED` con 7 `PASS_CLEAN`; no insertar manualmente un `created_by_execution_id` ficticio. Resolver también Router y binding de modo por ruta vigente, no solo el registro de nombre.
3. **Owner SALY:** alta gobernada en `public.lf_ig_project_owner_v2`, `project_code='SALY'`, `owner_name='Cristhian Luján'`, perfil registrado, `authority_receipt_sha256` real, `source_execution_id` real y `identity_mode='UNVERIFIED_CHAT_DECLARATION'`. Dejar en `CANDIDATE` hasta que controles autoricen `TEMP_DOCUMENTARY_ACTIVE`. No reutilizar el recibo LF ni afirmar identidad verificada.
4. **Prueba en aislamiento:** PG17.6/18.7 con operación+owner sintéticos claramente etiquetados; prueba positiva y negativos para owner ausente, autoridad obsoleta, perfil inválido, escalamiento de rol, child no completado, 7 pasos ausentes, decisión SALY/resultado inconsistentes; rollback y restauración posdatos. Los tests de #3818 no acreditan registro SALY en vivo.
5. **Carriers separados:** un PR/Train exclusivo y versionado para operación/owner, posterior a la evidencia de bootstrap y owner; no mezclar con migración padre/hija #3818. Confirmar cadena de autoridad, SHA-256 pre/post, catálogo, ACL y readback mediante SELECT real antes de cualquier escritor SALY. El dueño debe aprobar por separado Train DDL #3818.

## Bloqueos hasta obtener evidencia
- `B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED` (writer exige operación SANDBOX_ACTIVE).
- `B07_SALY_OWNER_REGISTRY_MISSING` (writer exige owner SALY activo vinculado a decisión V2).
- `B07_SALY_ROUTER_PROFILE_RUN_REQUIRED` (RUN parent habilitado con project_code SALY).
- `B07_SALY_OWNER_AUTHORITY_EVIDENCE_MISSING` (**código de preflight propuesto**, no afirmar error emitido por runtime).

## Evidencia de cierre exigida
PR/Train autorizado, bootstrap y owner recibidos, 3 CI PASS en HEAD exacto, conteos sin duplicados, procedencia y hash verificables, permisos explícitos, negativos PG17.6/18.7, SELECT previo/posterior y backup/restauración. Cualquier ausencia mantiene NO-GO. **Este PR solo documenta preparación y SELECT; no contiene DDL/DML.**

## DECISIÓN DE OWNER SALY — 2026-11-13 12:53 Lima (autoridad documental)
La frase textual reportada por el dueño es **"Si me designo"**. El mandato actual especifica expresamente el alcance: Cristhian Luján queda owner **documental** del proyecto SALY y autoriza crear/homologar perfil canónico SALY propio, **sin heredar el perfil LF**. No verificar identidad por chat: `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `identity_verified=false`; producción no autorizada.

Evidencia normalizada: `docs/input-governance/b07_parent_child_candidate/10_owner_saly_decision_20261113.json`; SHA-256 de bytes UTF-8 del JSON canónico: `107332ebbae4295dc76179bd5619856cb61807b91a856c080b12e1942018fb0f`. El hash acredita integridad de los bytes, **no autenticación**.

## Ejecución candidata por ruta oficial (SIN escritores vivos)
- **Perfil SALY propio**: `profiles/saly_product_director/`, nuevo pack canónico `PERFIL-PRODUCT-DIRECTOR-SALY`, `CANDIDATO/READ_ONLY/NO_HABILITADO`. La creación en `public.lf_activos` debe ocurrir mediante el RUN nativo de `CREACION_PERFIL_LF` y no con INSERT en el Train SALY.
- **Train SALY separado**: `supabase/migrations/20261113190500_lf_ig_b07_saly_operation_owner_register_v1.sql`. Preflight rechaza si falta el perfil creado con RUN `COMPLETED` y misma procedencia. Bootstrap de operación por `public.fn_lf_operation_reserve_execution_v1`, igual al patrón oficial de PROMOCION_REGLA_LF, no crea un RPC escritor alterno.
- **Registro gobernado**: operación `ACTUALIZACION_REGLA_SALY` `SANDBOX_ACTIVE/OP_CANDIDATE`; owner SALY `TEMP_DOCUMENTARY_ACTIVE` con UUID interno opaco **no Auth**, recibo SHA-256 de la decisión, `source_execution_id` del Train real; Router `SALY_RULE_UPDATE` `CANDIDATO_READ_ONLY` y `write_allowed=false`; modo `NO_WRITE`; autoridad de perfil `PROPOSED` y `self_update_allowed=false`.
- **Criterio de integración B07**: el preflight de #3818, `B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED` / `B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED`, solo debe pasar tras readback de alta real SALY. No equivale a writer SALY operativo ni concede permisos ni reemplaza aprobación del DDL del dueño.
- **Bloqueo real hasta nuevo RUN nativo**: `B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED` (la fuente está preparada; el perfil no está registrado en la base). Mantener DRAFT, sin `ready-to-merge` y sin Train de #3818.

## Split físico del perfil (PR #3835) — precedencia obligatoria
- Los **24 archivos del perfil SALY** y el procedimiento `ACT-0001 → Gate2 → Issue → OIDC` se movieron al [PR #3835](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3835), **DRAFT**, `profiles/saly_product_director/`. #3832 **no** añade ni modifica archivos del perfil.
- El Issue `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1` crea un RUN `EJECUCION_PERFIL_LF` de perfil ya existente, **no crea un perfil** ni genera `CREACION_PERFIL_LF`.
- El caller nativo `lf-profile-creator-governance-caller-v1` actualmente solo permite perfiles Customer y su runtime marca `production_authorized=true`: **bloqueo de seguridad** para la designación SALY `production_authorized=false`. No inventar un Gate2, no ampliar privilegios ni invocar Edge directo. Procedimiento exacto en #3835, documento 12.
- Para dar paso al Train de **alta de operación/owner** de este PR debe existir primero `CREACION_PERFIL_LF` real `COMPLETED` y fila `lf_activos` de `PERFIL-PRODUCT-DIRECTOR-SALY` asociada al mismo execution_id; el SQL lo exige `B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED`. Crear perfil por INSERT directo está prohibido.
- Hasta #3834 en main + R17 PASS, **cero ejecuciones vivas**. El Train de #3818 sigue sujeto al OK explícito y distinto del dueño sobre DDL de tablas hija.
