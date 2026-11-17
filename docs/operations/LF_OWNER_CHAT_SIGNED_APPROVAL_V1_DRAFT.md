# LF_OWNER_CHAT_SIGNED_APPROVAL_V1 — DRAFT / FAIL-CLOSED

## Mandato 2026-11-16 18:54 Lima

El dueño decidió que el CHAT sea canal humano final de aprobación de promociones de reglas y PRs de gobernanza. Un clic en GitHub no debe ser la aprobación final. El texto actual demuestra intención expresada, no un evento del proveedor autenticado criptográficamente.

Estado: CANDIDATO SOURCE-ONLY. PROHIBIDO fusionar, activar, promover, ampliar permisos, saltar Merge Train o declarar operativa esta vía hasta disponer de mensaje humano original autenticado y firmado por el proveedor. El modelo no puede emitir, firmar ni completar el recibo.

## Reutilizar HUMAN_DECISION_ROUTING (no ruta paralela)

Proponente -> alcance y snapshot congelados -> solicitud HUMAN_DECISION_ROUTING
-> ingreso de mensaje humano de primera parte autenticado y firmado FUERA del modelo
-> verificador Ed25519 scripts/lf_owner_chat_event_v1.py
-> programacion.provenance_receipts (adaptador autenticado: PENDIENTE)
-> private.fn_lf_human_decision_record_verified_v1
-> private.lf_human_decision_receipts_v1
-> private.fn_lf_owner_chat_consume_v1 (consumo único, caducidad y revocación)
-> gate de promoción o Merge Train.

Se conserva private.fn_lf_human_decision_assert_authority_receipt_v1, políticas de autoridad y recibos canónicos. SELECT 2026-11-16: solicitudes humanas genéricas=0; políticas de emisor activas=0. El entorno no ofrece una firma de mensaje original de ChatGPT. No existe aún un recibo real aceptable.

## Evento firmado; identidad y trazabilidad

El servicio emisor independiente del LLM debe leer el mensaje ORIGINAL con identidad de cuenta autenticada; nunca firmará texto o JSON presentado por el asistente. Campos obligatorios:
- version LF_OWNER_CHAT_SIGNED_MESSAGE_V1; event_type USER_MESSAGE; source_platform CHATGPT; issuer_kind TRUSTED_FIRST_PARTY_INGRESS;
- actor_subject de cuenta autenticada, fijado en configuración protegida (un nombre visible NO es identidad);
- conversation_id, message_id único, challenge_id, literal_text, sent_at y expires_at;
- scope exacto fijado por API de PR HEAD vigente o fuente de BD y NO por el modelo;
- firma Ed25519 separada sobre bytes originales, payload_b64, signature_b64, key_id.

El trust store externo configura huella de clave pública y owner subject. El verificador retorna SHA256 de texto literal, mensaje firmado y alcance; fecha, emisor, mensaje y firma. No se almacena clave privada ni texto literal en el latch de un solo uso. Emisión válida no equivale a consumo.

El backend entrega en el propio chat un challenge inmutable de alcance cerrado; el dueño responde en chat APRUEBO LF-<challenge> o AUTORIZO LF-<challenge>. Ese mensaje debe estar firmado y unido al challenge por proveedor. No se acepta autorreferencia, mensaje generado por agente ni "Ok" sin binding demostrable. Esto NO obliga clic en GitHub.

## Dos scopes independientes, exactos y no ampliables

MERGE_GOVERNANCE_PR:
 action, repository, pr_number, head_sha exacto. Si el Train sincroniza/retimestamp y HEAD cambia, exigir nueva orden para el HEAD nuevo.

PROMOTE_RULE_BATCH:
 action, repository, pr_number, head_sha, execution_id, rule_codes ordenados y únicos, rule_snapshots_sha256. Sin expansión ni selección por nombre, con transacción única para todas las reglas y readback APPLIED. Es promoción de DEFINICIÓN, NO GO de producción.

Vigencia máxima: 15 minutos después del mensaje original. Un solo uso por message_id, request_id y receipt SHA. Cancelación/revocación por otro evento humano firmado mediante tabla private.lf_owner_chat_revocations_v1, antes del consumo.

## Gates y cambios de cutover necesarios — NO IMPLEMENTADOS EN ESTE PR

