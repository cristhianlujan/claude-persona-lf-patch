# PG-00.C3 — Contrato de autoridad del catálogo (candidato, no activado)

**Estado:** `DESIGN_ONLY / NO_GO_RELEASE`. Este documento no sustituye ACT-0001, PASE, Merge Train ni a los contratos de publicación de LF.

## 1. Fronteras de confianza

1. **Fuente versionada (GitHub, solo lectura).** `paulozterra/lf-programming-sandbox:standards/catalog.json` debe extraerse del commit SHA completo obtenido por una consulta autenticada al proveedor GitHub y no del propio JSON candidato. Guardar SHA del commit y digest SHA-256 de **bytes originales**, así como estado y versión. HEAD de un PR no es release; verificar protección/admisión exact-head y autoridad del revisor mediante proveedor, no texto declarativo.
2. **Aprobación (antes del apply).** Separar aprobación del owner, juicio semántico independiente y permisos de release. Recopilar identificador verificable de revisión del proveedor y SHA exacto revisado. Un comentario, `approved_by` en CHG o un recibo JSON enviado por el agente **no** concede autoridad. La validez del mecanismo de aprobación y el paso de borrador a release requieren decisión/contrato formal, todavía pendiente.
3. **Plan de publicación inmutable (antes del apply).** Crear propuesta única que una: source SHA + source file SHA-256, CHG, revisión autenticada, schema y versión de release, payload JSON canónico, digest del payload y ruta/migración exacta. La única transformación permitida por el preflight candidato es `status`; no se permite cambiar reglas, dominios, waivers ni otras claves. La transformación **todavía no está autorizada**, aunque estructuralmente pase pruebas.
4. **Router/Train (aplicación).** Resolver `ACTUALIZACION_DB_LF` con ACT-0001, invocar ruta `MIGRATION_VIA_MERGE_TRAIN`, preparar PR con una migración clasificada, cumplir PASE y checks requeridos exact-head, pasar por cola `ready-to-merge`; el Train asigna la versión, aplica, verifica ledger y hace merge. No ejecutar DML/DDL de publicación por agent, psql, API o SQL Editor. La migración solo puede habilitar un escritor tras aprobar diseño y procedencia; la tabla inicial de #3365 **bloquea INSERT y no acepta todavía ninguna publicación**.
5. **Recibo final (después del apply).** Solo aceptar evidencias obtenidas del Train/canal autorizado: execution ID real, PR, commit de merge, versión aplicada, ledger y lectura de fila exacta, payload digest y checks post-apply. No exigir un recibo final inexistente para autorizar el pre-apply; tampoco declarar PASS por un recibo autodeclarado.

## 2. Máquina de estados propuesta

`SOURCE_DRAFT` → `SOURCE_REVIEWED` → `RELEASE_APPROVED` → `TRAIN_ADMITTED` → `TRAIN_APPLIED_VERIFIED` → `CONSUMABLE_BY_PG`

- Cualquier evidencia incompleta, no vigente, de otro HEAD, replay, cambio de payload o conflicto de versión = `BLOCKED` / `REQUIRES_DECISION`.
- `TRAIN_APPLIED_VERIFIED` se establece **solo después** de comprobar ledger, recibo verificado y readback del catálogo. No inferirlo de un workflow `SUCCESS` de otro repositorio.
- `CONSUMABLE_BY_PG` requiere también contrato de lectura/permiso de runtime y pin exacto; no lo concede automáticamente insertar una fila.

## 3. Admisión y pruebas negativas obligatorias

- Source SHA suministrado por el candidato vs commit verificado por GitHub: rechazo.
- Mismo hash de bytes pero aprobación de otro SHA: rechazo.
- Misma versión semver con contenido distinto: rechazo.
- `catalog_version` más baja / release duplicado: rechazo, sin hacer `UPDATE` ni `DELETE`.
- Catálogo con estado borrador insertado directamente: rechazo (check del store).
- Estado alterado sin decisión explícita de transformación: rechazo.
- Regla pendiente promovida o suprimida, waiver o dominio cambiado: rechazo.
- Evidencia de CI / Train fabricada o proporcionada dentro del candidato: no acreditada.
- Apply fuera del Router y Merge Train: `BLOCK_DB_WRITE_OUTSIDE_MERGE_TRAIN`.
- Replay tras merge con base/HEAD antiguos: rechazo.

## 4. Contratos reales consultados (2026-10-30)

- `CLAUDE.md` en `main`: Router ACT-0001, DB_WRITE_TRANSPORT, migración **una por PR**, Merge Train exclusivo y checks exact-head.
- `sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py`: `select_route()` es ruta agent-facing; `select_transport()` es exclusiva interna del Train. `ACTUALIZACION_DB_LF`.
- `sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_pre_apply_checks_v1.json`: `lf-independent-change-admission`, `ig-runtime-candidate-judge`, `PASE`, `migration-source-parity`.
- PR #3365: schema-only, `PG00_C3_UNTRUSTED_INSERT_FORBIDDEN`; no writers ni releases.
- PR #13: catálogo v0.7.0 aún `BORRADOR_EN_REPO_DE_CALIFICACION`, admisión condicionada.

## 5. Decisiones que NO puede tomar el implementador

- Quién/qué sistema tiene autorización para convertir un catálogo de calificación en release aprobado.
- Contrato firmado o atestado que prueba **aprobación independiente** exact-head.
- Contrato específico para que el Merge Train aplique el payload autorizado (transporte/procedencia), sin habilitar un bypass de triggers.
- Política de versiones monótonas y consumidor PG-01 con accesos mínimos.
- Resolución funcional ADR-012 y presupuestos D17: fuera de C3.

**Criterio de salida de este carril:** preflight negativo reproducible + modelo de autoridad revisado independientemente. No marcar `GO_RELEASE` antes de resolver estas decisiones y pasar Train.
