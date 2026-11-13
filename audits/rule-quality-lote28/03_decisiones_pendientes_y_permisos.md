# Decisiones Q01–Q12 y brechas de control — SIN FIRMA

## ENMIENDA PRIORITARIA L28 — decisión del dueño, PENDIENTE DE FIRMA

**Solo base temporal.** B08 ya no exige verificar identidad humana vía Supabase Auth/JWT/MFA: toda decisión humana se **atribuye documentalmente** a `Cristhian Luján` con `identity_verified=false`, `identity_mode=UNVERIFIED_CHAT_DECLARATION`, frase, fecha, proponente, hashes y readback. No es identidad física comprobada ni firma. IAM humano real queda como requisito al migrar a la base de producción final. **B06**: el owner canónico de activos es `LF_GOVERNANCE` (distinto del decisor humano), guard en PR #3804 y backfill de **155** en PR #3806; ambos sujetos a PR #3803 vía Train. Los tres PR están sin readback de aplicación.

**Migraciones:** decisión solicitada «por Merge Train directamente, sin Router»; **no se debe llamar al Router manualmente antes de enviar una migración**. Se detectó conflicto con la implementación del Train y los PR, que aún exigen `ACTUALIZACION_DB_LF` y `router_authority_receipt`. No crear esos recibos ficticios ni retirar guardas: **reconciliación oficial pendiente**. La entrada ACT-0001 para *perfiles* y el Step70/Step80 EKB no cambian.

**PR #3803:** Train run `43373800126` falló por `LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:EXEC-MIGRATION-LF-IG-LIFECYCLE-V2`; sin apply/merge exitoso. En último HEAD observado `655822a9bdbd1af3796b2ffd7346cc273fa31028` hay bootstrap candidato, pero R17 run `43376438216` FAIL (un SELECT de test mal tipado y replay sin Train RUN exacto); PASE y clasificación PASS. #3804 DRAFT/mergeable=false y #3806 DRAFT/test aislado PASS, no aplicados. **0/7 Motor, 0/5 Contenido y 0/2 Infra final, todos abiertos.** Pruebas exactas y fuentes: `12_criterios_cierre_motor_7.md`; `13_readback_pr3803_3804_3806_train.md`.

**ENMIENDA VIGENTE L28 (SIN FIRMA):** base actual TEMPORAL; grupos Motor **7**, Contenido **5**, Infraestructura final **2**. B13/B14 **fuera del GO técnico del motor temporal**, sin cerrar ni aprobar; detalle vinculante para este plan en `10_decision_base_temporal_migracion_y_rollback.md`. Evidencia de panel B13 aportada por dueño, no leída independientemente. Esta enmienda prevalece sobre todo texto histórico L28 que todavía mencione Motor 9.

**Estado literal para TODAS las filas:** `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`, según entrada del dueño en L28. Significa **preferencia o dirección de diseño conversada**, no aprobación acreditada, contrato productivo ni implementación. Las otras 20 decisiones de L21 permanecen PENDIENTE. En la fuente L21 hay 32/32 sin firmas verificadas. **Las firmas de decisiones de Contenido son registro documental en IG, no gate del GO técnico Motor.** Las decisiones de autoridad y alcance de Motor requieren sus propias firmas auténticas. No actualizar `05_respuestas_dueno.csv` de L21.

| Q | Instrucción conversada (no firmada) | Por definir / acreditar | Bloqueos |
|---|---|---|---|
| Q01 | MFA correo vía Brevo; SMS contingencia; gatillos 30 días sin uso y 3 meses sin cambio de clave | Proveedor SMS, otros gatillos, SAML/IdP admins, factor 19 VIGENTE, AUTH-018, ADR-003, OTP server-side, tests fail-closed; correo ≠ AAL2 probado | B01, B08, B05 |
| Q02 | Ledger `payment` padre + `payment_detail` hija, **solo INSERT**, estado derivado, corrección mediante eventos compensatorios | DDL/versionado, conciliación, esquema de eventos, idempotencia, reversas, contabilidad, negativos | B10, B07, B05 |
| Q03 | Pasarela elegida: Niubiz | Contrato/credenciales productivas, frontera PCI, callbacks autentificados, antifraude, certificación y conciliación | B10, B08 |
| Q04 | Dirección de estados de cuota y cancelación | Reintentos, recordatorios, mora y destino contable del incobrable expresamente **NO_DEFINIDOS**; requiere Producto/Finanzas/Legal | B10, B11, B05 |
| Q05 | Pricing con vigencias | Motor de quote, reglas de elegibilidad, versionado/efectividad, autorización de cambios y QA | B10, B05, B08 |
| Q06 | Documentar contexto de cada par de parámetros; **no igualar valores** | Dictamen literal 20 pares: entidad, operación, evento, alcance, unidad, propiedad, vigencia | B05 |
| Q07 | Familias por dictamen | Firma 15 familias y 23 adscripciones caso a caso, segregación LF/SALY, frecuencias sin 90/60 inventados | B04, B05 |
| Q08 | Pendiente para producción; desarrollo con datos de muestra | Texto legal, consentimiento, fuentes y QA publicables | B11 |
| Q09 | Pendiente para producción; desarrollo con datos de muestra | Claims, visuales, rutas y trazabilidad aprobados | B11 |
| Q10 | Carta de no adeudo: **dos modelos de aliado**, reenvío y pantalla administrativa sujeta a permisos; pendiente para producción, muestras en desarrollo | API/SLA por modelo, entrega, settlement, auditoría, RBAC reenvío y aceptación Legal | B10, B11, B08 |
| Q11 | Recuperación asistida por soporte: documento, **dos personas**, espera **48 h**, aviso al contacto anterior; pendiente para producción y pruebas con muestras | Proveedor/validación IDV, anti-bypass, permisos de aprobación, antifraude, manejo de fallos, base Legal | B01, B10, B11, B08 |
| Q12 | Umbrales como parámetros DB; **5** como valor inicial **de experiencia previa**, pantalla de mantenimiento | Variable/unidad y contexto del 5, calibración con datos, dueño de riesgo, control de acceso, versionado, límites/rollbacks | B05, B10, B08 |

