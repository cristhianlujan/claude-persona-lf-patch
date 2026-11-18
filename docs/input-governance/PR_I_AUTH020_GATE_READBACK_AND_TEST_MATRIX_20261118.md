# PR-I — AUTH-020: paquete fuente y evidencia, **bloqueado para merge**

## Estado y ruta obligatoria

**Owner:** decisión de prioridad de 2026-11-18 09:17 America/Lima. **Objetivo:** corregir `B2B-RULE-AUTH-020` mediante `CORRECT_VIGENTE / FUNCTIONAL`, registrando al dueño por usuario conforme PR-G, sin alterar el permiso 38 ni otras reglas.

**Resultado de inspección:** el mecanismo PR-H está aplicado, pero **no hay evidencia técnica real de este parche**, ni RUN `EJECUCION_PERFIL_LF` activo con el Step50 exacto y Step70 independiente. No insertar `lf_ig_owner_decision_v2`, `lf_ig_rule_change_v2` ni actualizar `lf_ops.reglas` mediante SQL de migración como alternativa a V2.

### Delta confirmado antes de escribir

| Cambio | Antes | Candidato PR-I |
|---|---|---|
| `descripcion` | Requiere 2 aprobadores y 48 h | Soporte con un operador permiso 38, DNI foto/escaneo, clave temporal un uso, contraseña nueva, actualización del correo y auditoría; **no menciona 48 h en la descripción** |
| `razon` | L16-Q11 | Registra sustitución de controles históricos y dependencias operativas |
| `valor_config` | 50 campos | 65; 3 eliminados, 10 modificados, 18 añadidos, 37 intactos |
| Eliminados | `hold_hours=48`, `human_approval_count_required=2`, `current_authorized_recovery_profile_ids=[1]` | Ausentes |
| Modos admin/no-admin | `TWO_PERSONS_48H` | `ASSISTED_SUPPORT_DNI_SINGLE_PERMISSION38_OPERATOR_TEMP_KEY` |
| TTL | Parametrización ausente | Referencia `AUTH/TEMP_KEY_TTL_HOURS`, sin literal en `valor_config` |
| `owner_evidence_mode` | Fuente original con declaración chat; en #4080 exigía firma antigua | `USERNAME_ONLY_UNVERIFIED_PR_G` y QA real pendiente |
| `estado`, ID y otras reglas | `VIGENTE`, ID 439 | Sin cambio de identidad o estado |

| Hash | SHA-256/MD5 de PostgreSQL real (SELECT, **proyectados**, no escritura) |
|---|---|
| MD5 actual (excl. `updated_at`) | `7588d5a7de4d94a864fca9e63cd10ebe` |
| SHA-256 origen `REGLA` | `8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8` |
| SHA-256 JSONB #4080 original | `f76d61783e669e82b27508d2a3bb2384ddad95673849da62d69bf04f1ece2cd7` |
| SHA-256 JSONB PR-I normalizado | `adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02` |
| SHA-256 candidato PR-I | `16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061` |
| MD5 candidato PR-I (excl. `updated_at`) | `9d558e62bd85cefe6dbe0f4147e59056` |

La versión de PR-I solo normaliza la descripción y cuatro claves de metadatos antiguos de firma; no cambia la semántica del flujo pedido. El artefacto fuente completa el delta exacto y mantiene traza a #4080.

## Obstáculos reales y decisión de NO-GO

| Gate | Evidencia presente | Resultado |
|---|---|---|
| TTL `AUTH/TEMP_KEY_TTL_HOURS=24` | SELECT: `INTEGER / REAL` | PASS |
| PR-G dueño | `lf_ig_rule_owner_decide_v2`, input `{usuario,veredicto}` | Instalado, pero no invocado sin RUN real |
| RUN del Product Director | Históricos verificados son `COMPLETED` y de otros alcances; falta Step50 con SHA PR-I y juez independiente | **BLOCKED** |
| Evidencia PR-H `lf_ig_functional_train_evidence_v1` | **0 filas**; ninguna para AUTH-020 | **BLOCKED** |
| Train `COMPLETED` con recibo específico de parche | No existe el par comprobado (`source_sha256`, `proposal_sha256`, `candidate_sha256`); ninguno de los recibos de Train contiene AUTH-020 exacto | **BLOCKED** |
| Clave temporal y sesiones en backend real | No se identificó implementación consumidora de estos parámetros en este repositorio; código disponible de autenticación es principalmente gobernanza/edge | **NOT_TESTED** |
| Permiso 38 | Solo `ALLOW/CANDIDATO` de perfil1, 0 VIGENTE | Bloqueo de producción; no cambiar en PR-I |
| Política 20 | `CANDIDATO`, `non_admin_recovery_mode=PENDING_FUNCTIONAL_DEFINITION_EMAIL_ACCESS_RECOVERY` | Reconciliación propuesta, sin actualización hasta el rule gate |

