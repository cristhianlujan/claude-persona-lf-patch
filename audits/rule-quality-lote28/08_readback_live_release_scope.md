# L28 — Readback de contratos de liberación (solo SELECT)

**ENMIENDA VIGENTE L28 (SIN FIRMA):** base actual TEMPORAL; grupos Motor **7**, Contenido **5**, Infraestructura final **2**. B13/B14 **fuera del GO técnico del motor temporal**, sin cerrar ni aprobar; detalle vinculante para este plan en `10_decision_base_temporal_migracion_y_rollback.md`. Evidencia de panel B13 aportada por dueño, no leída independientemente. Esta enmienda prevalece sobre todo texto histórico L28 que todavía mencione Motor 9.

**Alcance:** verificar si el requisito «14 bloqueos / 32 firmas» de L21 corresponde a un gate operacional consultable o a una política de dossier; identificar barreras técnicas reales para pase del motor. **Diagnóstico de solo lectura, no aprobación.**

- **Origen:** Supabase actual conectado `https://mhwmirqcgxxukpctffuv.supabase.co` (URL obtenida del conector). Rol SQL `supabase_read_only_user`, database `postgres`. Ningún DML/DDL, RUN, escritura, deploy o modificación de gate.
- **Fecha de consulta:** 2026-11-12, **hora UTC exacta no capturada**; no inventar `as_of` para un snapshot firmado.
- **Fuentes documentales inalteradas:** L21 `02_matriz_bloqueos_produccion.md`, `04_go_no_go_firmable.md`; L28 `07_separacion_motor_contenido.md`.
- **Confianza:** alta en resultados SQL literales capturados de las tablas indicadas; limitada en «ausencia de gate global» por no haber auditado todos los consumidores externos/Edge/GitHub Actions.

## A. Hechos directos del SQL consultado

| Control inspeccionado | Evidencia RAW/resumen literal | Resultado y alcance |
|---|---|---|
| `programacion.contratos`: `INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT` | `contract_revision=1.0`; `estado=defined`; `fail_closed=true`; `requires=[47_FAMILIES_PER_ACTIVE_SCREEN,47_VALIDATOR_PASS,CURRENT_RUN,APPLICABILITY_INVARIANTS,STAGE_HIERARCHY,3_DOWNSTREAM_INTERFACE_CONTRACTS]`; `does_not_require=[ALL_FAMILIES_READY,NO_FUNCTIONAL_BLOCKERS,PRODUCTION_READY]`; `promotion_authorized=false` | **Soporta separación de salud de módulo y preparación funcional.** No acredita GO ni modifica las condiciones técnicas por pantalla/familia/validación. |
| `programacion.contratos`: `INPUT_GOVERNANCE_EXECUTION_CONTRACT` | `contract_revision=1.7`, `estado=defined`, `fail_closed=true`, `human_owner=SUPER_ADMIN`, `promotion_authorized=false` | **Diferencia para B06**: el atributo human_owner sigue marcado SUPER_ADMIN en el contrato consultado, sin comprobar qué actor tiene capacidad efectiva de firma o ejecución. Requiere investigación IAM/owners, no asumir que SUPER_ADMIN pueda aprobar. |
| `public.lf_operation_contracts`: `EJECUCION_INPUT_GOVERNANCE_LF` | `status=ACTIVE_ENFORCEMENT`; `contract_sha=783103f2196c1e49d1460bee239d41b74235be97f3b114ab27366f7c436afbb9`; `required_before_write=[exact_screen_resolved,consumer_authorized,worker_spec_resolved]`; `required_after_write=[governance_status,output_sha256,screen_code,consumer]`; `blocked` contiene `production_promotion` | **No está permitida la promoción productiva por la operación ordinaria de IG.** No se propone eliminar este bloqueo; cualquier liberación técnica debe tener autorización/ruta separada, explícita y gobernada. |
| `public.lf_operation_step_contracts` `EJECUCION_PERFIL_LF` | 11 pasos órdenes `0,10,20,30,40,45,47,50,60,70,80` con `status=ACTIVE_ENFORCEMENT` y evidencias declaradas | Hay contrato de pasos activo; **no es prueba E2E ni recibo terminal**. |
| `programacion.gates` | 50 filas; 0 coincidencias en `configuracion` para expresión `(G15\|14/14\|9/9\|GO.NO.GO)` | No se encontró la regla numérica buscada en ese campo de esas 50 filas. No prueba ausencia en todo sistema. |
| `public.lf_operation_step_contracts` | 659 filas; 0 coincidencias en `pass_condition/block_condition/required_evidence_keys/notes` para `G15.MOTOR\|14 recibos\|32 firmas\|B01_MFA\|B14_RESTORE` | No se encontró allí el checklist L21, sin demostrar ausencia en otros contratos o servicios. |
| `programacion.contratos` / `public.lf_operation_contracts` | 0 coincidencias de texto JSON para `G15.MOTOR,14 recibos,32 firmas,B01_MFA,B14_RESTORE,RELEASE_GOVERNANCE` en los campos especificados | Restringido a esos campos. El JSON `programacion.contratos` no equivale a toda la configuración ni código desplegado. |
| `pg_proc.prosrc` para `public/programacion/lf_ops` | 0 coincidencias para `G15.MOTOR,14 recibos,32 firmas,B01_MFA,B14_RESTORE` | Negativo de búsqueda textual sobre fuente de funciones en esos esquemas; no inspección de lógica indirecta/externa. |

