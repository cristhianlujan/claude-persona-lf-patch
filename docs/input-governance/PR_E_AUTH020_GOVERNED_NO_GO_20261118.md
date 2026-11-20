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

## Ruta real de decisión, impacto y registro V2 — leída del código desplegado

| Orden | Mecanismo | Qué exige, quién lo produce y bloqueo actual |
|---|---|---|
| 0 | Preimagen/alcance | Readback SELECT sobre AUTH-020, política 20, permiso 38 y `lf_global_config`. Resolver en proceso autorizado el SHA **canónico** de regla con `public.lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-020')`; el lector SELECT actual no puede ejecutar la función. No usar MD5 documental como SHA del contrato. |
| 1 | RUN Product Director | Entrar por ACT-0001/Router y producir RUN `EJECUCION_PERFIL_LF`, Product Director, transporte IG y pasos de perfil. Step50 debe contener `deliverable_created.governed_rule_patch` idéntico en JSONB a la propuesta que se revise y fuente exacta. Step60 y Step70 independientes acreditados; jamás simular juez. |
| 2 | Firma del dueño (**falta infraestructura**) | Owner humano real firma fuera del chat una decisión individual, con IAM/IdP y `sub` comprobado, rol LF vigente, nonce de un uso, fecha del servidor, intención explícita y vinculación a **preimage SHA + patch SHA + HEAD + scope**. Registrador nuevo/adaptado conserva firma verificable y readback; **no** equivale a la actual declaración documental. |
| 3 | `public.lf_ig_owner_decision_v2` | Función `lf_ig_rule_owner_decide_v2` requiere seis strings `codigo_regla`, `propuesta_sha256`, `veredicto`, `decisor`, `fecha`, `frase_literal`; RUN padre activo con Step40/60/70 válidos, propuesta Step50 exacta, proponente diferente a decisor y snapshot actual. En éxito crea `decision_id` UUID y fila con `owner_sub`, `decision_record` + SHA, `source_sha256`, `proposal_sha256`, `approved_patch`. **Hoy** el CHECK `identity_mode='UNVERIFIED_CHAT_DECLARATION'` de `lf_ig_owner_decision_v2`, igual al de `lf_ig_project_owner_v2`, y el filtro de la función impiden atribuir firma IAM real; requieren actualización gobernada previa. |
| 4 | Escritor de regla | Tras decisión auténtica **y recibo independiente de impacto preemitido y validable**, `lf_skill_invoke_v1('RULE_UPDATE_APPLY',...)` / `lf_skill_o_rule_update_v2` crea RUN hijo `ACTUALIZACION_REGLA_LF` (7/7 pasos) e inserta `lf_ig_rule_change_v2` con `kind=CORRECT_VIGENTE`, `owner_decision_id` FK, `source_snapshot_sha256`, `approved_patch`, `state=STAGED`. **No** es una promoción de CANDIDATO ni modifica todavía AUTH-020. |
| 5 | Impacto funcional (**falta infraestructura**) | En `lf_ig_rule_finalize_v2` el branch `CORRECT_VIGENTE` rechaza todo `change_kind` distinto de `DOCUMENTARY_ONLY`: `LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING`. El recibo de impacto debe haberse generado **previamente sobre el candidato proyectado en entorno aislado**, estar firmado, source-bound y verificable dentro de la misma llamada atómica al finalizador. No hay emisor/verificador integrado a este gate hoy. |
| 6 | Finalización posterior | Solo después de que exista el gate/recibo y QA, el finalizador aplica el cambio exacto, exige source SHA vigente, registra `finalized_snapshot_sha256`, actualiza estado `VIGENTE_VERIFIED`. Paso80 por bridge oficial y recibo terminal 11/11; readback SELECT sobre regla, política, permiso, parámetro y ausencia de efectos no aprobados. No confundir `VIGENTE_VERIFIED` documental con acceso productivo autorizado. |

### Orden atómico obligatorio de los recibos (evitar un bloqueo oculto)

