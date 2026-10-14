# M10.5 / R17 — secuencia de despliegue: diagnóstico y contrato objetivo

Estado: **ANÁLISIS / NO ADMITIDO**. Esta rama no autoriza despliegues ni cambia Supabase.

## Evidencia AS-IS (2026-10-14)

- `public.lf_operation_steps`: `r17_preflight` (orden 20), `edge_deploy` (50), `independent_readback` (60), `close` (70).
- El juez en `edge_operation_step_judges_v1.py`, para el paso 20, exige `rollback_drill=PASS`, `idempotency=PASS` y `r17_status=PASS` antes del deploy.
- `edge_deploy_guard_v1.py` reproduce los mismos requisitos cuando `execute=true`.
- Evento Supabase 20890: `provider_deployment_executed=false`, `provider_rollback_drill_executed=false`, `provider_idempotency_drill_executed=false`, `runtime_authorization_present=false`. Live caller v23.
- La operación continúa `OP_CANDIDATE`; no hay operación de despliegue ejecutada. `can_attempt_real_cp2=false`.

## Incompatibilidad

La evidencia de rollback/idempotencia **del proveedor**, exigida antes de desplegar, solo puede producirse mediante operación real sobre el proveedor. Los ensayos locales 20883/20890 no prueban efectos de proveedor; convertirlos en PASS violaría EKB `IG-M105-R17-OFFLINE-VS-PROVIDER-REHEARSAL-016`.

## Contrato objetivo (requiere diseño/validación previa a migración)

1. **PREDEPLOY / sin efecto**: exact source+SHA Git, baseline del Edge live, JWT, scope de un target, dry-run de reversión, tiempos de GET; prohibir promoción, CP2 y escrituras.
2. **AUTHORITY**: autorización efectiva de SUPER_ADMIN ligada a operación, identidad, SHA y target; Operation `OP_OPERATIONAL`, Router write-allowed y effect guard reservado. No inferir autorización de este documento.
3. **PROVIDER EXECUTION**: un despliegue gobernado y recibo inmutable del proveedor.
4. **POSTDEPLOY**: readback independiente de paridad/OIDC/JWT, ausencia de CP2 inesperado; prueba real de idempotencia y ejercicio de rollback gobernado, con restauración del SHA aprobado y readback final. Cada efecto requiere ámbito y autorización propia según la gobernanza vigente.
5. **CLOSE**: juez final solo si TODAS las evidencias anteriores son auténticas, con efecto `SUCCEEDED` y sin promoción implícita.

### Restricción de seguridad

**No modificar solamente el paso 20**: el guard de despliegue reimpone el requisito circular. El cambio necesita alinear conjuntamente contrato SQL, juez, guard, pruebas positivas/negativas y política del Router. Si el ejercicio de rollback exige autorización adicional, cerrar como `PENDING_AUTHORITY`, sin autoaprobar ni simular.

## Matriz mínima de pruebas que debe pasar antes de Train

| Caso | Resultado exigido |
| --- | --- |
| Solo ensayo offline (event 20890) | NO PASS de provider / NO DEPLOY |
| Falta SUPER_ADMIN o Router sigue candidato | BLOCK |
| Predeploy auténtico sin rollback provider (que aún no puede existir) | Puede llegar a evaluación de autoridad; **nunca** autoejecuta |
| Provider deploy sin recibo auténtico | BLOCK |
| OIDC scope mismatch / JWT drift | BLOCK |
| Rollback real no realizado | NO CLOSE |
| Replay sin idempotencia de proveedor | NO CLOSE |
| Con todos los recibos reales independientes | PASS por minijueces existentes |

## Decisión

No admitir migración mientras no exista un transporte de ejecución autorizado que produzca recibos reales de idempotencia/rollback y restore sin ampliar el único target. El error es **circularidad contractual más ausencia de productor real**, no falta de más ensayos offline. Aprobaciones previas de piloto de una pantalla no son autorización de despliegue en producción.
