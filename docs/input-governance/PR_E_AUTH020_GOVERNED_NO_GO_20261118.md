# PR-E — AUTH-020 recuperación asistida: preparación NO-GO

**Estado:** DRAFT · NO-GO / NO MERGE / NO DB WRITE · revisión documental de alcance.
**Decisión declarada por el dueño:** 2026-11-18 01:40 Lima (referencia conversacional; **no** es un recibo V2, firma ni ejecución).
**Objetivo:** aplicar solamente AUTH-020, la política 20 y el parámetro AUTH/TEMP_KEY_TTL_HOURS, pero **no** hacerlo por un UPDATE SQL directo que eluda el escritor oficial de cambios funcionales en VIGENTE.

## Readback actual (SELECT, 2026-11-18)

| Objeto | Estado verificado | Preimagen |
|---|---|---|
| `lf_ops.reglas` id 439 / `B2B-RULE-AUTH-020` | VIGENTE, dos personas, `hold_hours=48`, `human_approval_count_required=2` | `md5((to_jsonb(r)-'updated_at')::text)=7588d5a7de4d94a864fca9e63cd10ebe` |
| `lf_ops.politicas_seguridad` id 20 / `SEC-B2B-MFA-RECOVERY` | CANDIDATO, `non_admin_recovery_mode=PENDING_FUNCTIONAL_DEFINITION_EMAIL_ACCESS_RECOVERY`, admin por Google Workspace legado | `md5((to_jsonb(s)-'updated_at')::text)=97dbf5ff2e9da91da0ab33d6a837d4c2` |
| `lf_ops.perfiles_permisos`, `permission_id=38` | Solo perfil 1, `access_effect=ALLOW`, `status=CANDIDATO`; 0 permisos VIGENTE acreditados | SELECT actual |
| `public.lf_global_config` | Solo `PAGOS/NIUBIZ_EMAIL_GENERICO`, FICTICIO; todavía sin parámetro AUTH | SELECT actual |
| `public.lf_ig_rule_change_v2` para AUTH-020 | 0 recibos | SELECT actual |
| `public.lf_ig_owner_decision_v2` para AUTH-020 | 0 decisiones | SELECT actual |

El lector SELECT no tiene permiso para `public.lf_asset_snapshot_sha_v1('REGLA',...)`; **no** se construyó un SHA oficial sintético ni se declaró un ID de RUN.

## Contrato funcional solicitado de AUTH-020 — aún no aplicado

| Paso | Obligación propuesta |
|---|---|
| 1. Inicio | Solicitud asistida por soporte. Autoriza **una persona**, de cualquier rol con una asignación **efectiva y VIGENTE** de `permission_id=38` en `lf_ops.perfiles_permisos`; no se amplían permisos en este PR. |
| 2. Identidad | Operador comprueba DNI en fotografía o escaneo, registra resultado y evidencia protegida; no se habilita recuperación solo con correo antiguo comprometido. |
| 3. Emisión | Emitir credencial temporal de **un solo uso**, vía servidor, al correo indicado para recuperación. Toda emisión nueva invalida la previa, incluso la no utilizada. |
| 4. Vigencia | Leer `public.lf_global_config(scope='AUTH',config_key='TEMP_KEY_TTL_HOURS')`, `value_type='INTEGER'`, `config_value='24'`, `value_status='REAL'`. La regla no duplica el número ni contiene `hold_hours`. |
| 5. Autenticación transitoria | Credencial válida permite únicamente completar **cambio obligatorio de contraseña**, no sesión ni acceso operativo ni acción funcional. |
| 6. Finalización | Tras definir contraseña nueva válida, actualizar el correo y completar recuperación atómicamente; entonces desaparece cualquier retención por recuperación y procede el acceso normal, con MFA normal cuando aplique. |
| 7. Caducidad | Si vence la credencial sin completar, no se consume ni se habilita acceso; se reinicia comprobación de identidad. |
| 8. Comunicación | Aviso al contacto anterior solo informativo; no constituye veto, hold ni doble aprobación. |
| 9. Auditoría | Registrar actor efectivo autorizado, fecha/hora de servidor, tipo y referencia protegida del documento DNI, resultado IDV manual, emisión/invalidez/consumo, cambio de contraseña/correo y cierre; no registrar secreto temporal ni imagen del DNI en logs abiertos. |
| 10. Protección | Sin contraseña sola, sesión operativa, bypass de MFA normal, factor elegido por cliente o habilitación de producción sin implementación y QA. |

