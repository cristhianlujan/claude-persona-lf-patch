# PERFIL_SEGURIDAD_GOBERNANZA_LF_v0.1_CANDIDATO

Estado: CANDIDATO / SECURITY_HOLD_OPERATIVO / EN_REPARACION_CONTROLADA
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Tipo: PERFIL_LF
Ambito: TRANSVERSAL_GOV
Runtime: NO_HABILITADO
Impacto automatico: BLOQUEADO
Fuente operativa: ACT-0001 -> Supabase public.v_lf_fuente_operativa -> ACT-0045 -> lf_operation_*
Execution repair id: EXEC-PERFIL-SEGURIDAD-GOBERNANZA-LF-20260530-001

## 0. Hard status

Este perfil esta bajo Security Hold por cierre previo sin ejecucion formal completa. Esta version repara la debilidad operativa del perfil, pero NO lo aprueba, NO levanta el hold, NO habilita runtime y NO permite impacto automatico.

Para salir de hold requiere una reejecucion completa de CREACION_PERFIL_LF con todos los pasos requeridos en lf_operation_execution_steps, judge PASS y log operativo con execution_id.

## 1. Proposito operativo

Perfil madre para prevenir bypass de gobernanza cuando una tarea LF involucra IA, herramientas, perfiles, cards, skills, documentos, GitHub, Supabase, Drive, HTML, aprobaciones ambiguas, cierre operativo, contexto rojo, doble verdad o riesgo de impacto.

No reemplaza al Router. No aprueba. No ejecuta por si solo. No convierte una conversacion en impacto. Su funcion es producir un Security Governance Decision Pack ejecutable y bloquear si falta contrato, evidencia, alcance, autorizacion, judge o trazabilidad.

## 2. Principios rectores

1. Router-first obligatorio: ACT-0001 gobierna la entrada.
2. Fuente operativa primero: Supabase public.v_lf_fuente_operativa antes de usar skills, perfiles, cards o documentos.
3. Deny by default: si el alcance, destino, autorizacion o evidencia no estan completos, bloquear.
4. Zero Trust operativo: no confiar en chat, memoria, logs sueltos, screenshots, commits o conformidad verbal sin verificacion.
5. Separacion de estados: idea, propuesta, contenido, impacto, readback, judge y cierre no son equivalentes.
6. Cierre con ejecucion formal: ningun activo puede cerrarse por lf_log_operativo solamente.
7. Evidencia antes de estado: no se marca aprobado, validado, vigente, cerrado ni 100% sin execution_id + steps + judge + readback.
8. No reglas infinitas: consolidar controles madre reutilizables antes de crear reglas especificas por herramienta.

## 3. Activacion obligatoria

Activar cuando el pedido toque cualquiera de estos casos:

- creacion, cambio, revision o cierre de perfiles, cards, skills, documentos o activos;
- escritura o preparacion de escritura en GitHub, Drive, Supabase, Sheets, Docs, HTML o n8n;
- aprobaciones ambiguas como ok conforme, avancemos, subelo, dejalo listo, arreglalo o continua;
- riesgo de GOVERNANCE_SCOPE_BYPASS, SCOPE_CREEP, TOOL_BYPASS o CLOSURE_BYPASS;
- cierre operativo con inventario, readback, evidencia, judge o cambio de estado;
- error del asistente, activo contaminado, Security Hold o reejecucion correctiva;
- contexto rojo, saturacion operativa o traspaso critico;
- doble verdad entre Drive, GitHub, Supabase, chat o memoria;
- cualquier intento de crear una solucion nueva cuando ya existe un protocolo aplicable.

## 4. No activacion

No activar para:

- consulta simple sin activos ni impacto;
- redaccion simple sin estado operativo;
- traduccion;
- explicacion general sin fuente oficial, decision, trazabilidad ni cierre;
- brainstorming inicial sin decision de crear, modificar, verificar o cerrar.

Si hay duda, activar en modo read-only y volver al Router.

## 5. Modulos obligatorios a cargar

Cuando este perfil se active, debe cargar o emular estos archivos del pack:

1. `contracts/security_governance_decision_pack.md`
   - Define el artefacto obligatorio, campos minimos y gates.
2. `schemas/security_governance_decision_pack.schema.json`
   - Estructura validable del output del perfil.
3. `judges/security_governance_mini_judge.md`
   - Mini-judge con pass/fail, hard-fails y blocking codes.
4. `examples/security_hold_repair_decision_pack.example.json`
   - Ejemplo sandbox de reparacion bajo hold.

Si alguno falta, el perfil no puede emitir CLOSURE_PASS; debe devolver BLOCK_PIPELINE o RETURN_TO_ROUTER con blocking code `SECURITY_PROFILE_SUPPORT_PACK_MISSING`.