1. Ingreso: crear integración OFICIAL del proveedor de ChatGPT que entregue evento usuario autenticado y firma. Ningún conector actual entrega ese recibo. Hasta entonces FAIL-CLOSED. Nada de model-supplied verified=true.
2. decide_v1 HUMAN: exigir recibo chat ya consumido, con lote/ejecución/snapshots exactos; no aceptar sólo HUMAN:<nombre>. Wrapper genérico debe consumir una vez y llamar request_v1 -> decide_v1 -> apply_v1 de cada regla en la MISMA transacción, abortar al primer error y comparar readbacks. AUTO_SCORE_V1 permanece idéntico. No GRANT nuevos.
3. Merge Train: tras sincronizar PR y verificar HEAD exacto y CI, antes de cualquier real_apply/merge, verificar y consumir un recibo MERGE_GOVERNANCE_PR. El trigger del Train puede ser solicitado desde el chat sin clic, pero sólo tras verificar evento real. Mantener locks, admisión, PASE, source parity, branch protections, ruta de Train; ningún merge directo.
4. PASE: verificar tests y wiring de plataforma; PASE PASS NO ES decisión humana. Si falta recibo real el Merge Gate bloquea aunque CI sea verde.
5. Revocación: evento firmado por el mismo owner, antes del consumo, marca receipt SHA revocado. Replay prohibido.

## Snippet de integración en workflow protegido (diseño, NO operativo)

En el archivo actual .github/workflows/lf-migration-merge-train.yml, del checkout main confiable, en el punto posterior a sync/rechecks y anterior a real_apply, ejecutar como paso:

    - name: Require authenticated owner chat decision
      env:
        LF_CHAT_TRUSTED_SIGNER_PUBLIC_KEY_PEM: from protected runner setting
        LF_CHAT_TRUSTED_SIGNER_PUBLIC_KEY_SHA256: from protected runner setting
        LF_CHAT_TRUSTED_OWNER_SUBJECT: from protected runner setting
        LF_CHAT_TRUSTED_KID: from protected runner setting
      run: |
        python3 scripts/lf_owner_chat_gate_ci_v1.py \
          --event-json "$TRUSTED_PROVIDER_MESSAGE_EVENT" \
          --expected-scope-json "$SERVER_RESOLVED_EXACT_HEAD_SCOPE" \
          --out-json "$RUNNER_TEMP/verified-chat-owner.json"

El runner protegido debe resolver expected_scope desde el PR/BD, no confiar en payload del evento ni en archivos del PR. La siguiente operación, todavía no implementada, debe registrar la procedencia firmada por escritor oficial, crear el recibo del HUMAN_DECISION_ROUTING y consumirlo atómicamente dentro del Train. Nunca transferir secret/private key a un prompt. No instalar el snippet antes de la integración del emisor.

La migración candidata añade solamente tablas/funcción de consumo y revocación sin grants. No cambia decide_v1, Train, PASE ni las funciones históricas protegidas. Es intencional: activar sin emisor real bloquearía todo el Train; aceptar string arbitrario sería autoaprobación.

## Coexistencia con PR #4061

El PR #4061 sigue DRAFT con 22 reglas P51 60 MANUAL. No se modifica en este PR. Cadenas HUMAN:Cristhian Lujan y citas textuales previas no son firmas del proveedor; no pueden elevarse retroactivamente. Tras disponer de emisor real, se debe preparar challenge NUEVO con #4061 HEAD exacto, la lista cerrada de 22, RUN autorizado y SHA de snapshots; recibir aprobación firmada por chat, consumirla dentro de wrapper oficial y pasar por Train. Una aprobación de merge distinta no promueve reglas automáticamente.

No tocar #4040, #4044, #4062, RATE-001, TIMEOUT-001, AUTH-047/049 ni ejecución protegida. No nuevas autorizaciones EXECUTE.

## Pruebas y límite

En el entorno local se ejecutaron 14/14 fixtures criptográficos Ed25519 con claves SINTÉTICAS efímeras y 9/9 fixtures SQLite en transacción ROLLBACK, incluyendo: éxito, falta de orden, scope equivocado, HEAD incorrecto, caducidad, repetición, actor equivocado, autoaprobación, firma equivocada, payload manipulado, sin trust root, regla diferente, cohorte duplicada, fecha futura, challenge diferente y revocación.

FALTAN: PG17 y PG18 contra el DDL, CI sobre HEAD exacto, autenticación real de evento de ChatGPT, políticas canónicas ACTIVE e integración del camino material al Train/decide. No existió prueba de recibo real ni escritura en Supabase. Cierre NO-GO.

Comando local con pytest y cryptography instalados:
 python -m pytest -q sandbox/lf_contract_gate_test/owner_chat_approval/
