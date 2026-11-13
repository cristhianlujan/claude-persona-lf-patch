# B07 — Diseño PADRE/HIJA (candidato, sin firma)

**Decisión documental del dueño:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA; decisor declarado Cristhian Luján; NO equivale a firma ni identidad humana verificada. SQL NO desplegable.

## Lecturas exactas (fuentes reales)
- [L1] Supabase SELECT pg_class/information_schema/constraints: padres `lf_ops.reglas` (15 columnas, id integer PK, codigo UNIQUE) y `saly.reglas` (18 columnas, id bigint PK, codigo UNIQUE y decision_id FK saly.decisiones). No existen las hijas B07.
- [L2] Supabase SELECT 2026-11-13T11:24:10.886Z: LF 578 filas, 412 VIGENTE y 166 CANDIDATO; SHA256 filas `15caa058184e52db3572bd0884810d0b731703d72e989c9e33dccc59ce983d8f`.
- [L3] Supabase SELECT misma hora: SALY 14 reglas, todas VALIDADO/vigente, SHA256 filas `588bf6b8368eb48ff93ae3edaebf1e80018364c3078a409aeb153836d55256c7`.
- [L4] Supabase SELECT: `public.lf_ig_rule_change_v2` 0 filas, campos `owner_decision_id`, `source_snapshot_sha256`, `candidate_snapshot_sha256`, `finalized_snapshot_sha256`; `public.lf_ig_owner_decision_v2` 0 filas, decisor, fecha, hash y registro documental.
- [L5] Supabase SELECT: `saly.decisiones` 54 filas, referenciables por `saly.reglas.decision_id` pero no guardan todas las versiones de cada regla.
- [L6] Supabase SELECT: `lf_policy_versions` 25 y `lf_functional_versions` 7 registros de otros activos; `lf_ops.modelos_priorizacion_historial` 0. No son historia reutilizable de estas reglas.
- [L7] [Migración V2 de LF #3803](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/8dd64cea361df0d47d787a6899fa2ddb5a0c92fd/supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql), líneas 540–640: `lf_ig_rule_finalize_v2` actualiza la fila LF en sitio, calcula hashes y marca `lf_ig_rule_change_v2` VIGENTE_VERIFIED. No guarda snapshot íntegro por cada cambio ni escribe SALY.
- [L8] EKB [INPUT GOVERNANCE LF V1.4](https://docs.google.com/document/d/1nUFk29HhCl_kCg-W-bwkpyLuwx9gURQNJAGKhhgerTk): Router→perfil→RUN→IG, ruta oficial, no atribuir PASS sin evidencia.
- [L9] [L28 Documento 12 §B07_SCHEMA · G11](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote28-blocker-closure-plan-v1/audits/rule-quality-lote28/12_criterios_cierre_motor_7.md) aún exige 4/5 columnas literal.

**Readback:** no hay hija de versiones de reglas exacta reutilizable. Se pueden reutilizar PADRES y tablas de decisiones/receipts, NO reasignar versiones de políticas/capacidades a reglas.

## Modelo candidato EXACTO (TODOS los elementos nuevos = INFERIDOS)
| Componente | Nombre/clave | Escritura/relación |
|---|---|---|
| Padre LF (existente) | `lf_ops.reglas`, PK `id integer`, `codigo UNIQUE` | Regla actual. Consumidor efectivo filtra `estado=VIGENTE`. Existen 166 CANDIDATO: excepción legado pendiente, no borrar ni promover. [L1,L2] |
| Hija LF (INFERIDO) | `lf_ops.reglas_versiones_b07`, PK `version_id bigint IDENTITY`, FK `rule_id integer → lf_ops.reglas.id` ON DELETE RESTRICT | Snapshot JSONB completo de cada versión en secuencia; solo escritor oficial tras integración [L7]. |
| Padre SALY (existente) | `saly.reglas`, PK `id bigint`, `codigo UNIQUE`, `decision_id → saly.decisiones.id` | Conserva `estado=VALIDADO`, `vigente=true`; nunca traducir VALIDADO→VIGENTE. [L1,L3,L5] |
| Hija SALY (INFERIDO) | `saly.reglas_versiones_b07`, PK `version_id bigint IDENTITY`, FK `rule_id bigint → saly.reglas.id` ON DELETE RESTRICT | Misma historia completa; snapshot conserva `estado`, `vigente`, `decision_id` SALY. [L3,L5] |

**Columnas de CADA hija (propuesta, INFERIDO):** `version_id bigint IDENTITY PK`; `rule_id integer/bigint FK`; `version_no integer >0`; `snapshot jsonb` (fila completa del padre); `snapshot_sha256 text` (SHA256 del JSONB serializado); `previous_sha256 text NULL` (hash de versión anterior); `origin text` (BASELINE_CURRENT_ONLY o GOVERNED_APPEND); `decision_ref text NULL`; `decisor text NULL`; `decision_record_sha256 text NULL`; `decided_at timestamptz NULL`; `writer_execution_id text NULL`; `identity_verified boolean DEFAULT false`; `captured_at timestamptz DEFAULT now()`. Únicos `(rule_id,version_no)` y `(rule_id,snapshot_sha256)`.

**Backfill (INFERIDO):** INSERT SELECT por cada fila de padres: imagen exacta actual, SHA256, versión 1, origin BASELINE_CURRENT_ONLY; `decisor/decision_ref/decided_at=NULL`. Solo rescata **estado actual**: NO reconstruye la historia anterior no disponible. En copia CI, la forma de las tablas viene de metadata, pero los textos de reglas LF y SALY son SINTÉTICOS.

**Escritura (INFERIDO):** escritor oficial LF V2 y futuro SALY deberán hacer UPDATE del PADRE y append HIJA **en la misma transacción**; sin crear una nueva entrada al Router. Función candidata `public.lf_b07_append_version_candidate_v1` security definer con EXECUTE solo service_role, NO está integrada a escritor V2, NO acredita OIDC/humano físico, no es autorización de producción. Exige hash previo, recibo documental LF V2 / decision_id SALY y paquete de evidencia no vacío.

**Invariante (INFERIDO):** triggers de comprobación diferida `DEFERRABLE INITIALLY DEFERRED` verifican en COMMIT `to_jsonb(PADRE) = snapshot` de la última versión de HIJA. Sin append, UPDATE PADRE bloquea. HIJA es append-only: UPDATE/DELETE/TRUNCATE prohibidos. Firma humana no verificada: `identity_verified=false`.

**DOWN (INFERIDO):** si cualquier historia existe, devuelve B07_DOWN_HISTORY_ROWS_PRESENT sin borrar nada, incluso registros baseline. Necesita custodiar/exportar y aprobar otra restauración para revertir después de guardar historia. El rollback transaccional de UP se prueba por separado.

**Riesgos explícitos:** 166 LF CANDIDATO aún viven en padre — la interpretación estricta 'solo vigente' exige plan gobernado de reconciliación sin pérdida; V2 actual actualiza PADRE sin append y quedaría bloqueado si se instalara este candidato sin integrar finalizador. Faltan RLS/ACL/consumidores, permisos exactos de escritor, evaluación E2E y restauración post-datos. **No deploy, B07 abierto.**
