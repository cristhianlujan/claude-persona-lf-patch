# Lote 27 — Matriz de reglas afectadas por decisiones Q03 / Q04 / Q05

**Criterio:** distinguir **DECISIÓN DEL DUEÑO EN CONVERSACIÓN** (confirmada pero sin firma) de **ESTADO DE REGLA** (VIGENTE/CANDIDATO en fuente) y de **DESPLIEGUE** (NO-GO). Esta matriz es documental; ninguna regla de L25 queda aprobada ni promovida. Sin nuevo SELECT Supabase.

## Q03 — Niubiz único recaudo, tarjeta y Yape

| Código / regla | Estado fuente o propuesta | Impacto de conversación | Gobierno sugerido |
|---|---|---|---|
| `REG_NIU_001` | VIGENTE histórico; **L25-05 CAMBIO PROPUESTO CANDIDATO** | De “principal” a Niubiz único recaudo tarjeta/Yape | `PENDIENTE_APROBACION_PROPUESTA_Y_CONTRATO` |
| `REG_CLIENT_CHECKOUT_CARD_DATA_BOUNDARY_001` | VIGENTE histórico (sin propuesta de cambio L25) | Captura de tarjeta solo en componente controlado por proveedor | `MANTENER_VIGENTE; VALIDACION_PCI_Y_QA_PENDIENTE` |
| `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001` | VIGENTE (L25 G25_08) | Callbacks, evidencias autoritativas y reconciliación, no asumir cobro confirmado sin prueba | `MANTENER_VIGENTE; CALLBACK_NIUBIZ_QA_PENDIENTE` |
| `REG_CHK_CUO_003`, `REG_CHK_011` | CANDIDATO; revisadas **sin cambio** L25-10/L25-12 | Proveedor único no decide recurrencia Yape ni recordatorios | `CANDIDATO_PENDIENTE; NO_PROMOVER_POR_Q03` |
| Ledger Q02 | **Sin ledger acreditado por L22** | Es gate para producción Q03 | `PENDIENTE_PRODUCTO_QA_FUERA_IG` |

La **opción A Q03** es declaración de dueño, no autorización de pago. Antes de producción: contrato Niubiz, callbacks probados, componente seguro para tarjeta, ledger Q02 y **sin credenciales DEMO**.

## Q04 — Estados de cuota, cancelación y autoantigüedad

| Código / regla | Estado fuente o propuesta | Subdecisión confirmada | Gobierno sugerido |
|---|---|---|---|
| `REG_CLIENT_INSTALLMENT_STATUS_025` | **NUEVA PROPUESTA CANDIDATO L25-01** | PENDIENTE, EN_PROCESO, PAGADA, VENCIDA, CANCELADA; sin gracia y corte Lima | `CANDIDATO_NO_INSTALADO` |
| `REG_CLIENT_INSTALLMENT_MIDNIGHT_RECON_025` | **NUEVA PROPUESTA CANDIDATO L25-02** | Reconciliar EN_PROCESO con Niubiz; NO_DETERMINADO conserva estado y escala | `CANDIDATO_NO_INSTALADO; FORMATO_NIUBIZ_PENDIENTE` |
| `REG_CLIENT_INSTALLMENT_RECON_ALERT_025` | **NUEVA PROPUESTA CANDIDATO L25-03** | Excepción con correo a destinatario configurable; sin nombre de cliente ni tarjeta | `CANDIDATO_NO_INSTALADO; CONFIGURACION_ALERTA_PENDIENTE` |
| `REG_CLIENT_INSTALLMENT_CANCELLATION_025` | **NUEVA PROPUESTA CANDIDATO L25-04** | Cuota/plan; EN_PROCESO no se cancela antes de conciliar; VENCIDA sí | `CANDIDATO_NO_INSTALADO` |
| `REG_CLIENT_INSTALLMENT_AUTO_CANCELLATION_025` | **NUEVA PROPUESTA CANDIDATO L25-13** | VENCIDA al cumplir umbral de 12 meses calendario: cancelar impagas del plan, preservar PAGADA, EN_PROCESO a siguiente corrida | `CANDIDATO_NO_INSTALADO; INCOBRABLE_CONTABILIDAD_PENDIENTE` |
| `ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES` | **PARÁMETRO CANDIDATO, NO REGISTRADO** | Valor inicial 12, desde fecha de cuota; pantalla mantenimiento Producto, historial/cambio autorizado/rango válido | `CONFIGURACION_PRODUCTO_PENDIENTE; NO_HARDCODE` |
| `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001` | **VIGENTE** + **L25-06 CAMBIO PROPUESTO CANDIDATO** | `overdue_authority` actual depende de gracia incompatible con decisión sin gracia | `SUCESORA_GOBERNADA_PENDIENTE; NO_EDITAR_VIGENTE` |
| `REG_CHK_CUO_006` | **VIGENTE** + **L25-07 CAMBIO PROPUESTO CANDIDATO** | “en cualquier momento” contradice prohibición EN_PROCESO sin conciliar | `SUCESORA_Y_COPY_REVISADO_PENDIENTES` |
| `REG_CHK_014` | **VIGENTE** + **L25-08 CAMBIO PROPUESTO CANDIDATO** | Mis operaciones: misma excepción para EN_PROCESO; mantener sin penalidad | `SUCESORA_Y_UX_REVISADOS_PENDIENTES` |
| `REG_CLIENT_DEBT_SETTLEMENT_STATUS_001` | **VIGENTE; NO MODIFICADA EN L25** | `states=[ACTIVE_BALANCE,FINAL_PAYMENT_PENDING_CONFIRMATION,SETTLED_CONFIRMED]`; no contiene INCOBRABLE | `REQUIERE_REVISION_SEMANTICA_NEGOCIO_LEGAL_FINANZAS` |
| `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001` | **VIGENTE, REVISADA SIN CAMBIO L25-09** | Recordatorios siguen PENDIENTE; la alerta de excepción es distinta | `NO_CAMBIO` |
| `REG_CHK_CUO_009` | **VIGENTE, REVISADA SIN CAMBIO L25-11** | No adeudo debe seguir regido por deuda efectivamente liquidada, no por cancelación automática INCOBRABLE | `NO_CAMBIO; REVISION_LEGAL` |