### Campos y texto exactos a reconciliar cuando el escritor oficial admita impacto funcional

| Destino | Cambio funcional requerido |
|---|---|
| `B2B-RULE-AUTH-020.descripcion` | Reemplazar narrativa de dos personas / 48 h por el flujo de 10 pasos anterior. |
| `B2B-RULE-AUTH-020.razon` | Sustituir fundamento L16-Q11 contradictorio; mantener trazabilidad a la nueva declaración de 01:40, **sin atribuir firma verificada**. |
| `B2B-RULE-AUTH-020.valor_config` | Eliminar **las claves** `hold_hours` y `human_approval_count_required`; sustituir ambos `*_recovery_mode` que incorporan TWO_PERSONS_48H. Conservar bloqueos de sesión/contraseña antes de completar. Vincular `permission_id=38` y referencia al parámetro global, no a un literal temporal en la regla. |
| `SEC-B2B-MFA-RECOVERY` id 20 | Unificar recuperación asistida tanto admin como no-admin; retirar la ruta Google Workspace legada y el placeholder `PENDING_FUNCTIONAL_DEFINITION` **solo en el contexto documental**; mantener `status=CANDIDATO` y `production_authorized=false` hasta implementación/QA. |
| `lf_ops.politicas_seguridad.parameter_provenance` | Renovar procedencia **por cada clave cambiada**: el trigger actual exige registro nuevo y rechazará reutilizar provenance antigua. No inventar identidad/sello verificado. |
| `public.lf_global_config` | Añadir **una sola** configuración AUTH/TEMP_KEY_TTL_HOURS = `24` (INTEGER, REAL) en la misma operación autorizada; unicidad por scope+key+valid_from. No insertar otros parámetros. |

## Bloqueos efectivos (no resolver mediante el SQL de migración)

| Gate | Resultado |
|---|---|
| `lf_ig_rule_owner_decide_v2` | Requiere parent RUN Product Director, Step40/60 con evidencia, Step70 `PASS_INDEPENDENT_SEMANTIC`, parche exacto con SHA y declaración de decisión vinculada. No hay recibo actual de AUTH-020. |
| `lf_ig_rule_finalize_v2` | `CORRECT_VIGENTE` con `change_kind=FUNCTIONAL` produce **`LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING`**; no hay mecanismo instalado de aceptación de impacto funcional en este escritor. |
| Permiso 38 | Ningún acceso de soporte VIGENTE acreditado: no atribuir operación a un rol sin autorización real. |
| Política 20 | `CANDIDATO`, requiere provenance actualizada y pruebas de integración; no promover por inferencia. |

**Consecuencia:** esta rama **no contiene migración ejecutable ni llamadas al escritor V2**; queda DRAFT y NO debe recibir `ready-to-merge`. No existe prueba PostgreSQL BEGIN/ROLLBACK del **cambio funcional aplicado** porque el gate lo rechaza; no sustituir con tests de fixture que aparenten producción.

## No alcance — AUTH-018 y AUTH-019

Ambas reglas **permanecen intactas**. Solo reportar sus brechas comparadas con la petición actual. No crear/editar reglas o parámetros MFA, dispositivo, SMS o lockout en este PR.

## Reanudación permitida

1. Instalación gobernada de recibo verificable de impacto funcional en escritor V2, preservando separación independiente y source-bound, y pruebas negativas; **no hacerlo implícitamente en PR-E**.
2. Obtener parent RUN admisible y paquete exacto de AUTH-020 con SHA oficial, evaluación independiente, autoridad y recibos V2; no fabricarlos en una migración.
3. Con gates vigentes acreditados, crear/aplicar la migración **atómica** de dato global y política 20 por el Train normal exact-head, con BEGIN/ROLLBACK real y SELECT posteriores. No usar esta DRAFT como permiso automático de aplicar.