## B. Consultas SELECT reproducibles (sin ejecutar actualizaciones)

```sql
SELECT contrato_codigo, especificacion->>'contract_revision' AS revision,
       especificacion->'requires' AS requires,
       especificacion->'does_not_require' AS does_not_require,
       especificacion->>'promotion_authorized' AS promotion_authorized,
       estado,fail_closed
FROM programacion.contratos
WHERE contrato_codigo='INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT';

SELECT contrato_codigo, especificacion->>'contract_revision' AS revision,
       especificacion->>'human_owner' AS human_owner,
       especificacion->>'promotion_authorized' AS promotion_authorized,
       estado,fail_closed
FROM programacion.contratos
WHERE contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';

SELECT operation_code, status, contract_sha,
       required_before_write,required_after_write,blocked
FROM public.lf_operation_contracts
WHERE operation_code='EJECUCION_INPUT_GOVERNANCE_LF';

SELECT operation_code,step_order,step_id,status,required_evidence_keys
FROM public.lf_operation_step_contracts
WHERE operation_code='EJECUCION_PERFIL_LF'
ORDER BY step_order;

SELECT count(*) total,
 count(*) FILTER(WHERE configuracion::text ~*
 '(G15|14/14|9/9|GO.NO.GO)') AS matching
FROM programacion.gates;

SELECT count(*) total,
 count(*) FILTER(WHERE concat_ws(' ',
 coalesce(pass_condition::text,''),coalesce(block_condition::text,''),
 coalesce(required_evidence_keys::text,''),coalesce(notes,''))
 ~* '(G15.MOTOR|14 recibos|32 firmas|B01_MFA|B14_RESTORE)') AS matching
FROM public.lf_operation_step_contracts;
```

## C. Dictamen restringido

- **OBSERVADO:** el checklist G15 global de 14 recibos/32 firmas existe en el documento L21 y la separación G15-MOTOR de 9 bloques existe en L28.
- **OBSERVADO:** el contrato de salud `INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT` no exige `ALL_FAMILIES_READY` ni `NO_FUNCTIONAL_BLOCKERS`, aunque **sí exige** 47 familias por pantalla activa, Validator y otros controles técnicos; por tanto no se puede «liberar ignorando familias».
- **OBSERVADO:** la operación normal `EJECUCION_INPUT_GOVERNANCE_LF` bloquea `production_promotion` y la especificación IG examinada indica `promotion_authorized=false`.
- **NO DEMOSTRADO:** que G15 L21 sea un gate executable deployed o que haya un release-engine cuyo contrato ya acepte 9/9; tampoco que el ajuste documental L28 se haya promovido a fuente canónica.
- **RIESGO:** confundir los 9 recibos del motor con una autorización de promoción de reglas, MFA, cobro o publicación de Contenido. Se deben preservar fail-closed y segregación por proyecto.

## D. Pendientes y siguiente lote sugerido
1. Identificar **quién y qué contrato** autoriza técnicamente un cambio de estado a motor operable (release técnico IG) sin utilizar la operación ordinaria bloqueada para `production_promotion`.
2. Verificar autoridad real de los owners y sustituibilidad de `SUPER_ADMIN` por actor real (B06+B08), sin escribir ahora.
3. Construir y revisar una especificación de gate `G15-MOTOR` con alcance limitado a liberación técnica IG, firmas válidas Motor, evidencia 9/9 y no publicación de Contenido.
4. Auditar consumer externo: Edge/Actions y path completo de ejecución para probar que el checklist L21 no se evalúa en una capa no consultada.
5. Solicitar operación de cambio oficial solo si se determina que es necesaria, con autorización explícita, preimagen hash, regresión y rollback. **L28 no la ejecuta.**

**RESULTADO:** READBACK_SQL_PARCIAL / **NO-GO**. Evidencia SQL real, **sin recibos firmados ni resultados de producción**.
