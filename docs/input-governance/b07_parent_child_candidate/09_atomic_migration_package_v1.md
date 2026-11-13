# B07 — paquete migración oficial VERSIONADO, CANDIDATO (SIN Train)

Ruta: `supabase/migrations/20261113180000_lf_ig_b07_parent_child_atomic_v1.sql`. Prefijo `lf_` clasificado por `lf_migration_source_parity_ci_context.py`; el Train puede retimestamp y hay que releer el nombre final. **No modificar migraciones ya desplegadas.**

Composición: (1) UP padre/hija, (2) hook oficial LF V2, (3) escritor SALY B07; Git blobs respectivamente `d3962191b547d4613198dc68b5d196932a6ab14f`, `aa9f177d4fab048c058c03d8b0bf9ab6d1ac6a90`, `ff6d47c70f42f5fb2ad6f8b132caf278ec16c79d`. Se sustituyen exclusivamente las tres parejas `BEGIN/COMMIT` por **una** pareja exterior y se añade preflight gobernado. Ninguna operación ni owner se registra en este archivo. No tocar RUN históricos.

## Preflight DDL de la migración (fail-closed)
- `B07_GOVERNANCE_CATALOG_MISSING` si falta catálogo.
- `B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED` si operación `ACTUALIZACION_REGLA_SALY` no está `SANDBOX_ACTIVE` y `OP_CANDIDATE`.
- `B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED` si no hay owner SALY `TEMP_DOCUMENTARY_ACTIVE` `UNVERIFIED_CHAT_DECLARATION`, recibo SHA y perfil real de tipo PERFIL en `lf_activos`. Esto es admisión técnica, **no** afirma identidad autenticada ni sustituye decisión explícita del dueño.
- Otros guardas originales B07 y LF/SALY permanecen en SQL. STOP ante cualquier error, sin intentar DML alternativo.

## Suite ligada al archivo oficial
`sandbox/lf_contract_gate_test/edge_function_operation/test_b07_official_atomic_migration_pg17_pg18.py`: PG17.6 y PG18.7 aislados; rechaza ausencia de operación, owner y perfil, luego migración atómica sobre fixture sintético, 578 LF/14 SALY, padre=última hija, contrato SALY, roles y hash padres antes/después. Los tests originales continúan, con rollback y restore posdatos en fixture. **No equiparar PASS CI con restore de backup vivo.**

## Requisitos de aprobación y readback — sin evidencia aún
- Decisión documental B07 #3821 + #3831 en main, `identity_verified=false`.
- Alta SALY oficial separada con readback de operación/owner/Router/Perfil, status y procedencia, sin reutilizar LF. PR #3832 es solo preparatorio.
- Confirmación **nueva y específica** del dueño sobre DDL B07 y la base temporal, distinta de aprobación documental #3831.
- Backup previo de datos/esquema, IDs SHA, WAL/PITR si existe, restauración pre-Train en base aislada y recibo; CI exactos R17/PASE/clasificación/PG17/18 PASS; un solo Train y una migración; no otro Train concurrente.
- SQL readback: `to_regclass` ambas hijas; 578 LF (166 CANDIDATO, 412 VIGENTE), 14 SALY VALIDADO **solo si preimagen coincide**; versiones baseline, hash encadenado, última hija igual padre, RLS/ACL, checksum funciones y recibos; 0 RUN históricos modificados; backup pos-commit con datos restaurado en instancia aislada y SHA iguales.
- DOWN no destruye historia confirmada. Fallas: detener, código, restauración gobernada con custodia, nunca borrar filas.

**HOLD:** No poner `ready-to-merge`, NO quitar DRAFT de #3818 ni ejecutar Train hasta las dependencias y OK explícito del dueño. Paquete preparado ≠ despliegue acreditado.