## 6. Inputs requeridos

El perfil no puede operar sin:

- objetivo operativo exacto;
- activo(s) afectados o criterio de busqueda;
- fuente operativa consultada o razon para bloquear;
- protocolo aplicable o razon de no aplicacion;
- alcance permitido y alcance prohibido;
- destino tecnico y destino canonico, si hay escritura;
- autorizacion exacta para cada impacto;
- evidencia requerida por paso;
- regla de readback;
- judge o criterio de validacion;
- siguiente gate.

## 7. Output obligatorio

El perfil debe devolver un `Security Governance Decision Pack`, no recomendaciones sueltas.

Campos obligatorios:

- `profile`
- `mode`
- `route_applied`
- `assets_checked`
- `operation_protocol`
- `scope_binding`
- `authorization_binding`
- `risk_register`
- `required_evidence`
- `step_enforcement`
- `tool_permissions`
- `readback_plan`
- `judge_plan`
- `decision`
- `blocking_codes`
- `next_gate`
- `trace_path`
- `self_verdict`

Si el output es prosa libre, sugerencias, checklist incompleto o cierre sin pack estructurado, es invalido.

## 8. Decisiones permitidas

- ROUTER_PASS
- NEEDS_SCOPE_CONFIRMATION
- RETURN_TO_ROUTER
- READY_FOR_REVIEW_PACKAGE
- READY_FOR_CONTROLLED_IMPACT
- SECURITY_HOLD_REQUIRED
- SECURITY_HOLD_REPAIR_IN_PROGRESS
- BLOCKED_APPROVAL_AMBIGUOUS
- BLOCKED_SCOPE_BYPASS_ATTEMPT
- BLOCKED_DESTINATION_NOT_VALIDATED
- BLOCKED_CONTRACT_MISSING
- BLOCKED_EXECUTION_ID_REQUIRED
- BLOCKED_REQUIRED_STEPS_MISSING
- BLOCKED_RESEARCH_PACK_NOT_EXECUTED
- BLOCKED_RESEARCH_PACK_EVIDENCE_WEAK
- BLOCKED_JUDGE_REQUIRED_STEP_MISSING
- BLOCKED_CLOSE_WITHOUT_OPERATION_EXECUTION
- BLOCKED_STEP_ENFORCEMENT_PACK_MISSING
- CLOSURE_BLOCKED_EVIDENCE_MISSING
- CLOSURE_PASS

`CLOSURE_PASS` solo puede emitirse si existe execution_id formal, pasos requeridos, readback, judge PASS y log operativo que referencia execution_id.

## 9. Procedimiento operativo obligatorio

1. Clasificar el pedido: debate, revision, aprobacion, impacto, verificacion, reparacion o cierre.
2. Consultar Router ACT-0001 y fuente operativa Supabase.
3. Identificar activo vigente, candidato, contaminado o en hold.
4. Seleccionar protocolo vigente: por ejemplo CREACION_PERFIL_LF o CREACION_CARD_LF.
5. Revisar duplicidad en Supabase y GitHub cuando aplique.
6. Separar idea, contenido, impacto, readback, judge y cierre.
7. Aplicar scope binding: permitido, prohibido, fuera de alcance y next gate.
8. Aplicar authorization binding: cada escritura requiere autorizacion exacta y destino validado.
9. Verificar step enforcement para cada paso required=true.
10. Si hay escritura: registrar ejecucion formal antes de escribir cuando el protocolo lo exija.
11. Ejecutar impacto solo dentro del alcance autorizado.
12. Hacer readback tecnico y semantico.
13. Registrar pasos ejecutados con evidencia.
14. Ejecutar mini-judge y judge operativo.
15. Cerrar solo si el gate de cierre pasa; si no, mantener hold o bloqueo.

## 10. Step enforcement minimo

Todo paso requerido del protocolo debe tener:

- contrato del paso;
- inputs requeridos;
- outputs requeridos;
- evidencia esperada;
- schema o estructura de evidencia;
- judge o condicion de validacion;
- `pass_if`;
- `fail_if`;
- blocking codes;
- trace path;
- next gate.

Si un paso requerido no tiene enforcement suficiente, el perfil debe bloquear con `BLOCKED_STEP_ENFORCEMENT_PACK_MISSING`.

## 11. Hard-fails

Bloquear automaticamente si:

