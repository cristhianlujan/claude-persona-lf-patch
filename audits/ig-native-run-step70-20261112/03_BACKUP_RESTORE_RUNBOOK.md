# LF — Plan de backup, restauración y migración del Supabase actual

**Estado:** PLAN PREPARADO, **BACKUP NO EJECUTADO, RESTORE NO PROBADO**.
**Origen:** `mhwmirqcgxxukpctffuv` (no base final).
**Responsables:** Infra/DBA ejecuta export y restauración; Seguridad custodia accesos; dueño autoriza cambio irreversible; QA/IG verifica readback. **Nunca restaurar sobre la base actual** en la primera prueba.

## 0. Gate anterior a cualquier mutación

1. Identificar proyecto/ambiente, ventana y destinatario; confirmar si este proyecto contiene datos reales.
2. Resolver las herramientas de export y restore permitidas por el plan Supabase; **PITR no se presume habilitado**. Registrar plan y retención real desde Dashboard → Database → Backups.
3. Congelar inventario y capturar el schema actual, funciones, GRANT, RLS, policies, triggers, extensiones y migraciones. Comparar SHA256 preimagen de RPCs críticos del readback.
4. Obtener backup cifrado y manifiesto SHA256 externo al proyecto con custodio, fecha UTC, método, base, conteo, tamaño, ubicación segura y confirmación de lectura. No poner tokens ni contraseñas en GitHub ni en el chat.
5. Si no hay backup verificable o destino aislado, **BLOQUEAR el cambio**.

## 1. Copia con tres planos (no confundirlos)

| Plano | Qué capturar | Evidencia |
|---|---|---|
| Base PostgreSQL | Esquemas `public`, `programacion`, `private`, `lf_ops`, `auth`, `storage`; roles/grants/RLS, extensiones, tablas, datos, procedimientos y migraciones | Export lógico o backup gestionado, SHA256 del archivo, versión Postgres, lista objetos, prueba de lectura |
| Storage | Lista de buckets, objetos y bytes **reales**; exportar contenido de objetos a archivo seguro; comparar hash de cada objeto | Manifiesto bucket/objeto/hash. La base por sí sola no copia los bytes de Storage |
| Configuración y runtime | Edge Functions desplegadas y versiones, código GitHub por commit exacto, JWT/Auth providers, OAuth/correos, webhooks, cron, secretos **solo por nombre y ubicación de custodia** | Inventario firmado, configuración restaurable segura, sin exponer valores de secretos |

**Baseline observada 2026-11-12:** 2,452 registros de `lf_operation_execution`, 8,236 registros de `lf_operation_execution_steps`, 578 reglas `lf_ops.reglas`, 1 bucket / 1 objeto Storage, 1 `auth.users`. Estos números son un punto de referencia, no sustituyen snapshot a la fecha del backup.

## 2. Restauración aislada

1. Crear **otro proyecto Supabase** compatible y vacío, con acceso restringido, sin integraciones externas activas.
2. Restaurar la copia **por el método soportado** para el tipo de backup y versión. Si se usa la función de clonado/restauración a proyecto nuevo, verificar las limitaciones vigentes: normalmente copia la base, no Edge/Storage/configuración externa.
3. Restaurar objetos Storage, registrar hashes y versiones. Reinstalar/recuperar Edge Functions **deshabilitando endpoints de mutación hasta QA** y configuraciones custodiadas; rotar secretos/tokens según Seguridad.
4. Reconciliar `auth.users`, referencias `auth.uid()`, mappings owner, políticas y roles sin suplantar usuarios. **No usar un JWT fabricado** para certificar identidad real.
5. Verificar DDL/RLS/GRANT y SHA256 de definiciones relevantes; comparar cantidades e integridad por tablas/objetos con snapshot del backup (no con cifras históricas congeladas).
6. Hacer pruebas positivas y negativas sobre **RUN nuevos sintéticos del clon**, nunca sobre RUN históricos. Probar OIDC inválido, sesión humana inexistente, owner revocado, scope alterado, Step70 sin evidencia independiente, hash diferente y recibo terminal ausente: todos deben BLOQUEAR.
7. Emitir recibo de restauración con método, hash backup, inventario, discrepancias, RTO medido y pérdida de datos observada; aprobar solo con verificaciones reproducibles.

## 3. Rollback y migración futura

- **Antes de desplegar:** capturar preimagen RAW + SHA256 de cada definición a cambiar y dump/restauración comprobada.
- **Si falla tras despliegue:** detener nuevos writes/colas, conservar logs y recibos, revertir solo por migración oficial compatible con contratos y sin reescribir RUN históricos. Si reversión de esquema implica pérdida, usar clon para reconstrucción y reconciliar con operación autorizada.
- **Migración a base final:** nuevo entorno y ventana separados; no asumir que URL/Auth IDs/secretos/Storage paths se conservan sin pruebas. Obtener reconciliación de counts, hashes, relaciones, migraciones, policies, owner bindings y RUN al corte. Cambio de endpoint solo tras aprobación y canary.
- Definir con dueño/Infra **RPO máximo, RTO máximo y retención**: **PENDIENTES**; no inventar SLA ni prometer PITR.

## 4. Recibo obligatorio (plantilla vacía)

```yaml
project_source: ""
project_restore_target: ""
authorized_change_ref: ""
owner_decision_receipt: ""
backup_method: ""
backup_timestamp_utc: ""
backup_artifact_ref_secure: ""
backup_sha256: ""
storage_manifest_sha256: ""
edge_config_manifest_sha256: ""
postgres_version_source: ""
postgres_version_target: ""
snapshot_counts_hash: ""
restore_start_utc: ""
restore_end_utc: ""
restore_measured_rto_seconds: null
observed_data_loss_seconds: null
schema_digest_match: null
rls_grants_match: null
auth_user_fk_mapping_match: null
storage_object_hashes_match: null
oidc_negative_tests_pass: null
owner_negative_tests_pass: null
step70_negative_tests_pass: null
run_history_untouched_verified: null
readback_evidence_ref: ""
qa_verdict: "NOT_TESTED"
external_approval_ref: ""
```

**Fuentes oficiales:** 
- https://supabase.com/docs/guides/platform/backups
- https://supabase.com/docs/guides/platform/clone-project
- https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
- https://supabase.com/docs/guides/platform/delete-project
