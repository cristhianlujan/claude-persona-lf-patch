# AM PAYMENTS_CHECKOUT — Paquete técnico para futura aprobación de publicación
Estado: **PREPARADO PARA REVISIÓN; PUBLICACIÓN BLOQUEADA**. Fecha base: 2026-11-21. No constituye solicitud de aprobación inmediata ni habilita publicación.

## Evidencia exacta (Supabase, previo al lote V3)
| Candidata | Versión | Nota/decisión | Hash versión (concurrencia) | Hash paquete evaluado | Alcance | Legada vigente |
|---|---:|---|---|---|---|---|
| REG_CHK_002 | 2 | 100, AUTO | `0d08e6f13b1eefb6188c4a06098ddac4a4641f149f9baa486cb7bfd74498cb19` | `7d796a48bd4576f53ace8cf27718cab2cf9bb5bdda0b9ebb716603c2f274cd67` | CLIENT_PAYMENTS/HEREDA | REG_CHK_002, id 156 |
| REG_TEC_007 | 2 | 100, AUTO | `9ea2a6c14b2b816ae0d0fb599f629d0ed23775bfb293d5cca0d59916314262e5` | `e07786dcea25d66456ff270fc9a6880fd2c0849a16884bd7773b2fa23e1be1a3` | CLIENT_PAYMENTS/HEREDA | REG_TEC_007, id 183 |
| REG_CHK_007 | 1 | 97, AUTO | `e9744cd5013e09e0fa26faefc99094ed880daf7ac7afd7252d05a50614c39057` | `1c09f69a302751f9c54f7538fe634d1fbd99d8a8da5e92d86e7eb1e54f6fe1b7` | CLIENTE/HEREDA | REG_CHK_007, id 211 |

La rúbrica y los juicios están registrados como `CONTEXTO_ACTUAL`, `revisor_es_productor=true`, `llamadas_modelo=0`; **no son certificación independiente**. Pruebas previas: PR #4517/#4533; PASE #4533 44891335735, 17/17, negativo detectado y 17/17 posterior a rollback; lectura de notas y hashes en `lf_ops.nucleo_evaluaciones`/`nucleo_juicios`.

## Efecto real y riesgo de la vista de compatibilidad
Fuente **verificada con** `pg_get_viewdef('lf_ops.v_reglas_compat_v1')`: la primera rama `UNION ALL` entrega las 586 filas de `lf_ops.reglas`, incluidas estas tres legadas VIGENTE. La segunda rama del núcleo excluye todo candidato migrado `origen.tipo=MIGRACION` con `origen.ref LIKE 'lf_ops.reglas/%'`, y también cuando ya hay `old.codigo=n.codigo`. **Publicar por sí solo no hace visible su sustitución en `v_reglas_compat_v1`; antes y después del registro candidato hay 586 filas legadas y 0 diferencias.** Esto tampoco garantiza seguridad si otro consumidor usa `nucleo_reglas_efectivas_v1` y un lector legacy simultáneamente. Asignar FK prematuramente tampoco sirve como mecanismo de cutover: se probó el peligro (EKB coexistencia, PR #4524). No cambiar FK, vista, escritores ni lectores en este paquete.

## Prerrequisitos verificables por candidata (no cumplidos hoy)
1. **REG_CHK_002 (100 AUTO):** contrato y binding real de `checkout_items[].monto_total`, selección/quote snapshot por oferta, cotejo con `lf_proto.checkout_pricing_quotes.offers_subtotal_today` y sus ítems reales; tests multi-oferta, cuotas, pago único, montos cero y no duplicación. La legada 156 es `es_transversal=true` y la V2 aplica solo a CLIENT_PAYMENTS: mapear uso externo a checkout y demostrar que ningún consumidor pierde esa regla. No resolver ni cambiar la comisión LF.
2. **REG_TEC_007 (100 AUTO):** conectar `checkout_en_confirmacion` y `conexion_disponible` con detector real en UI; probar desconexión **antes** del envío versus **después** de posible envío con `PAYMENT_PENDING_CONFIRMATION` autoritativo, sin doble cobro. La legada 183 incluye también guardado local/banner del onboarding: demostrar cobertura de esa porción antes de cortar legado o conservarla explícitamente con código/alcance propio.
3. **REG_CHK_007 (97 AUTO):** actualmente `CLIENTE/HEREDA`, aunque la conducta pertenece a confirmación checkout. Requiere revisión de alcance por puerta canónica (`REVISION`, nuevo hash, pruebas, nuevo juicio), binding de pantalla/estado `checkout_en_confirmacion`, bloqueo efectivo de mutación de selección y snapshot firmado/selección inmutable; probar salida/retroceso y reintento. No publicar la V1 AUTO de alcance demasiado amplio.

## Puerta común de aprobación/publicación — bloquear hasta verificación
- Revisar fuentes y EKB; separar calidad semántica de implementación. Acreditar juez independiente o dejar constancia explícita de que no lo hubo; la nota AUTO no es aprobación del dueño.
- Verificar autoridad, hash de paquete actual, pruebas negativas por condición y alcance, config activa, equivalencia con legadas y dependencias; demostrar consumidores/lectores reales, su contrato de salida y cobertura (F4 todavía incompleto).
- Diseñar y **probar** cutover atómico por familia en copia PG17 y transacción ROLLBACK, incluyendo cambios a vista/FK/consumidores **solo después de nueva autorización expresa del dueño**; prueba antes/después con SELECT, integridad de las 586 fuentes, no duplicados ni omisiones, reversión sin pérdida; no retirar regla legada sin esa aprobación.
- Validar implementación en código CI, trazabilidad `regla+version`, monitoreo, ruta reversible (F5 no acreditada), evidencia de QA funcional del flujo de pago. Conservar los estados CANDIDATA y legados actuales hasta completar.
- Revalidar en Supabase con SELECT las tres versiones, notas, hashes de paquete, estado y paridad de vista. Luego **presentar** al dueño un corte concreto que identifique legado por ID y cambio exacto a aprobar. Sin aprobación no invocar `nucleo_version_publicar_v1`, aun si AUTO lo permitiera técnicamente.

## Evidencia y límites del paquete
- Fuente actual: PR #4533 (migración `20261121094400`) y hallazgo EKB resuelto PR #4532.
- Plan AM exige criterios de migración de familia completos; las tres AUTO por sí solas no cierran el criterio.
- REG_CHK_006 (comisión) y REG_CHK_CUO_003 (Yape cuotas) excluidas. No se decide `acepta_yape_en_cuotas` ni visibilidad/cobro de comisión.
- **Resultado de este documento: propuesta y checklist. Ejecución de publicación: 0.**