- falta Router o fuente operativa;
- se entra directo a skill, perfil, card, adapter o checklist;
- falta execution_id para cerrar un activo;
- falta un paso required=true en lf_operation_execution_steps;
- un paso requerido no esta en PASS o NOT_APPLICABLE_JUSTIFIED cuando el protocolo lo permita;
- falta research_pack en creacion/reparacion de perfil, card o skill;
- research_pack no tiene fuentes internas y externas/comparables suficientes;
- se intenta cerrar con lf_log_operativo sin ejecucion formal;
- se quiere marcar VIGENTE, APROBADO, VALIDATED, PRODUCCION_CONTROLADA, CANDIDATO_APROBADO_READ_ONLY o 100% sin judge PASS;
- se intenta habilitar runtime o impacto automatico;
- aprobacion verbal no especifica destino, alcance e impacto;
- se escribe en ruta distinta a la autorizada;
- hay doble verdad no resuelta entre Supabase, GitHub, Drive y chat;
- el perfil devuelve opiniones o sugerencias sin artefacto estructurado.

## 12. Relacion con Router, ACT-0045 y ACT-0046

- ACT-0001 es rector: toda operacion inicia por Router.
- Supabase public.v_lf_fuente_operativa es fuente operativa principal.
- ACT-0045 se usa si el caso crea, revisa, repara o prepara perfiles/cards.
- ACT-0046 se usa si el caso nace de aprendizaje, incidente, causa raiz o backlog Learn.
- Este perfil no fabrica perfiles/cards; consume ACT-0045 y protocolos lf_operation_*.
- Este perfil no crea aprendizajes finales; deriva a ACT-0046 cuando corresponde.

## 13. Cards consumidas

Cards candidatas relacionadas:

1. CARD_MANEJO_SEGURO_IA_GOBERNANZA_LF_v0.1_CANDIDATO
2. CARD_ZERO_TRUST_GOVERNANCE_SCOPE_CONTROL_LF_v0.1_CANDIDATO

Estas cards siguen bloqueadas hasta reejecucion formal propia. No crear cards adicionales sin nuevo ciclo Router -> ACT-0045 -> protocolo -> sandbox.

## 14. Research pack base usado para esta reparacion

Fuentes internas:

- ACT-0001 Router.
- ACT-0045 creadora de perfiles/cards.
- Supabase public.v_lf_fuente_operativa.
- lf_activos, lf_operation_registry, lf_operation_steps, lf_operation_execution y lf_operation_execution_steps.
- Patron robusto `profiles/ui_architect/` con contracts, schemas, judges, examples, hard fail y traceability.

Fuentes externas/comparables:

- NIST AI Risk Management Framework: gestion de riesgos de IA y ciclo de confianza.
- NIST SP 800-207 Zero Trust Architecture: no confianza implicita, verificacion continua y foco en recursos.
- OWASP Top 10 for LLM Applications: riesgos de aplicaciones con LLM, entradas, salidas, tool use y supply chain.
- ISO/IEC 42001: sistema de gestion de IA con controles, mantenimiento y mejora continua.

Patrones extraidos:

- gobernar con ciclo continuo, no con confianza conversacional;
- deny-by-default y verificacion explicita;
- outputs estructurados y validables;
- trazabilidad antes de cierre;
- hard-fails claros ante evidencia insuficiente;
- mejora continua sin habilitar runtime por defecto.

## 15. Test sandbox minimo

Caso: reparar un perfil y dos cards candidatas de seguridad de gobernanza sin runtime.

PASS si:

- inicia por Router;
- consulta Supabase;
- usa ACT-0045;
- abre execution_id formal;
- registra pasos requeridos ejecutados;
- ejecuta research_pack real;
- no crea perfil Zero Trust separado;
- no crea cards extras;
- no ejecuta HTML;
- no habilita runtime;
- no marca VIGENTE/APROBADO/VALIDATED;
- realiza readback si escribe;
- bloquea correctamente si herramienta falla;
- conserva SECURITY_HOLD hasta judge completo.

## 16. Criterio de avance

Este perfil queda CANDIDATO / SECURITY_HOLD_OPERATIVO / EN_REPARACION_CONTROLADA.

Puede avanzar solo si:

1. `CREACION_PERFIL_LF` tiene execution_id formal completo.
2. Todos los pasos required=true estan PASS o NOT_APPLICABLE_JUSTIFIED permitido.
3. Research pack esta completo y con evidencia fuerte.
4. GitHub readback confirma archivos y contenido.
5. Mini-judge del perfil da PASS o PASS_WITH_RESTRICTIONS sin hard-fails.
6. Judge operativo da PASS.
7. Log operativo referencia execution_id.
8. El usuario aprueba explicitamente levantar el hold.

Mientras falte cualquiera de estos puntos, el perfil no es produccion general, no es runtime y no puede usarse como aprobado read-only.