**Q04: cuatro subalcances aún abiertos y sólo estos en el registro decisorio:** reintentos de cobro automático; recordatorios; mora; destino contable de deuda INCOBRABLE (Negocio/Legal/Finanzas). El **formato de archivo Niubiz** es una dependencia de implementación no resuelta, **no se trata como quinta decisión pendiente Q04**. Tampoco se define nuevo tratamiento contable ni correo con dirección fija.

## Q05 — Pricing, vigencias, autorización de modificaciones

| Activo / regla vinculada | Estado de lectura | Decisión / riesgo | Gobierno sugerido |
|---|---|---|---|
| Configuración pricing con historial y vigencias | **DECIDIDA EN CONVERSACIÓN, sin tabla nueva en L27** | Una versión por fecha, sin huecos/solapes, prohibido fallback cuando no hay versión vigente | `PRODUCTO_DISeÑO_E_IMPLEMENTACION_PENDIENTE` |
| `REG_PRI_001`, `REG_PRI_002`, `REG_PRI_007` | Referencias de pricing identificadas en lecturas de L25; **sin nuevo SELECT ni SHA por fila aquí** | Precio final desde backend, fórmula/desglose existente debe conciliarse con vigencias/versiones | `INVENTARIO_Y_IMPACTO_POR_PRODUCTO_QA_PENDIENTE` |
| `REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001` | **VIGENTE**, L25 G25_08 SHA de preimagen `753265ddccdba94faa9a23e4b03705f254fffd3355a9131e7633401c2040c35e` | Un plan activado conserva su snapshot ante cambios futuros de pricing | `MANTENER_INVARIANTE_SNAPSHOT` |
| `lf_ops.permisos` (no es regla de negocio) | **45 permisos** en L19/L21; dueño informa **16 resource_type y 0 permisos pricing**; no SELECT nuevo | Actualización desde sistema solo por usuario con permiso explícito en perfil | `PERMISO_PRICING_PENDIENTE_DE_PRODUCTO_Y_OWNERS` |
| Asignaciones `empresa_usuarios_perfiles`, `b2b_user_company_profiles` | **0** en consultas históricas L19/L21 | Ningún permiso efectivo de pricing puede suponerse concedido al usuario | `REGISTRO_OPERATIVO_OWNERS_E_IDENTIDAD_PENDIENTE` |

**Precisión de prueba Q05:** la afirmación de **16 resource_type y ausencia de permiso de pricing** proviene de lo comunicado por el dueño; L27 no tiene SELECT nuevo. El conteo **45** y las **0 asignaciones en tablas examinadas** sí cuentan con SELECT histórico: L19 O2 SHA-256 `0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d`; L21 S21_01 SHA-256 `4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933`. Consultas propuestas **NO EJECUTADAS** en `02_pricing_permission_select_no_ejecutado.sql`. **No presentar como readback nuevo.**

## Evidencia, gobierno y bloqueo final

- Fuente L25: `docs/rule-quality-lote25/01_propuestas_reglas.json` Git blob `d3d1fb7e537e74b17c2d5ba0e993ea7e77e3eac7`, 13 propuestas; L25 G25_02 SHA-256 `d6bd8de4ad5e4ba404e362acac25158db7e5e92030bcbe95a1a040a18defaa8f`.
- Fuente deuda L25 G25_08 SHA-256 `f338ec8eefbc51b7a4e93eb800f48951327cdb6342f9a413190f55bdb24b0c7f`. Fuente de contradicciones L25 G25_06 SHA-256 `ccde80ceaafe4aa2568e204e33220fbad2d0cfc76a9f83a6eadae7508d61660f`.
- Fuente historial de permisos L19 `audits/rule-quality-lote19/04_owners_real_registry.md` Git blob `b3b5fd534f45e36738bdf577443f0ba9433aebe5`.
- `CANDIDATO` del L25 designa **propuesta documental**, no regla oficialmente registrada como candidata ni aceptada. **VIGENTE** referido al estado histórico leído, NO revalidado en L27.
- Regla de decisión conversacional **NO AUTORIZA** implementar tabla de pricing, otorgar permisos, ejecutar reintentos, programar cobranza, emitir alertas reales, editar fuente ni promover.

**Resultado: propuestas CANDIDATO sin adopción; Q03/Q04/Q05 decididas en conversación sin firma; NO-GO / UNVERIFIED.**