| Contrato desplegado | Consecuencia para la continuación |
|---|---|
| `lf_ig_rule_owner_decide_v2` con `veredicto='APROBAR'` invoca el skill, crea el cambio `STAGED` y llama a `lf_ig_rule_finalize_v2` **en la misma transacción** | **No** se puede firmar y registrar el `owner_decision_id` ahora, para luego entregar evidencia de impacto en otra llamada: el fallo de finalización revierte también decisión, hijo y `STAGED` |
| Recibo de impacto independiente propuesto | Debe calcularse primero, en ensayo aislado sobre la **proyección** del parche Step50 y la preimagen canónica; incluir SHA de candidato proyectado y quedar disponible al verificador del futuro finalizador |
| Orden permitido después de instalar los dos gates faltantes | Fuente/Step50 + juez real → **evaluación de impacto aislada firmada** → firma autenticada del dueño sobre parche+dependencias+impacto → llamada atómica oficial `owner_decide_v2(APROBAR)` → skill staging + verificador del recibo → finalización → readback |
| Alternativa arquitectónica | Introducir por un cambio de contrato **explícito** y gobernado un proceso bifásico `STAGE → IMPACT → OWNER SIGN → FINALIZE`; no existe hoy y no debe simularse ni implementarse en este PR documental |
| Consecuencia para `candidate_snapshot_sha256` | El campo es NULL en el staging actual de `CORRECT_VIGENTE`; usar SHA de **candidato proyectado** emitido por evaluador aislado y ligarlo al SHA final efectivo o instalar un mecanismo de guardado verificado al cambiar el contrato. No inventar hash de un candidato inexistente |

### Autoridad del dueño: mecanismo actual versus mecanismo requerido

| Campo o control | Estado actual | Condición para usar sin chat |
|---|---|---|
| `lf_ig_owner_decision_v2.decision_id` | UUID generado por `gen_random_uuid()`; FK de `lf_ig_rule_change_v2.owner_decision_id` | Emitir solo desde escritor autorizado, no inventar ni insertar manualmente |
| `identity_mode` | CHECK solamente `UNVERIFIED_CHAT_DECLARATION` | Nuevo contrato admite y valida `VERIFIED_IDP_SIGNED` **como propuesta de diseño, no estado existente** |
| `owner_sub` | Placeholder interno en `lf_ig_project_owner_v2` | Actor real, `sub` verificado, vinculado a rol y proyecto |
| `decision_record` | 6 campos documentales, `decision_record_sha256` del JSONB | Firma/atestación verificada de identidad y consentimiento para los hashes exactos; el SHA documental **no** es una firma |
| Emisor de la firma | Ningún escritor autenticado verificado identificado para la actual función | Interfaz IAM gobernada y registrador oficial con readback inmutable; **firma el dueño, no el agente ni un juez** |

**Frase única de acción humana (PLANTILLA, NO FIRMADA):** «Desde una sesión de identidad verificada, apruebo exclusivamente el parche funcional de B2B-RULE-AUTH-020 y sus dependencias identificados por sus hashes exactos, sujeto al recibo independiente de impacto y las pruebas de seguridad requeridas, sin autorizar producción automáticamente».

### Diseño de recibo funcional independiente — pendiente de implementar, no emitir ahora

| Requisito | Productor propuesto | Prueba que debe quedar ligada al recibo |
|---|---|---|
| Emisor | Revisor independiente de Seguridad/QA, asistido por CI protegido e identificable; separado de proponente, firmante y escritor | Identidad autorizada del revisor, firma verificable, fecha servidor, run/job y commit exact-head |
| Preimagen `source_snapshot_sha256` | Servicio autorizado que invoca snapshot canónico REGLA | Vincular código, id 439, estado VIGENTE y SHA **real** de origen; bloquear drift |
| Propuesta `proposal_sha256` | Paso50 RAW oficial | SHA256 de `governed_rule_patch::jsonb::text` en PostgreSQL, **no hash del archivo**; coincidir con `owner_decision_v2.proposal_sha256` |
| Candidato `candidate_snapshot_sha256` | Evaluador aislado que materializa el estado **proyectado** según semántica real del finalizador | SHA canónico de regla después del parche en transacción de prueba, más delta exacto pre/post; en el V2 actual, este campo es NULL para `CORRECT_VIGENTE` en staging y **no** se genera automáticamente |
| Dependencias | Seguridad/QA/DBA con readback | Política 20 coherente, permiso 38 efectivo, clave TTL global INTEGER/REAL, no regresión de reglas/objetos ajenos |
| Pruebas negativas | Runner independiente PostgreSQL real, BEGIN/ROLLBACK, integración backend/auth y auditoría de funciones | Rechazar operador sin permiso, DNI no verificado, clave reusada, emisión previa, TTL vencido, sesión antes de contraseña nueva, actualización de correo parcial, aviso anterior como veto, pérdida de MFA regular, stale SHA, recibo falso y repetición |
| Aceptación | Verificador de recibo ligado al branch `CORRECT_VIGENTE FUNCTIONAL` del finalizador | Verificar firma, independencia, hash fuente/candidato, checks completos y uso único del recibo; **este verificador NO existe integrado hoy** |