**Q12:** '5' no debe propagarse como umbral universal ni como baseline estadísticamente validado; conservar la procedencia y ligar a un parámetro identificado.

## Cuatro permisos faltantes informados (NO es registro de alta)
Fuente del señalamiento: pedido L28 del dueño. **Sin SELECT de `lf_ops.permisos` en L28**; validar ausencia, IDs, contratos, roles y herencia antes de proponer alta.

| Capacidad/acción que necesita permiso | Dueño de diseño | Brecha de cierre | Pruebas mínimas |
|---|---|---|---|
| Mantener pricing/versiones/vigencias | Producto + IAM/Seguridad | B10, B08 | denegar por defecto, editar solo rol facultado, auditoría before/after y efecto de vigencia |
| Reenviar carta de no adeudo | Operaciones/Producto + IAM/Legal | B10, B11, B08 | reenvío con destinatario permitido, permisos server-side, logs e idempotencia |
| Aprobar recuperación por soporte | Seguridad + Soporte/Operaciones | B01, B10, B08 | **dos identidades distintas**, espera 48 h, notificación previa, no autoaprobación, negativa por bypass |
| Actualizar parámetros de riesgo | Seguridad/Riesgos + IAM | B05, B10, B08 | versionado, scope y límites, trazabilidad actor, rollback, autorización de cambio |

**No inferir códigos, scopes, IDs ni roles:** esos campos deben provenir del inventario y contratos reales. No crear grants nuevos ni asignaciones tácitas. La ausencia no exime políticas o restricciones server-side existentes. Estas cuatro brechas de **Contenido** no impiden por sí solas el GO de Motor, **siempre que** B08/B09 prueben deny-by-default y no queden capacidades de negocio expuestas sin permiso; la falla de aislamiento o auth sí bloquea Motor.

## Separación de trabajo y autoridad
| Capa | Puede preparar en L28 | No puede acreditar por sí sola | Autoridad de cierre futura |
|---|---|---|---|
| **IG/Plataforma** | inventario de contrato, gaps, pruebas planificadas, estructura de recibos | identidad real, firma owner, E2E nativo sin ejecución | IG + Seguridad + dueño en B09; recibos reales |
| **Dueño LF/SALY** | especificar elecciones, dueños, alcance, criterios y límites | efecto técnico, ejecución o autorización de producción por conversación | firma autenticada por decisión y G15 posterior |
| **Producto/QA** | especificaciones, casos de prueba, fixtures etiquetados | PCI, alianzas, legal vigente y producción | dueños de área + artefactos/test readback |
| **Legal** | dictamen documental por versión | ejecución técnica y autorización de GO por sí solo | Legal + dueño en B11 |
| **Seguridad/IAM** | threat model, SAML/IdP, MFA, permisos, identidad | permiso real sin registro y positivos/negativos | recibos IAM + dueño |
| **Operaciones/aliados** | conciliación, inventario RUN, contratos SLA | cerrar/reintentar RUN sin autoridad y reconciliación | recibos por RUN, custodios y dueño |
| **Infra/DBA/proveedor** | backup policy, planes restore/migración | backup/restore real sin pruebas y firmas | custodia DBA/Continuidad + dueño |

## Regla de salida
Ninguna decisión Q01..Q12 se promueve por este paquete. **Contenido (B01/B04/B05/B10/B11):** firma y dictamen quedan como registro documental gobernado por IG y bloquean **solo su propia funcionalidad/promoción**, no GO técnico del Motor. **Motor (B02/B03/B06/B07/B08/B09/B12/B13/B14):** necesita evidencia de cierre, identidad/autoridad y G15-MOTOR antes de una operación de pase gobernada. El contrato técnico compartido y las pruebas fail-closed siguen siendo obligatorios. Toda mutación futura exige versión, impacto, aprobación competente y operación independiente de L28.
