# LF — Recuperación ante bloqueo de seguridad de herramienta de OpenAI (V1)

**Alcance:** bloqueo explícito emitido por la capa de seguridad de OpenAI/ChatGPT al invocar una herramienta en una operación legítima de LF. Aplica transversalmente a tareas de GitHub, Supabase, Router e Input Governance; no crea un Router alterno, permisos nuevos, un workflow ni un desbloqueo automático.

**EKB consultado:** `IG-M92-TOOL-SAFETY-ATTRIBUTION-001` (ACTIVO), `ENGINEERING-CP-SECURITY-CONTEXT-NO-EXPLICITO-028` (VALIDATED_TESTED). Mantener sus reglas de atribución y evidencia. Este documento es una extensión de recuperación; no pretende modificar la política viva de EKB por sí mismo.

## 1. Activación exacta

Activar **`OPENAI_SAFETY_BLOCK_REVIEW`** solo si el mensaje literal identifica a OpenAI como emisor del bloqueo de seguridad, por ejemplo:

`Los controles de seguridad de OpenAI bloquearon esta llamada a la herramienta. Verifica nuevamente lo que estás intentando enviar.`

No activar por error SQLSTATE, HTTP 403/429, falta de rol, bloqueo del Router, restricción EKB, `permission denied` de GitHub, timeout o una inferencia genérica. Si el emisor no está demostrado: `ORIGIN_UNVERIFIED`; inspeccionar sin atribuir ni reetiquetar el proveedor externo.

## 2. Secuencia breve, sin eludir controles

1. **Congelar la invocación fallida.** Guardar nombre de operación, herramienta, paso, error literal, momento con zona horaria, request/trace ID si existe y efectos efectivamente observados. Sin afirmar que GitHub/Supabase recibió la llamada.
2. **Recuperar contexto y EKB.** Objetivo legítimo, propiedad/autorización del repositorio o recurso, ruta Router/PR/commit y controles vigentes; usar solo identificadores comprobados. Distinguir tipo de operación (lectura, cambio de candidato, escritura gobernada, producción) y privilegios.
3. **Comprobar si hay riesgo real.** Si la petición sí viola una política aplicable, detenerse y resolver mediante un flujo permitido. No utilizar esta salida para insistir en una solicitud prohibida. Si parece un falso positivo, clasificar `POSSIBLE_FALSE_POSITIVE`, no `SAFETY_CLEARED`.
4. **Generar descargos breves y verificables.** Indicar finalidad empresarial, activo propio, alcance técnico preciso, vía autorizada, efecto esperado y límites (sin credenciales, accesos ocultos, bypass, cambio de permisos o ejecución no aprobada). Adjuntar código/error exacto y evidencia no sensible.
5. **Solicitar revisión por canal oficial cuando persista.** Para ChatGPT, usar el Centro de Ayuda de OpenAI (https://help.openai.com/), icono de chat de Soporte. Incluir error, fecha/hora/zona, producto/modelo, request ID si existe, y explicación anonimizada. El asistente puede preparar el texto; **no puede afirmar que lo envió ni que la plataforma levantó el bloqueo** sin acuse de recibo real. No existe aquí una acción autorizada de desbloqueo automático.
6. **Continuidad sin pérdida de avance.** Registrar `PROVIDER_BLOCKED_PENDING_REVIEW` y el siguiente paso. Seguir trabajo independiente seguro por la ruta habitual. Reanudar la operación original solo cuando la herramienta vuelva a permitirla, con autorización normal y readback, nunca declarando PASS a partir del descargo.

No simular una aprobación de OpenAI, no editar el mensaje de error, no recurrir a rutas alternativas para saltar el bloqueo, no repetir en bucle la solicitud rechazada. La simplificación del alcance solo es válida cuando mejora claridad o elimina datos innecesarios sin evadir una prohibición aplicable. Un bloqueo de seguridad de OpenAI **no es** una prueba de fallo de GitHub, PostgreSQL ni del repositorio.

## 3. Evidencia y clasificación de salida

Registrar, en el mecanismo de errores/observaciones existente (sin nueva tabla ni cola):

| Campo | Contrato |
|---|---|
| `provider` | `OPENAI` solo por mensaje literal |
| `error_origin` | `OPENAI_TOOL_SAFETY` |
| `error_literal` | Texto exacto, sin interpolaciones |
| `operation_ref` | Ruta/PR/commit/ejecución observados, no inventados |
| `intent_and_authority` | Actividad legítima, propiedad y autorización comprobadas |
| `business_impact` | Paso afectado; no atribuir falla externa |
| `appeal_packet_status` | `PREPARED`, `SUBMITTED_WITH_RECEIPT` o `NOT_SUBMITTED` |
| `recovery_status` | `POSSIBLE_FALSE_POSITIVE`, `PROVIDER_BLOCKED_PENDING_REVIEW`, `RESUMED_WITH_READBACK` o `STOP_POLICY_APPLIES` |

**Descargo breve de referencia (adaptar solo con datos verificados):**

> Estamos trabajando en una operación autorizada sobre un recurso propio. La acción bloqueada fue [operación exacta] en [herramienta] para [objetivo legítimo]. Se limita a [alcance/efecto], bajo [ruta/permiso verificado]; no solicita acceso no autorizado ni altera mecanismos de seguridad. El bloqueo mostrado fue: «[mensaje literal]». Solicitamos revisión por posible falso positivo. Referencia: [PR/commit/run], fecha y hora [zona], request ID [si existe].

## 4. Pruebas mínimas de aceptación

- **Positivo:** bloqueo con literal explícito de OpenAI => `OPENAI_SAFETY_BLOCK_REVIEW` y descargos preparados, sin cambios a permisos ni confirmación ficticia.
- **Negativo A:** `permission denied` / SQLSTATE / fallo de GitHub => no clasificar OpenAI, continuar diagnóstico del emisor real.
- **Negativo B:** solicitud que infringiría una restricción real => `STOP_POLICY_APPLIES`, sin reintento de evasión.
- **Negativo C:** descargo sin acuse de Soporte => `NOT_SUBMITTED`, no `SUBMITTED_WITH_RECEIPT`.
- **Readback:** un reintento legítimo solo es `RESUMED_WITH_READBACK` si produjo efecto autorizado comprobable.

## 5. Referencia oficial de revisión

- https://help.openai.com/en/articles/9824988-why-was-my-chatgpt-prompt-blocked
- https://help.openai.com/en/articles/20001326-additional-safety-checks-for-biological-and-cybersecurity-requests-in-chatgpt-codex-and-the-api
- https://help.openai.com/en/articles/6614161-how-can-i-contact-support

**Estado del documento:** candidato para incorporación transversal; su presencia en GitHub no significa que una capa de herramientas de ChatGPT implemente automáticamente la revisión ni que EKB vivo esté modificado.
