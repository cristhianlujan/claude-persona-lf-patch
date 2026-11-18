# PR-J1 — AUTH-020 RULE_CONTRACT_LEVEL / fuente exacta

## Alcance
PR-J1 reutiliza sin alterar el JSON fuente y la proyección reversible de PR-I #4084. La decisión del dueño permite **pruebas de contrato regla/datos**, no E2E de Spring Boot/Cognito. El SQL extra ensaya transiciones con funciones **solo de fixture**, y nunca crea una cuenta ni envía una clave real. Se documenta `RULE_CONTRACT_LEVEL` y `login_backend_e2e=NOT_TESTED`. No se altera la autoridad del permiso 38, AUTH-018/019, otras reglas, ni protect-main.

| Objeto | Fuente / antes | Candidato / después |
|---|---|---|
| Código | B2B-RULE-AUTH-020 | Mismo |
| Reglas | 579 | 579 |
| Estado | VIGENTE | VIGENTE |
| SHA origen | `8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8` | Sin cambio en PR-J1 |
| MD5 fila | `7588d5a7de4d94a864fca9e63cd10ebe` | `9d558e62bd85cefe6dbe0f4147e59056` proyectado, no aplicado |
| SHA parche JSONB | `adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02` | Exacto |
| SHA candidato | — | `16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061` |
| Campos | hold_hours=48; human_approval_count_required=2; lista fija | Eliminados; TTL referenciado a AUTH/TEMP_KEY_TTL_HOURS |
| Permiso 38 | 0 VIGENTE | Sin modificación persistida |
| Política 20 | CANDIDATO | Sin modificación |

## Pruebas PG17
El workflow `lf-pr-j-auth020-rule-contract.yml` requiere HEAD exacto, SQL PostgreSQL17 real, BEGIN/ROLLBACK, y otra conexión para el readback. Se conservan reporte, logs, SHA-256 de fuente y suite y manifiesto de checks.

| Área | Prueba |
|---|---|
| Operador | Cuenta sin permiso38 efectivo denegada; prueba positiva tras habilitarlo **solo dentro del fixture reversible** |
| DNI | Verificación con referencia segura y rechazo sin verificación |
| Clave temporal | TTL obtenido de tabla global, un solo uso; reemisión revoca anterior |
| Vencimiento | Rechazo de clave vencida y nueva verificación requerida |
| Sesión | No se concede sesión antes de definir contraseña |
| Contraseña | Obligatoria antes de completar; clave temporal solo contexto limitado |
| Correo | Actualización de correo y contraseña en una sentencia atómica del modelo SQL |
| Fallos parciales | Constraint UNIQUE forzada, ambas columnas originales se conservan |
| MFA | Sin MFA: no hay sesión; con MFA y recuperación completa: modelo admite |
| Auditoría | La regla exige eventos y referencia documental, sin secretos ni imagen DNI sin procesar |

**Alcance de los PASS:** reglas/valores declarativos y ejecución del modelo SQL aislado. **NO** afirman que Spring Boot, Cognito, ni el login real cumplan esos comportamientos. Paulo conserva las pruebas de integración y producción.

## Orden gobernado (circularidad PR-H)
1. PR-J1: publicar evidencia reproducible del parche exacto y su Run Train COMPLETED. Su migración únicamente comprueba preimagen, conteos y TTL; no toca AUTH-020 ni inserta recibo protegido.
2. PR-J2 posterior: validar el Run COMPLETED y evento real PR-J1; insertar solo una fila fuente-vinculada en `lf_ig_functional_train_evidence_v1` con hashes del **reporte real de CI**, únicamente por migración privilegiada Train. Sin números fabricados.
3. Crear/admitir RUN de perfil legítimo con Step50 exacto y Step70 independiente, seguido de `lf_ig_rule_owner_decide_v2` y `lf_ig_rule_finalize_v2`. El acceso disponible de Supabase es SELECT-only, por lo que no se suplanta al escritor oficial.
4. Reconciliar política 20 **CANDIDATO** por su vía gobernada y provenance renovada, sin tocar permiso38.

**No promocionar PR-J2 ni emitir decisión V2 si falta recibo REAL del Train/Run.** EKB aplicado: IG-M98-IMMUTABLE-RECEIPT-CYCLE-001 e IG-TOOLS-TRANSIENT-RETRY-STAGNATION-001.