### Política 20 y permiso 38: orden y carril de cambio

| Dependencia | ¿Exige VIGENTE antes de qué? | Mecanismo y límite comprobado |
|---|---|---|
| `lf_ops.perfiles_permisos.permission_id=38` | **Sí, antes de que un operador ejecute una recuperación real**; no es requisito SQL actual para registrar DRAFT | Hoy solo `profile_id=1` tiene `ALLOW/CANDIDATO` y hay 0 asignaciones VIGENTE. Preparar operación de datos gobernada de permisos con autoridad, alcance, preimagen, QA y Merge Train exact-head, **sin conceder acceso a roles nuevos por inferencia**. No se encontró escritor V2 específico de promoción de `perfiles_permisos`. |
| `lf_ops.politicas_seguridad` ID 20 | **Sí, antes de invocar la política como fuente efectiva de runtime**; puede seguir CANDIDATO mientras se diseña y prueba, sin reclamar producto listo | Reconciliar valores admin/non-admin, hacer `parameter_provenance` nueva por cada clave cambiada (trigger obligatorio), revisión Seguridad, preimagen/hash, pruebas PG BEGIN/ROLLBACK y migración `ACTUALIZACION_DB_LF` por Train cuando exista autoridad suficiente. No se encontró escritor V2 específico de promoción de políticas. |
| `B2B-RULE-AUTH-020` | Ya es VIGENTE, no se promueve como regla nueva; se corrige por `CORRECT_VIGENTE` | El writer V2 gobierna solo `lf_ops.reglas`; no puede promover política20, permiso38 ni insertar TTL. No sustituir con SQL directo el gate FUNCTIONAL. |
| `AUTH/TEMP_KEY_TTL_HOURS` | Requerido antes de desplegar consumidor de clave temporal | **Solo propuesta** de fila `AUTH, TEMP_KEY_TTL_HOURS, '24', INTEGER, REAL`, con `valid_from` y `created_at` por default `now()`. Futuro INSERT aislado y autorizado con idempotencia/active version check, CI PG real y SELECT. `REAL` de valor no acredita implementación de clave temporal. |

### Entregable exacto en PR #4080

| Archivo | Naturaleza | Alcance |
|---|---|---|
| `docs/input-governance/PR_E_AUTH020_FUNCTIONAL_PATCH_DRAFT_20261118.json` | **Parche concreto, no aprobado** | `governed_rule_patch.change_kind='FUNCTIONAL'`, `changes.descripcion` literal, `changes.razon` literal y **`changes.valor_config` completo**, derivado del SELECT de 50 claves originales; elimina `hold_hours`, `human_approval_count_required` y lista fija de autorizados; sustituye ambos modos `TWO_PERSONS_48H` por operador con permiso 38; fuente, firma y hashes oficiales pendientes |
| Mismo JSON → `global_config_draft.fields` | **Fila exacta propuesta, NO INSERT** | `scope='AUTH'`, `config_key='TEMP_KEY_TTL_HOURS'`, `config_value='24'`, `value_type='INTEGER'`, `value_status='REAL'`, `description` literal |
| Este documento | Lecturas, gates y continuación | **No hay** SQL ejecutable, writer V2, firma, recibo ni autorización de merge |

**Estado final de este lote:** PR-E continúa DRAFT/NO-GO. El CSV/JSON documental no se debe transportar como `approved_patch` hasta su revisión oficial source-bound, juez independiente, firma IAM y recibo de impacto.
