# LF_ENGINEERING_CHECKPOINT_MCP_V1 — conector operativo acotado (candidato)

## Estado
**CODE-ONLY / NO INSTALADO / NO ACTIVADO**. Construido para resolver el error
`ERROR 25006 cannot execute UPDATE in a read-only transaction` de M4.11 CP2,
sin modificar los permisos del conector Supabase de consultas.

Este repositorio **no** registra automáticamente un conector nuevo en ChatGPT
ni autoriza una ruta alternativa de escritura. El Router y las políticas Supabase
son autoridad. La regla actual `DB_WRITE_TRANSPORT v2.1.0` dice que los agentes
solo escriben base de datos mediante Merge Train; hasta introducir y admitir
explícitamente el carril **DML operativo no migratorio**, este conector responde
`BLOCK_OPERATIONAL_MCP_INACTIVE_BY_POLICY`.

## Superficie de herramienta

- `engineering_checkpoint_transition(plan_code,unit_code,checkpoint_code,
  new_status,evidence_ref,actor,detail,router_execution_id,dry_run=true)`
- Solo invoca `programacion.fn_engineering_checkpoint_transition_v1`,
  exactamente una vez por transacción autorizada.
- Sin DDL, `execute_sql` arbitrario, `apply_migration`, ni acceso al ledger
  de migraciones. Nunca ejecuta ni sustituye LF Migration Merge Train.
- `dry_run=true`: calcula en transacción y hace ROLLBACK; nunca informa DONE.
- `dry_run=false`: COMMIT después de leer `status` y `evidence_ref` exactos
  dentro de la misma transacción. Si el conector read-only da 25006, falla.

## Frontera de autorización (defensa en profundidad)

Para que una futura instancia hospedada pueda escribir se requieren **todos**:

1. Política activa en Supabase aprobando explícitamente el transporte
   operacional `LF_ENGINEERING_CHECKPOINT_MCP_V1` para checkpoints, **no
   migraciones**. Modificar contrato y gobernanza juntos mediante el Train.
2. Ejecución `ACTUALIZACION_DB_LF` activa, con `target_type=DB`,
   `target_code=programacion.engineering_work_checkpoints`.
3. `manifest.operational_transaction_admission.status=APPROVED`,
   `connector=LF_ENGINEERING_CHECKPOINT_MCP_V1`, `verification=PASS`,
   `plan_code`, `unit_code`, `checkpoint_code`, `new_status` y
   `evidence_ref_sha256` exactamente vinculados. **El conector no genera este
   manifiesto ni la aprobación**; los exige a la autoridad del runtime.
4. Router `lf_router_resolve_v1(...,'UPDATE','DB')` devuelve
   `READY_TO_EXECUTE` y `ACTUALIZACION_DB_LF`.
5. Bootstrap devuelve `CONTINUE_CURRENT_CHECKPOINT`, checkpoint actual
   correcto y `action_spec.status=READY`. Evidencia no vacía.
6. Credencial dedicada de mínimo privilegio para el runtime gobernado (nunca
   la contraseña del conector read-only ni secretos en el repositorio), más
   configuración `LF_ENGINEERING_TX_LANE=GOVERNED_OPERATIONAL_DML` y
   `LF_ENGINEERING_TX_DSN`, inyectada externamente.
7. Instalación por usuario/admin de un servidor MCP remoto con transporte
   HTTPS y autenticación autorizada. El código implementa **STDIO** para
   desarrollo; no publica un endpoint accesible ni configura OAuth.

El valor de la variable de entorno no sustituye la admisión en Supabase.
Si falta cualquier paso, devuelve BLOCKED. No se autoriza apuntar a
producción ni compartir un secreto en chat.

## Pruebas deterministas, sin credenciales

```bash
python sandbox/lf_contract_gate_test/engineering_checkpoint_mcp/test_connector.py
python sandbox/lf_contract_gate_test/engineering_checkpoint_mcp/lf_engineering_checkpoint_mcp.py --self-test
```

El runtime requiere, *solo cuando haya admisión operativa autorizada*:
`mcp` (FastMCP) y `psycopg` 3 instalados en un entorno aislado.

## Prueba y pase requeridos antes de usarlo en M4.11 CP2

1. Admitir un transporte de **transición DML operativa** en el Router/políticas;
   no modificar la ruta de migraciones.
2. Prueba real controlada `BEGIN/ROLLBACK` de caso positivo (evidencia válida)
   y negativos (sin aprobación, evidencia vacía, estado no READY) mediante el
   conector con su credencial dedicada.
3. Probar COMMIT en LF_SUPABASE_SANDBOX sobre una ejecución activa autorizada,
   luego readback del mismo checkpoint y del porcentaje oficial.
4. En M4.11 CP2, vincular `IG_M411_UPSTREAM_READBACK_V1=PASS` y el recibo
   de procedencia 1667. CP3 queda fail-closed hasta independencia T-INDEP.

## EKB considerado

`RTE-001`: write test en read-only. `IG-ENGINEERING-TRANSITION-EMPTY-EVIDENCE-001`:
guard de evidence_ref y control positivo/negativo. 
`IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001`: contrastar contrato/gobernanza/validación.
`IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`: no confundir sandbox con producción.
`CI-DB-WRITE-TRANSPORT-UNMAPPED-FULL-REGRESSION-001`: no crear CI paralelo,
mapear la nueva superficie a controles causales en el eventual pase operativo.
