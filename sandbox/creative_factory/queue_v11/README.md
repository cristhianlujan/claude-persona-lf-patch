# SALY · V11 bridge V09 → V10 (candidato, no envío)

**Ámbito:** PR #4616 en Draft. Carpeta sandbox/creative_factory/queue_v11. Sin cambio de SKILL oficial, Router, perfiles, Supabase o permisos.

## Contrato implementado

1. El puente lee hash de archive.json, ejecuta el validador V09 existente (archivo, RUN/claim, lease, fuentes y política) y vuelve a leer el manifiesto contra cambios durante el gate.
2. Claim credential se obtiene de un puerto runtime-owned y se compara con order/item/RUN/claim; el token solo se pasa a la RPC V10 y nunca entra al mensaje Native, logs ni resultado.
3. El puerto reserve_dispatch representa la reserva SQL V10 (candidata, aún no desplegada). Requiere status RESERVED_NOT_DISPATCHED o ALREADY_RESERVED_NOT_DISPATCHED y flags de entrega falsos.
4. El puerto reservation_readback lee la fila persistida de forma independiente: comprueba ID, order/item/RUN/claim, modo/proveedor, request key, hash de wire, prompt, archive y snapshot.
5. La respuesta final es RESERVATION_READBACK_VERIFIED_NOT_SENT o IDEMPOTENT_RESERVATION_READBACK_NOT_SENT. Siempre dispatch_authorized=false, native_transmitted=false, provider_attested=false, host_delivery_verified=false y db_done_allowed=false.
6. Un reintento idempotente NO concede un segundo envío. No existe llamada al generador en este módulo.

## Puertos reales pendientes

- DB: clock, policy, binding, render_wire, claim_credential, reserve_dispatch y reservation_readback.
- Native: host propietario de la conversación, despacho con identidad auténtica, artefacto con bytes verificables y readback de mensaje entregado.
- V06 ya define una puerta independiente para QA y evidencia de entrega; V11 no la sustituye.
- No se encontró en las herramientas disponibles en esta conversación un puerto de lectura autenticada del message_id servido al usuario. Esto no prueba que no exista ninguna API en otros entornos; solo que no se verificó aquí.

## Riesgo y evidencia

SQL V10 ofrece unicidad de **reserva**, no exactly-once de un servicio Native fuera de PostgreSQL. Si el efecto externo queda indeterminado, NO reintentar por la sola presencia de una reserva: hace falta reconciliación autenticada del host, sin fabricar un callback.

Test sintético V11: 26 casos sobre funciones y puertos dobles de prueba. El test test_real_v10_ports_pg17.py conecta el puente con la función SQL V10 y hace SELECT auténtico de la reserva en un PG17 desechable; únicamente V09 está simulado en ese test y sigue sin host real. B25/B28 añade dos mutaciones comprobables con aserción precisa. La CI temporal ejecuta además regresión de V08/V09 con sus propias pruebas del repositorio. CI verificada: run #45081493060 sobre SHA 62673ed5ee7bb62381082d65cf944c13440b1d7d: 69/69 Python PASS, 2/2 mutaciones detectadas; puente V11 conectado con la función SQL V10 real en PostgreSQL 17.6 aislado, replay y readback PASS, cero entrega/DONE y fixture restaurado. Registro detallado en ci_results_20261122.txt. El primer intento de CI falló por ruta de importación Python y quedó documentado; fue corregido y reprobado. Un test positivo simulado nunca demuestra host real.

NO MERGE / NO DEPLOY / NO GRANT / NO RENDER / NO FALSE DONE.
