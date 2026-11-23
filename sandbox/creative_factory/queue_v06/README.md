# SALY Creative Factory · Queue V06 · Entrega autenticada y cierre

**Estado:** CANDIDATO, solo sandbox PR #4616. No GRANT, no migración desplegada, no entrega Native real.

## Defecto hallado (fuente de verdad: queue_v02)

`saly.creative_queue_record_delivery_v1(p_token,p_run_id,p_channel,p_delivery_receipt)` admitía `p_channel/p_delivery_receipt` **texto elegido por el worker**. El posterior `creative_queue_release_v1(...,'DONE')` aceptaba esa fila como evidencia. Los checks de RUN, QA, hash y claim no prueban que el chat haya mostrado la imagen. **No se debe permitir que un recibo sintético cierre un pedido.**

## Corrección V06

- `record_delivery_v1(uuid,bigint,text,text)` conserva firma por compatibilidad pero rechaza **incondicionalmente** con `CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN`. En SQL nuevo no existe camino `DONE` a través de `creative_queue_delivery_receipts_v1`.
- Tabla privada `creative_queue_native_delivery_evidence_v1`: identidad única de `claim_id` y `run_id`, `order_id/item_id`, artefacto y hash, `host_surface` y `message_id` únicos, modo Native, referencia y SHA de evidencia de host. **STAGED por defecto**.
- `STAGED → VERIFIED` exige `verifier_ref` distinto de worker, `verified_at`, QA/ítem `APROBADO`, RUN `EXITOSO`, claim `ACTIVE` y vigente, mismos `artifact_ref/sha256`. La fila se vuelve inmutable tras promoción. Esto verifica **forma y vínculo**, no autenticidad criptográfica de host.
- `creative_queue_release_v1(...,'DONE')` mantiene el resto de comprobaciones V02 y **exige además** evidencia `VERIFIED` vinculada a la misma tupla (RUN, claim, ítem, pedido, artefacto, SHA), con verificador distinto. **Un registro STAGED y el ledger textual antiguo nunca satisfacen DONE.**
- `REVOKE ALL` sobre tabla, trigger, RPC textual y release para `PUBLIC`, `anon`, `authenticated`, `service_role` y rol RO si existe. **No GRANT** a ningún runtime. No existe RPC público ni secreto compartido para auto-marcar VERIFIED.
- La prueba con verificador sintético está limitada al owner de la base PG17 descartable. Nunca sustituye prueba real de ChatGPT/Claude, no autoriza servicio, no verifica firmas OIDC ni confirma imagen mostrada.

## Aún falta para operar

1. Host Native de la **misma conversación** debe proveer lectura confiable del mensaje entregado, destinatario y hash de imagen realmente mostrado; `GPT_NATIVE` y `CLAUDE_NATIVE` no implican por sí solos callbacks atestados. Cuando el host no provea confirmación, conservar `STAGED/NO_HOST_READBACK`, no `DONE`.
2. Diseñar un **único** adaptador autenticado de promoción de STAGED a VERIFIED, aislado del worker de generación, con identidad verificada del host (OIDC/servicio permitido), prueba de bytes y mensajes, replay/idempotencia. El SQL por sí mismo solo valida vínculos y ACL, no certifica un host.
3. Valores reales de `CREATIVE_FACTORY`: siguen sin registrar, no utilizar cifras de tests. SQL V02/V05 sin desplegar; no mutar 2 pedidos existentes.
4. PG17 contra esquema completo (el fixture V02 es una réplica selectiva), competencia real de 2 workers B7, comportamiento con cancelaciones, rotación de claves, pruebas con archivos reales, QA separado de procedencia B6, PASE y Merge Train de a uno.
5. El ciclo humano de aprobación de imagen **no** está incluido: pedido termina automáticamente solo después de entrega verificable y QA interno, según decisión vigente.

## Pruebas

```bash
PGHOST=127.0.0.1 PGUSER=postgres PGDATABASE=saly_queue_test \
  bash sandbox/creative_factory/queue_v06/test_pg17.sh
```

Ejecutor aislado crea fixture, corre regresión V02, aplica V06, ejecuta prueba de resultado:
- negativa de RPC textual, ledger antiguo, vínculo claim incorrecto, STAGED no da DONE, verificación por mismo worker, mutación STAGED, modificación/borrado VERIFIED;
- positivo **solo sintético** con inserción de host simulada por dueño del PG17 desechable y QA independiente, para probar que el ciclo puede terminar sin aprobación humana adicional;
- dos mutantes SQL B25/B28: retirar puerta VERIFIED y retirar bloqueo textual. Cuentan solo si falla **la aserción esperada**, no el parser. El runner restaura código original y valida rollback.

**Resultado real PG17.6:** regresión V02 **39 PASS**, V06 **8 rechazos por código exacto**, prueba positiva **simulada** del ciclo STAGED → VERIFIED → DONE (sin cerrar pedidos incompletos), **2/2 mutantes muertos por aserción comportamental** y ROLLBACK. [Acción 45069397026](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45069397026), SHA probado `ba32558887c04266a5405d96319916758493536d`. Evidencia en `pg17_results.txt`. El primer intento falló en SQL por sustitución defectuosa de texto, corregida y probada de nuevo. PASE del HEAD final debe leerse **después** de retirar el workflow temporal, sin ampliar la allowlist.
