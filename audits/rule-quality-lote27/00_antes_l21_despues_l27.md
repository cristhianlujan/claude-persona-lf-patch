# LOTE 27 — Antes L21 / Después L27: decisiones del dueño

**Sólo registro documental.** Base Git L25 `dce10390aafdbf9a05362fde8b8799055c6b0319`; dossier L21 importado del commit `4c3e376c62a3ae488d1c031ba7043d686919a65d`. No se consultó Supabase, no se ejecutó PG18, no DML/DDL, producción o cambio en gates. Autor/juez: **GPT-6, mismo modelo, no independiente**.

## Comparación explícita

| Control | Antes L21 (documentado) | Después L27 (registrado) | Evidencia / límite |
|---|---|---|---|
| Decisiones totales | 32 | **32** | IDs L16 12 + L19 8 + L21 12, sin agregar filas |
| Decididas en conversación | 0 documentadas como decididas | **3**: L16-Q03, L16-Q04, L16-Q05 | Decisiones literales del dueño en la conversación |
| Recomendadas sin confirmar | Q01 mantenía sugerencia C, estado PENDIENTE | **1**: L16-Q01 `RECOMENDADA_SIN_CONFIRMAR` | No equivale a aceptación de MFA |
| Pendientes estrictos | 32 | **28** | Q02 + L16-Q06..Q12 (7) + L19 (8) + L21 (12) = 28 |
| Decisiones formalmente firmadas | 0/32 | **0/32** | Ningún recibo de firma, identidad o fecha autenticada |
| Q03 | PENDIENTE (se sugería bloqueo B) | **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**, opción **A** | Niubiz único proveedor recaudo tarjeta/Yape; **GO pago aún bloqueado** |
| Q04 | PENDIENTE; se sugería ocultar claims mientras no haya política | **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA** en subdecisiones confirmadas | **Sólo** reintentos automáticos, recordatorios, mora, destino contable de INCOBRABLE abiertos |
| Q05 | PENDIENTE (se sugería B hasta config canónica) | **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**, opción **A** | Pricing versionado sin huecos/solapes, sin fallback, snapshot y permiso por perfil |
| Q02 ledger | PENDIENTE | **PENDIENTE** | Producto/QA construye ledger, fuera de Input Governance |
| Q06–Q12 + L19/L21 | PENDIENTE | **PENDIENTE** | Ninguna selección ni firma inferida |
| Reglas L25 | 13 PROPUESTAS documentales y parámetro CANDIDATO | **Sin adopción ni promoción** | L25 HEAD dce10390; L27 no edita propuestas |
| Tablero L21 de 12 etapas | 15/36 REAL_EN_SANDBOX = **41,7%** | **15/36 = 41,7%** (archivo idéntico) | **No** fingir ejecuciones de L27; pruebas L23 son evidencia externa separada |
| Evidencia E2E nativa productiva en L21 | 0/36 | **0/36** para ese tablero | Indicador de evidencia de los lotes, no funcionalidad global |
| GO / NO-GO L21 | 15 gates NO_VERIFICADO; NO-GO | **15 gates NO_VERIFICADO; NO-GO** (archivo idéntico) | La conversación del dueño no satisface checks de producción |
| Supabase permisos | L19/L21: 45 permisos, 0 asignaciones en tablas inspeccionadas | Valores **históricos**, NO SELECT L27 | L19 O2 SHA256 `0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d`; L21 S21_01 `4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933` |
| Permisos de pricing | No prueba específica en dossier L21 de 16 tipos/sin pricing | Dueño informa **16 resource_type**, **ningún permiso pricing** | **DECLARACIÓN DEL DUEÑO, NO_VERIFICADO POR SELECT L27**; borrador SQL no ejecutado |

**Fórmulas sin inflar:** decididas en conversación = 3/32; recomendada = 1/32; pendientes estrictos = 28/32; firmas = 0/32. **No llamar 3/32 a tasa de aprobación formal.**

## Captura específica Q03 / Q04 / Q05

**L16-Q03, opción A:** Niubiz único proveedor de recaudo para tarjeta y Yape. La decisión no acredita producción. Requisitos para paso a producción indicados por dueño: contrato, callbacks probados, captura de tarjeta **solo en componentes del proveedor**, ledger de Q02 y ausencia de credenciales DEMO. Todos requieren pruebas y readback.

**L16-Q04, subdecisiones:** estados PENDIENTE, EN_PROCESO, PAGADA, VENCIDA, CANCELADA; sin gracia, rechazo por sí solo no vence, corte 00:00 America/Lima; reconciliación Niubiz. Si NO_DETERMINADO, persiste EN_PROCESO, excepción + humano + correo parametrizado, **sin PAN ni nombre cliente**. Cancelación de cuota o plan: EN_PROCESO espera conciliación; VENCIDA cancelable. Cancelación automática por `ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES`, inicial 12 meses calendario desde la fecha de cuota, cancelación del resto impago del plan sin alterar PAGADA, EN_PROCESO se reconcilia y reevalúa próxima corrida, deuda cancelada INCOBRABLE según decisión conversada; configuración mantenida por Producto, fuera de IG. **Restan:** reintentos de cobro automático, recordatorios, mora y destino contable del INCOBRABLE con Negocio/Legal/Finanzas.

**L16-Q05, opción A:** tabla de pricing con historial/fechas de vigencia, una versión efectiva por fecha sin solapes ni huecos; si ninguna vigente, **NO_COTIZAR** (sin fallback a anterior); historial ineditable e imborrable (cerrar/abrir versión), snapshots activados inmutables y cambios de montos desde sistema por actor con permiso de perfil. Permiso pricing específico es dependencia de Producto/registro owners; no asumir que cuenta ya existe o que el permiso se concedió.

**L16-Q01, recomendación C NO CONFIRMADA:** MFA sigue bloqueada por requisitos y AUTH-018 CANDIDATO.

**L16-Q02, PENDIENTE:** no se ha elegido ledger canónico ni ha sido construido por IG; responsabilidad de construcción Producto/QA, fuera de IG.

## Semántica de estados

- `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`: el dueño adoptó el contenido conversacional, **NO** lo firmó, **NO** aprobó la regla CANDIDATO ni autorizó producción.
- `RECOMENDADA_SIN_CONFIRMAR`: el modelo aconsejó opción C pero el dueño no la seleccionó; **NO** licencia de promoción.
- `PENDIENTE`: alternativa o decisión no tomada; un alcance asignado a Producto/QA no convierte Q02 en decidida.
- Firma formal: campos firmante verificado, fecha y recibo **vacíos** para todas las filas. Nadie puede deducir firma de `respuesta_dueno=A`.

## Preservación de fuentes

Se importaron ocho archivos de L21 bajo `audits/rule-quality-lote21/`. Se actualiza sólo portada, registro, CSV y prefacio del manifiesto. **Estos cuatro permanecen con blob idéntico a L21**: `02_matriz_bloqueos_produccion.md`, `03_tablero_12_etapas.md`, `04_go_no_go_firmable.md`, `06_select_evidencia_live.sql`. El SQL copiado es **evidencia histórica**, NO ejecución nueva.

**Dictamen:** conversación capturada / SIN FIRMA / propuestas L25 no adoptadas / **NO-GO / UNVERIFIED**.
