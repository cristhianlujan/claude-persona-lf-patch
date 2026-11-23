# SALY · Reparación de literal de pedido y QA semántico de entrada

**Autorización:** dueño confirmó reparar solo la entrada y QA semántico de los pedidos #7 HOME / #8 SOLICITAR ADELANTO. No modificar colas, Native, diseño, reglas de copy, pedidos #4/#5, estado ni contextos sellados.

## Defecto identificado

La migración `supabase/migrations/20261123061613_lf_saly_creative_single_screen_sequence_v2.sql` (PR #4648) creó los dos pedidos con la **misma variable `literal`**:
> No, pero igual eso causa problema. Lo que debemos demandar es solo un pedido con una, o sea, la pantalla de Ergon que termine la pantalla de home y después haces la otra pantalla. Si no va a haber tendencia al error

Eso es una instrucción operacional, no el mensaje gráfico del usuario. El SHA-256 del texto reproducido en producción es
`835c6c243a95d651b473527bf92cb742067897916351919e408d3e5f0d868a3a`.

Los prompts `compiled_prompt` HOME y ADELANTO sí existen, hashes `13aac045a189b4f2dd085bf43e94f395666a20e7cc5ce87e596499c4a9100fd6` y `c77ce1be1a09aa64b7ab833c1207cc116b22cbe45682e5a7fe611abb5eb54f50`, respectivamente. Fueron elaborados en un **handoff local v0.15 desde entradas reconstruidas**. No son fuentes originales literales ni prueban autenticidad del mensaje del usuario.

## Reparación gobernada y alcance exacto

1. Se elimina el `scope_json.literal_request` erróneo únicamente para los dos pedidos afectados, tras verificar textualmente su SHA y preestado, y se conserva completo en `scope_json.operational_instruction` con su hash y procedencia `PR4648_SOURCE_SEED`.
2. Se registra `intake_source_status=MISSING_VERIFIED_USER_VISUAL_REQUEST` y QA `BLOCKED`. No se reconstruye ni inventa un texto de usuario.
3. El guard `saly.creative_intake_semantic_gate_v1` protege los futuros pedidos unitarios al registrar PLANIFICADO o autorizar ejecución; requiere mensaje visual literal, diferenciación de operacional, QA semántico con clase `CREATIVE_IMAGE_REQUEST` y hashes de literal + prompt. La veracidad del verificador/ref requiere un mecanismo externo de procedencia y no puede inferirse por JSON.
4. Los pedidos #7/#8 quedan `PLANIFICADO`, `review_only=true`, `render_authorized=false`; 0 RUN. El segundo sigue dependiendo de Home. El guard acepta solo esta cuarentena, no la promoción.
5. La SKILL mantiene `PLAN_ONLY/REVIEW_ONLY`, pero separa semánticamente proceso vs imagen antes de persistir. No hay generación ni paso adicional del workflow.

## Pruebas exigidas
PG17 aislado, con SQL exacto y subtransacciones negativas:
- Error específico de literal operacional incluso con una aprobación falsa.
- Error específico de fuente visual original faltante.
- Error específico por QA ausente.
- Error específico por SHA de QA/prompt diferente.
- Positivo **sintético solo del contrato de forma**, revertido en transacción (NO prueba juez independiente).
- Readback: 2 pedidos bloqueados, literal quitado, instrucción conservada, prompts/hash intactos, histórico intacto y 0 RUN.

## Pendiente de fuente
La solicitud visual literal original del usuario no se pudo recuperar inequívocamente de los handoffs. El próximo paso de entrada —no aprobado como fuente por esta migración— es vincular el mensaje original verificable y ejecutar QA semántico independiente sobre ambos textos/hashes. Sin esto no se puede desbloquear honestamente la generación.

**Reglas:** B1/B2/B3/B6/B11/B12/B19/B20/B25/B30/B31.