**Circularidad del Train:** PR-H exige que el recibo del Train del parche haya sido ya almacenado en `lf_eventos`, con ejecución `COMPLETED` y hashes específicos. El Train de PR-I **no puede ser su propio Train COMPLETED previo a la aplicación**: su recibo terminal solo se crea tras aplicar/terminar. `owner_decide_v2(APROBAR)` registra decisión y finaliza en la misma transacción, por lo que no se puede aprobar primero y aportar el recibo después. Hacen falta **dos carriles de ejecución secuenciales** (primero evidencia de parche exacto por Train completado, después RUN de perfil y finalización V2); un PR único simultáneo no satisface el contrato actual.

## Matriz de pruebas para el parche de recuperación

| Caso | Criterio de aceptación real | Estado actual |
|---|---|---|
| Solo un operador | El backend autoriza exclusivamente cuenta con permiso38 VIGENTE | **NOT_TESTED**; no hay permiso efectivo |
| DNI foto/escaneo | Registro protegido, actor/hora, verificación de identidad exitosa antes de clave | **NOT_TESTED** |
| Credencial de un uso | Solo primer consumo, token criptográficamente seguro, nunca logueado | **NOT_TESTED** |
| TTL global | Clave vence según `lf_global_config` al cabo de 24 horas; no hardcode | **NOT_TESTED**, config presente |
| Nueva emisión | Revoca todas las claves previas | **NOT_TESTED** |
| Caducidad | Obliga repetir verificación documental | **NOT_TESTED** |
| Contraseña nueva obligatoria | Clave temporal no crea sesión operativa ni concede permisos hasta cambio de contraseña | **NOT_TESTED** |
| Correo actualizado | Cambio de contraseña y correo atómico; rollback en fallo parcial | **NOT_TESTED** |
| Finalización | Acceso normal sin período de espera ni bloqueo; MFA normal sigue aplicando | **NOT_TESTED** |
| Notificación | Contacto anterior notificado solo informativamente; sin veto | **NOT_TESTED** |
| Operador sin permiso | Denegación antes de operar | **NOT_TESTED** |
| Reutilización/vencimiento | Rechazo sin sesión | **NOT_TESTED** |
| Bypass MFA | Denegación del acceso indebido | **NOT_TESTED** |
| Cambios parciales | Ningún correo o contraseña queda comprometido en fallo de transacción | **NOT_TESTED** |
| SQL de proyección | Preimagen exacta, UPDATE sintético, hashes del candidato, configuración de reglas y ROLLBACK PostgreSQL17 con readback independiente | **CI ejecutable en PR-I; NO es prueba del runtime** |

No convertir el test de proyección SQL en `functional_checks_status='PASS'` ni `negative_checks_status='PASS'`: sería un recibo técnico falso para PR-H.

## Política 20: carril permitido, pero no aplicar antes de la regla

`lf_ops.politicas_seguridad.security_policy_id=20` está `CANDIDATO` y no tiene un escritor V2 de reglas; el mecanismo gobernado es `ACTUALIZACION_DB_LF` con Merge Train, preimagen y `programacion.fn_guard_input_parameter_provenance_v1`, **sin firma V2 adicional**. El trigger obliga agregar provenance renovada para cada una de las **20 claves nuevas/cambiadas/eliminadas**. La propuesta exacta de configuración y descripción está en `PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json`; conserva status `CANDIDATO`. No modificar ahora una política de producción que contradiga la regla todavía sin corregir.

## Lote siguiente que realmente desbloquea

1. Identificar/facilitar la implementación auténtica del consumidor de recuperación (Spring Boot/Cognito o repositorio operativo) y ejecutar tests positivos/negativos de backend/sesión; conservar informes y hashes.
2. Usar un **Train ya completado de evidencia específica** para registrar `lf_ig_functional_train_evidence_v1`, con los SHA exactos del JSONB, del estado proyectado y logs; ningún RUN inventado.
3. Iniciar el RUN Product Director legítimo por Router → IG; obtener Step50 con SHA PR-I y Step70 independiente. Invocar registrador PR-G con `usuario='Cristhian Lujan'` y veredicto del dueño, para que el skill hijo y finalizador PR-H apliquen AUTH-020 atómicamente.
4. En operación de datos gobernada y coordinada, reconciliar política20 CANDIDATO con provenance renovada; readback completo de AUTH-018/019/020, permiso38 intacto, 579 reglas y 0 cambios no previstos.

**Alcance ejecutado en PR-I:** paquete de propuesta, preimagen, hashes proyectados y prueba SQL de proyección aislada. **No hay migración de AUTH-020** ni recibo falso, y PR-E #4080 queda DRAFT.
