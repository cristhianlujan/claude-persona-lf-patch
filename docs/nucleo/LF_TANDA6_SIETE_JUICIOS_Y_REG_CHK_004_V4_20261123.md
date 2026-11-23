# Tanda 6 — seis PASS y una DEVOLVER (REG_CHK_004)

Juicio independiente de Claude Sonnet 5.5. Siete criterios y observaciones, versiones y hashes completos en `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda6_v1.json`. Seis veredictos PASS se evalúan y promueven solo si AUTO. `REG_CHK_004 v3` se registra DEVOLVER y jamás se promociona.

## Regla devuelta

V3 presenta como alternativas tres requisitos que deben coexistir. V4 modifica solo descripción. Condición, efecto, título, autoridad, ocho pruebas y aplicación se verifican invariables. V3 queda histórica DESCARTADA; v4 queda CANDIDATA sin juicio propio, se evalúa y no se promueve.

Descripción v4:

> Un intento de checkout ya iniciado mantiene BLOQUEADO el reintento hasta que coexistan obligatoriamente las tres condiciones: (1) un outcome normalizado seguro del intento previo (PAYMENT_DECLINED_CONFIRMED, PAYMENT_NOT_SUBMITTED o PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT), (2) permiso explícito del backend para reintentar la misma operación, y (3) reserva original de operación y quote vigente y válida. Ninguna de estas tres condiciones por sí sola ni en combinación parcial desbloquea el reintento. El backend debe comprobar user_id, quote_status=VALID, expires_at y referencia reservada antes de emitir los hechos. Un timeout ambiguo nunca autoriza segundo cobro. Antes del primer envío esta regla no bloquea el inicio.

## Riesgo pendiente de Paulo

El borde exacto de `AUTH/IDEMPOTENCY_KEY_VALIDITY_MINUTES` (valor REAL 5 en Supabase) para `REG_TEC_009` no está acreditado contra runtime. No se integra ni se fuerza comportamiento real. IG, REG_CHK_007 y legadas intactos; pruebas 17/17 y lectura IG 14/14 exigidas.
