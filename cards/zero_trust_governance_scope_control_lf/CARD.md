# CARD_ZERO_TRUST_GOVERNANCE_SCOPE_CONTROL_LF_v0.1_CANDIDATO

Estado: VIGENTE_READ_ONLY_CONTROLADO / PRODUCCION_CONTROLADA_READ_ONLY / APROBADO_READ_ONLY_CONTROLADO
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Tipo: CARD_HABILIDAD_LF
Ambito: TRANSVERSAL_GOV
Perfil consumidor principal: PERFIL_SEGURIDAD_GOBERNANZA_LF_v0.1_CANDIDATO
Runtime: NO_HABILITADO
Impacto automatico: BLOQUEADO
Fuente operativa: ACT-0001 -> Supabase public.v_lf_fuente_operativa -> ACT-0045 -> lf_operation_*
Execution repair id: EXEC-CARDS-SEGURIDAD-GOBERNANZA-LF-20260530-001
Production promotion scope: READ_ONLY_CONTROLADO

## 0. Hard status

Esta card fue reparada, validada con judge formal y promovida a PRODUCCION_CONTROLADA_READ_ONLY para uso operativo de gobernanza read-only. No habilita runtime, no permite impacto automatico y no autoriza escrituras sin Router, Supabase, protocolo aplicable, evidencia y verificacion.

Cualquier intento de pasar esta card a runtime, impacto automatico, produccion ejecutiva con escritura o cambio de estado fuera de read-only requiere una nueva ejecucion formal, judge PASS y aprobacion explicita.

## 1. Proposito operativo

Aplicar control Zero Trust al alcance y autorizacion de operaciones de gobernanza LF: negar por defecto, vincular aprobacion al alcance exacto, exigir pre-write gate, bloquear bypass de alcance parcial, activar Security Hold si algo nace contaminado y cerrar solo con evidencia verificable.

Esta card no aprueba acciones. Debe producir un `Zero Trust Scope Control Output` estructurado que el Perfil Seguridad Gobernanza pueda consumir antes de permitir herramientas, impacto, cambio de estado o cierre.

## 2. Principios

1. Deny by default: nada esta permitido hasta que el alcance exacto lo permita.
2. Approval binding: una aprobacion solo cubre el objeto, sistema, fase y lote declarados.
3. Least privilege: usar la minima herramienta y escritura necesaria.
4. Pre-write gate: ninguna escritura sin precheck completo.
5. Evidence-first closure: no hay cierre sin execution_id, readback, judge y evidencia.
6. No double truth: Drive, GitHub, Supabase y chat no deben quedar como fuentes contradictorias.
7. State separation: crear archivo no autoriza marcar aprobado; readback no autoriza runtime.

## 3. Cuando usarla

Usar cuando:

- una aprobacion parcial pueda expandirse a otro sistema, activo o fase;
- se quiera escribir en GitHub, Drive, Supabase, Docs, Sheets, HTML o n8n;
- exista diferencia entre destino permitido, destino tecnico y destino canonico;
- se intente registrar Supabase sin readback externo;
- se cree, repare o regularice un perfil/card/skill;
- haya riesgo de GOVERNANCE_SCOPE_BYPASS;
- exista activo contaminado, cierre falso o Security Hold;
- el usuario diga `ok`, `conforme`, `continua`, `arreglalo`, `subelo` o equivalente en una fase ambigua.

## 4. Cuando no usarla

No usar en tareas puramente explicativas sin herramienta, activo, decision, alcance ni cierre operativo.

Si la tarea toca activos, usarla por defecto en modo read-only.

## 5. Inputs minimos

- objeto exacto solicitado;
- sistema destino;
- ruta destino;
- alcance autorizado;
- fase autorizada;
- activo rector;
- protocolo aplicable;
- duplicidad revisada;
- readback esperado;
- registro operativo esperado;
- restrictions de runtime, estado e impacto automatico;
- autorizacion exacta o razon de bloqueo.

## 6. Output obligatorio: Zero Trust Scope Control Output

La card debe devolver un objeto estructurado con estos campos:

- `card`
- `scope_matrix`
- `approval_binding_result`
- `destination_decision`
- `pre_write_gate_result`
- `tool_permission_result`
- `state_change_permission`
- `readback_requirement`
- `security_hold_status`
- `blocking_codes`
- `closure_verdict`
- `next_safe_gate`
- `self_verdict`

Si devuelve solo prosa, recomendaciones o checklist suelto, el output es invalido.

## 7. Pre-write gate obligatorio

Antes de escribir, validar:

1. Router leido.
2. Fuente operativa Supabase leida.
3. Activo rector identificado.
4. Protocolo aplicable identificado.
5. Duplicidad revisada.
6. Destino canonico decidido.
7. Destino tecnico validado.
8. Nombre validado.
9. Alcance exacto autorizado.
10. Execution_id creado cuando el protocolo lo exija.
11. Runtime seguira NO_HABILITADO.
12. Impacto automatico seguira BLOQUEADO.
13. Readback definido.
14. Judge/checklist definido.
15. Registro operativo definido.
16. Cierre definido como permitido o bloqueado.

Si falta un punto: `BLOCKED_PRE_WRITE_GATE`.

## 8. Bloqueo de alcance parcial

