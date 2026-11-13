# LF · Normalización de owners de `public.lf_activos` — diagnóstico y handoff oficial

**Fecha de inspección:** 2026-11-12 (UTC-5). **Estado:** DIAGNÓSTICO VERIFICADO / CAMBIO NO EJECUTADO / DRAFT-NO-GO.
**Proyecto:** LF - Agente imputs y reglas. **Ámbito:** exclusivamente `public.lf_activos.owner_name`.
**No confundir con:** `lf_ops.reglas` (578 filas) ni los PR #3785/#3786/#3787; NO son objeto de este paquete.

## Decisión del dueño comunicada en solicitud
- Los activos generados por el sistema tendrán owner funcional canónico `LF_GOVERNANCE`. Evitar variantes en los nuevos activos.
- Las aprobaciones de origen MANUAL son competencia humana de Cristhian, acreditada por evidencia vinculada a la acción. La coincidencia de un texto en `owner_name` NO constituye prueba de aprobación.
- `SUPER_ADMIN` es guard de gobernanza y NO tiene autoridad de aprobar ni se convierte en owner automático.
- `ChatGPT` / `OpenAI`: procedencia/autores declarados cuando se pueda acreditar, nunca owner ni aprobador por equivalencia.
- Preservar el autor histórico, execution IDs, estados, raw_payload, metadata y relaciones; no fabricar aprobaciones retroactivas.

## Evidencia viva (SELECT, solo lectura)
| Métrica | Valor |
|---|---:|
| Filas totales | 238 |
| No archivadas | 225 |
| Distintos valores no nulos de owner_name | 13 |
| owner_name = LF_GOVERNANCE | 83 |
| owner_name = Cristhian | 73 |
| owner_name = SUPER_ADMIN | 16 |
| owner_name NULL | 44 |
| Otros valores distintos de los dos candidatos canónicos, incluyendo SUPER_ADMIN | 38 |
| Cambios en simulación de dos destinos (NO AUTORIZA APPLY) | 82 |
| De esos cambios, no archivados | 76 |
| De esos cambios, archivados | 6 |
| Proyección preliminar LF_GOVERNANCE / Cristhian | 164 / 74 |

**Snapshot de pares `id:codigo_activo:owner_name:archived_at` ordenados:** MD5 `bcbb1f78e59a29267b9895c20128822e` (no es hash de fila completa ni recibo de IG).
**Simulación:** `Cristhian` y `Cristhian Lujan` se preservan/mapean a `Cristhian` exclusivamente como candidato manual a verificar; el resto, incluidos NULL, se propone como `LF_GOVERNANCE`. El mapeo NO demuestra procedencia ni aprobación de cada fila. Requiere preflight por código.
**Riesgo material:** 6 activos archivados incluidos en el candidato de cambio. La ruta no debe mutar registros archivados hasta verificar su contrato de inmutabilidad y la autorización del alcance; preservarlos/split en cohortes si el contrato lo exige.

## Diagnóstico de prevención
1. `public.lf_activos.owner_name` existe, permite NULL, no tiene default.
2. Solo hay trigger `trg_lf_activos_timestamp` (BEFORE UPDATE) y `trg_lf_profile_selector_descriptor_invalidate_v1` (AFTER UPDATE de otras columnas); NO hay guard de owner en INSERT/UPDATE.
3. El código GitHub contiene migraciones anteriores con `owner_name='SUPER_ADMIN'`, y otras con `LF_GOVERNANCE`. **No basta con un backfill**: cualquier nuevo insert/update podría reintroducir variantes.
4. No se encontró una tabla específica de registro de propietarios en el catálogo consultado. No inventar un registry paralelo: resolver la autoridad canónica y su persistencia en el contrato de IG/operación existente.
5. El Router ACT-0001 read-only recibió la solicitud en modo DB, pero devolvió `BLOCK_SCOPE_SEMANTICS_UNATTESTED` / `POSITIVE_NEGATIVE_SCOPE_NOT_BOUND`; `operation_code=null`, `operation_ready=false`. Esto NO es un permiso de escritura.
6. `EJECUCION_INPUT_GOVERNANCE_LF` está `SANDBOX_ACTIVE` en catálogo. El documento operativo V1.4 exige ACT-0001 → perfil → RUN → IG (si aplica) → validador/juez → escritor → readback → cierre; no IG paralelo ni INSERT/UPDATE manual.
7. Repo `AGENTS.md` y `CLAUDE.md`: todo DDL/migración debe ir por `ACTUALIZACION_DB_LF` → PR → Merge Train, con autorización y CI exact-head. No ejecutar migrations desde MCP read-only.

## Corte requerido (no ejecutado)
- **Prevención / nuevos activos:** una sola normalización en el escritor autorizado o gate canónico de INSERT, que derive owner de identidad de origen verificada, lo materialice como `LF_GOVERNANCE` en generación sistémica y bloquee/normalice variantes. Para entrada manual, separar aprobación humana de owner; la firma/identidad de Cristhian debe ser verificada por el mecanismo existente, nunca por literal en JSON/SQL. No modificar Router ni crear bypass.
- **Histórico:** operación IG de mantenimiento administrativo, idempotente, transaccional/reversible, solo `owner_name`. Congelar preimagen por ID + hash/filas y mapa explícito sujeto a autoridad. Cada ítem con before/after, source_ref, run_id, autor, razón, veredicto del juez; readback global, root hash, 0 omisiones, rollback en fallo.
- **No alterar:** estados, creación, permisos, políticas, contenidos, historial de aprobación, `created_by_execution_id`, `updated_by_execution_id` salvo que el escritor oficial requiera registrar de forma legítima una nueva ejecución. No homologar `lf_ops.reglas` por esta ruta.
- **Impacto:** revisar SQL en repo que aún compara `owner_name='SUPER_ADMIN'` y reemplazar dependencias de owner por guard autorizado **en un cambio gobernado y probado**, no haciendo sustituciones masivas de texto sin evaluación.
- **Sin interrupción:** usar lotes y transacciones pequeñas si el contrato y los locks lo permiten; los datos no se modifican hasta que exista contrato/pase. No prometer indisponibilidad cero sin medir.

## Criterios de cierre estrictos
- PRE: identidad/scope vinculados, autoridad de Cristhian para aprobaciones manuales demostrada, `SUPER_ADMIN` rechazado como aprobador; EKB y contratos CURRENT; no alteración de archivados sin permiso; backup y rollback.
- CAMBIO: PR con migración clasificada, CI y PASE, PR no DRAFT, `ready-to-merge` y Merge Train oficial; escritor IG para backfill; ninguna escritura SQL directa.
- TEST: intentos de INSERT con owner NULL, SUPER_ADMIN y variantes; alta manual aprobada y denegada; actor SUPER_ADMIN aprobador rechazado; doble apply idempotente; rollback; consumidores existentes.
- POST: 100% de nuevos activos normalizados bajo el contrato, 0 variants/NULL en cohorte alcanzada, before/after por ID + hashes verificables, recibo terminal real, consistencia con pantallas/consumidores, mismo RUN; estado CURRENT.
- Si alguna condición no está acreditada, conservar **NO-GO**. Este documento NO constituye ejecución, promoción, aprobación ni cambio de estado.

## Fuente de lectura
- Supabase SELECT del 12/11/2026: `public.lf_activos`, `information_schema.columns`, `pg_trigger`, `public.lf_router_resolve_v1`, `public.lf_operation_registry`.
- EKB `GOV-TRANSVERSAL-NO-PRODUCT-OWNER-001`, `LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001`.
- `docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md`, `AGENTS.md`, `CLAUDE.md`.
