# SALY — Preflight de política y evidencia de entrega V1 (candidato)

**Estado: CÓDIGO LOCAL VERIFICADO, NO INTEGRADO / SIN MERGE / SIN GRANTS / SIN RENDER.**

## Fuentes revisadas antes de programar
- Fuente anclada al proyecto: `LF_resguardos_construccion.md` (B1 esquema primero, B6 procedencia vs calidad, B11 prueba negativa, B13 configuración, B25 error específico y B30 registro no equivale a publicación).
- GitHub `main`: `AGENTS.md`, `CLAUDE.md` (writes solo por ruta Router/PR/PASE/Merge Train), `skills/creative_factory/SKILL.md` v0.12 (`PLAN_ONLY/REVIEW_ONLY`), `sandbox/creative_factory/native_transport_capture_v1.py` (`validate_provider_ack` no disponible).
- SQL live read-only: tabla `saly.config_global` y función `saly.creative_execution_policy_v1`.
- Candidato en PR #4616, `sandbox/creative_factory/queue_v02/001_saly_queue_serial_candidate.sql`.

## Evidencia encontrada
- 25 filas en `saly.config_global`; **ninguna** con `scope='CREATIVE_FACTORY'`. No hay política de cola autorizada hoy.
- La función actual requiere cuatro variables **REAL/INTEGER**: `QUEUE_MAX`, `MAX_ATTEMPTS`, `QUEUE_TIMEOUT_SECONDS`, `LEASE_SECONDS`. Valores no definidos, no fijar números a partir del fixture.
- El transporte Native oficial es solo revisión. Su validador de proveedor falla cerrado con `NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE`.
- El candidato de DB acepta `delivery_channel` y `delivery_receipt` de texto; eso NO prueba por sí solo entrega real de imagen. **No desplegar hasta vincularlo con un adapter/attestor de confianza.**

## Contrato preparado (lectura y verificación únicamente)
1. `check_creative_config(rows, asof)`: valida las cuatro claves y sus versiones desde una lectura autorizada; responde bloqueantes específicos. Aun con fixture válida no concede autorización operativa.
2. `verify_delivered_image(...)`: exige **dos readbacks independientes**, con conectores confiables inyectados por el ejecutor (no por el pedido):
   - Proveedor de imagen: `generation_status=GENERATED` y coincidencia de RUN, claim, ítem, artefacto y hash.
   - Canal de entrega: `delivery_status=DELIVERED`, `message_id` del host y mismas claves, incluyendo superficie destinataria.
   - Lectura binaria del artefacto real para comprobar `sha256` antes de devolver un recibo estructural.
3. Conector de proveedor ausente, host no disponible, correlación distinta o bytes alterados => **rechazo**. La función nunca da `production_authorized=true`.

## Pruebas
- `python3 -m unittest -v test_activation_preflight_v1.py` → **21/21 PASS** local.
- El caso positivo usa dobles de prueba, no constituye evidencia de un proveedor real.

## Bloqueos / siguiente lote
- **Configuración:** falta la decisión y publicación de los cuatro valores operativos mediante ruta gobernada. No inventarlos ni migrarlos desde fixture.
- **Generación:** no existe aún adaptador verificado Native con recibo auténtico y artefacto recuperable.
- **Entrega:** no existe aún API/recibo de host ChatGPT comprobado para certificar un `message_id` mostrado al usuario. No confundir archivo creado con archivo entregado.
- **Integración:** el código es una interfaz candidata, no está conectado a la RPC ni a la skill. Asegurar independencia de los readers y permisos antes de integrar.
- **Gobernanza:** PR/PASE/Train y readback solo tras tests con esquema fiel, sin modificar pedidos existentes.