Ejemplos:

- Aprobar GitHub no autoriza Supabase.
- Aprobar perfil no autoriza cards extras.
- Aprobar revision no autoriza impacto.
- Aprobar reparacion no autoriza estado VIGENTE.
- Aprobar Drive como manual no lo convierte en fuente tecnica final.
- Crear archivo no autoriza marcar APROBADO.
- Readback de GitHub no autoriza runtime.
- `ok conforme` no autoriza herramientas nuevas, cambio de estado ni cierre total.

## 9. Security Hold

Aplicar o mantener `SECURITY_HOLD_REQUIRED` si un activo nace o permanece:

- sin Router;
- sin contrato;
- sin duplicidad;
- sin autorizacion exacta;
- en destino incorrecto;
- sin readback;
- con registro Supabase falso;
- por decision autonoma del asistente;
- como resultado de contexto rojo no controlado;
- sin research pack cuando el protocolo lo exige;
- sin execution_id para cierre o cambio de estado.

## 10. Cierre verificable

Solo cerrar si:

- la operacion ejecutada coincide con el alcance;
- existe execution_id formal;
- hay readback del sistema escrito;
- los pasos requeridos tienen evidencia;
- el judge da PASS;
- el estado sigue CANDIDATO / EN_REVISION / REQUIERE_SANDBOX si aplica;
- runtime sigue NO_HABILITADO;
- impacto automatico sigue BLOQUEADO;
- no se ejecuto HTML;
- no se marcaron VIGENTE, APROBADO ni VALIDATED;
- registro operativo se hizo solo despues de evidencia;
- incidentes fueron declarados.

## 11. Blocking codes

- `BLOCKED_PRE_WRITE_GATE`
- `BLOCKED_SCOPE_BYPASS_ATTEMPT`
- `BLOCKED_DESTINATION_NOT_VALIDATED`
- `BLOCKED_APPROVAL_AMBIGUOUS`
- `BLOCKED_EXECUTION_ID_REQUIRED`
- `BLOCKED_RESEARCH_PACK_NOT_EXECUTED`
- `BLOCKED_READBACK_REQUIRED`
- `BLOCKED_JUDGE_REQUIRED`
- `BLOCKED_LOG_AS_EXECUTION_SUBSTITUTE`
- `BLOCKED_RUNTIME_ENABLE_ATTEMPT`
- `BLOCKED_AUTOMATIC_IMPACT_ENABLE_ATTEMPT`
- `SECURITY_HOLD_REQUIRED`

## 12. Veredictos

- `SCOPE_ALLOWED_READ_ONLY`
- `READY_FOR_REVIEW_PACKAGE`
- `READY_FOR_CONTROLLED_IMPACT`
- `BLOCKED_PRE_WRITE_GATE`
- `BLOCKED_SCOPE_BYPASS_ATTEMPT`
- `BLOCKED_DESTINATION_NOT_VALIDATED`
- `SECURITY_HOLD_REQUIRED`
- `CLOSURE_PASS`
- `CLOSURE_BLOCKED_EVIDENCE_MISSING`
- `PASS_WITH_RESTRICTIONS`

## 13. Research pack base usado en reparacion

Fuentes internas:

- ACT-0001 Router.
- ACT-0045 creadora de perfiles/cards.
- PERFIL_SEGURIDAD_GOBERNANZA_LF reparado.
- CREACION_CARD_LF.
- Supabase lf_activos y lf_operation_execution.
- GitHub readback de cards existentes.

Fuentes externas/comparables:

- NIST AI Risk Management Framework.
- NIST SP 800-207 Zero Trust Architecture.
- OWASP Top 10 for LLM Applications.
- ISO/IEC 42001 AI management systems.

Patrones aplicados:

- negar por defecto;
- vincular permiso al alcance exacto;
- minimo privilegio;
- pre-write gate;
- evidencia antes de cierre;
- verificacion continua;
- trazabilidad y mejora controlada sin runtime por defecto.

## 14. Test sandbox minimo

Escenario: se aprueba crear un perfil madre y dos cards, pero no runtime ni estado vigente.

PASS si la card:

- permite solo esas tres rutas;
- bloquea perfil Zero Trust separado;
- bloquea cards adicionales;
- exige execution_id y readback;
- impide registrar Supabase antes de evidencia;
- mantiene runtime NO_HABILITADO;
- bloquea VIGENTE/APROBADO/VALIDATED;
- emite `Zero Trust Scope Control Output` estructurado.

## 15. Criterio de uso vigente

Esta card queda VIGENTE_READ_ONLY_CONTROLADO / PRODUCCION_CONTROLADA_READ_ONLY / APROBADO_READ_ONLY_CONTROLADO.

Puede usarse para:

1. controlar alcance exacto;
2. bloquear expansion no autorizada de permisos;
3. exigir pre-write gate antes de herramientas;
4. separar revision, impacto, readback y cierre;
5. emitir Zero Trust Scope Control Output.

No puede usarse para:

1. habilitar runtime;
2. ejecutar impacto automatico;
3. aprobar escrituras por si sola;
4. saltar Router, Supabase o protocolo aplicable;
5. marcar VALIDATED o produccion ejecutiva con escritura sin nuevo ciclo formal.
