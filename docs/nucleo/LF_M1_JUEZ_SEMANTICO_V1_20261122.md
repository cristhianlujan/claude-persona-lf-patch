# LF M1 — revisión semántica de seis candidatas (22/11/2026)
Source branch base: `ba0e27990c119524dfcd0675c2aaa03a4d3aa5fd`. Fuentes: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4` sección 10 (juez/persistencia); `lf_ops.nucleo_rubrica` 7 criterios ACTIVOS; seis paquetes `M1-C01..C06` CANDIDATA V1; legadas 155,277,289,13126,229,183,185; decisiones M1-D01..D03 del dueño; EKB focal.
**Procedencia:** revisor GPT-6 en el mismo contexto productor. `modo=CONTEXTO_ACTUAL`, `revisor_es_productor=true`, `llamadas_modelo=0`. No se llamó un juez independiente, no se fabricó un RUN de perfil/step70 ni un receipt; **no equivale al juicio independiente**. La revisión es diagnóstica y cada veredicto es `DEVOLVER`, no `PASS`.
**Rúbrica:** CAL_ACCIONABLE, CAL_ALCANCE, CAL_CLARIDAD, COH_EFECTO, COH_TEXTO_CONDICION, SEM_NO_CONTRADICE y SEM_NO_DUPLICA. Puntajes y observaciones literales por regla en `sandbox/lf_contract_gate_test/nucleo_ci/m1_juicios_semanticos_v1.json`. La migración registra exclusivamente por `lf_ops.nucleo_juicio_registrar_v1` con el hash calculado en la transacción y reevalúa por `lf_ops.nucleo_regla_evaluar_v1`. Sin `nucleo_regla_promover`, sin publicación/deprecación y sin escrituras directas de tablas núcleo.
| Regla | Hallazgo crítico de revisión | Veredicto |
|---|---|---|
| M1-C01 | Booleano no verifica resumen único por oferta y modalidad | DEVOLVER |
| M1-C02 | No cubre aviso UI, solicitud desde Mis operaciones ni ejecución real | DEVOLVER |
| M1-C03 | Falta guard de emisión de recibo: posible bloqueo global de backend; fuente CANDIDATO | DEVOLVER |
| M1-C04 | La certificación sandbox y separación real de credenciales no tienen binding técnico | DEVOLVER |
| M1-C05 | Falta conservación persistida y banner literal de REG_TEC_007 | DEVOLVER |
| M1-C06 | Falta cotejo de identidad/reserva y respuesta previa; borde estricto | DEVOLVER |
**Protecciones de CI:** POSTGRESQL17 aislado; replay de source; control negativo de hash y rúbrica incompleta para cada candidata; prueba BEGIN/ROLLBACK del mismo SQL con readback de tablas antes/después; 17/17 regresiones conjuntas. No certificar pruebas mientras CI no termine.
**Paulo PENDIENTE:** binding de hechos de checkout, emisión de recibos, consentimiento/cancelación, credenciales y pruebas en proveedor, almacenado local offline, soporte de idempotencia y tabla/config de comisiones. **No inventar** tabla, columna ni capacidades Yape. D03 permite descarga en modal. Estas dependencias impiden certificar runtime, pero no impiden registrar honesta revisión semántica del paquete.
**Próximo paso separado:** remediar las candidatas mediante `tipo=REVISION` y hashes optimistas sin publicación; para cualquier juicio independiente, resolver contrato/autoridad real del perfil, no convertir revisión en mismo contexto en independiente.
**Tablero global:** sin aumento hasta criterio de salida certificado.