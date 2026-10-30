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
4. **Recuperación acotada conforme a EKB.** Si la política aplicable lo permite, se puede realizar un sondeo mínimo y como máximo un reintento ordinario de la misma operación autorizada, sin cambiar destino, permisos ni contenido para evadir el control. Registrar resultados reales; si persiste el bloqueo, continuar con la revisión. No interpretar un sondeo exitoso como aprobación de la operación bloqueada.
5. **Generar descargos breves y verificables.** Indicar finalidad empresarial, activo propio, alcance técnico preciso, vía autorizada, efecto esperado y límites (sin credenciales, accesos ocultos, bypass, cambio de permisos o ejecución no aprobada). Adjuntar código/error exacto y evidencia no sensible.
6. **Solicitar revisión por canal oficial cuando persista.** Para ChatGPT, usar el Centro de Ayuda de OpenAI (https://help.openai.com/), icono de chat de Soporte. Incluir error, fecha/hora/zona, producto/modelo, request ID si existe, y explicación anonimizada. El asistente puede preparar el texto; **no puede afirmar que lo envió ni que la plataforma levantó el bloqueo** sin acuse de recibo real. No existe aquí una acción autorizada de desbloqueo automático.
7. **Continuidad sin pérdida de avance.** Registrar `PROVIDER_BLOCKED_PENDING_REVIEW` y el siguiente paso. Seguir trabajo independiente seguro por la ruta habitual. Reanudar la operación original solo cuando la herramienta vuelva a permitirla, con autorización normal y readback, nunca declarando PASS a partir del descargo.

No simular una aprobación de OpenAI, no editar el mensaje de error, no recurrir a rutas alternativas para saltar el bloqueo, no repetir en bucle la solicitud rechazada. La simplificación del alcance solo es válida cuando mejora claridad o elimina datos innecesarios sin evadir una prohibición aplicable. Un bloqueo de seguridad de OpenAI **no es** una prueba de fallo de GitHub, PostgreSQL ni del repositorio.

## 2A. Control obligatorio: declaración de contexto del agente interno LF

**Disparador:** únicamente el rechazo **literal** `OPENAI_TOOL_SAFETY` establecido en §1. No se ejecuta ante permisos, SQLSTATE, errores de GitHub, un bloqueo gobernado del Router, ni ante un mensaje cuya procedencia no esté identificada.

**Acción inmediata del agente, antes de culpar al sistema o proponer otra ruta:**

1. Comunicar **`OPENAI_SAFETY_BLOCK_REVIEW`** y la operación exacta que quedó **sin efecto verificado**; distinguir claramente que es un bloqueo de la plataforma de herramientas y **no** un FAIL de Router, Input Governance o `EJECUCION_PERFIL_LF`.
2. Incorporar estos cinco hechos verificables en el descargo: `internal_system=LF`, `agent_role`, `operation`, `required_for` (dependencia real del funcionamiento), `authorized_path`. Incluir `permissions_and_effects` para precisar los límites (lectura, candidato o escritura autorizada). Si alguno no está demostrado, marcar `NO_VERIFICADO`; **no inventarlo**.
3. Explicar expresamente: **«Esta solicitud corresponde a un agente interno de Libertad Financiera (LF), dedicado a operar y verificar nuestro sistema bajo una ruta autorizada. La acción [operación] es necesaria para [dependencia funcional verificable]. No pretende vulnerar mecanismos de seguridad, obtener accesos indebidos ni eludir controles; la autorización y el efecto esperado son [datos comprobados]. Solicitamos revisión de un posible falso positivo.»** Esta declaración es contexto, no una prueba automática de inocuidad ni autorización para sortear un bloqueo.
4. Recuperar la operación únicamente según §2 (prueba mínima y, cuando esté permitido, **un** reintento normal con el **mismo alcance y controles**). Si persiste, registrar `PROVIDER_BLOCKED_PENDING_REVIEW`, conservar el paso siguiente y preparar revisión por el canal oficial de OpenAI. **No reescribir el mensaje para engañar filtros ni crear rutas alternativas de escritura.**
5. Reanudar solo si la ejecución autorizada llega realmente al destino y el readback confirma el resultado; caso contrario `NO_EJECUTADO`.

**Caso observado en LF (2026-10-30, prueba Router → perfil para Login B2B):** la petición para crear una solicitud gobernada en GitHub fue rechazada con el literal «Los controles de seguridad de OpenAI bloquearon esta llamada a la herramienta. Verifica nuevamente lo que estás intentando enviar». La operación buscaba continuar el paso de admisión del perfil a través de la ruta OIDC ya definida; no hay recibo de creación del issue ni de despacho. **Estado correcto:** `OPENAI_TOOL_SAFETY / POSSIBLE_FALSE_POSITIVE / NOT_SUBMITTED`, sin imputar la falla a GitHub, Router, Supabase ni a la función de admisión. Este caso documenta el intento, no certifica ausencia de riesgo ni apertura de un expediente de soporte.

**Límite de automatización:** una regla escrita en este repositorio **no intercepta por sí sola** los controles de seguridad de ChatGPT/OpenAI ni los desbloquea. El agente debe aplicar este protocolo en cuanto observe el literal; una aplicación automática requeriría integración de telemetría y permisos específicos, actualmente **NO_VERIFICADOS**.

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

**Estado del documento:** protocolo de respuesta documentado para agentes LF. Su presencia en GitHub no significa que la capa de herramientas de ChatGPT lo ejecute automáticamente, que OpenAI haya desbloqueado una llamada ni que el EKB vivo esté modificado.
