# PERFIL_SEGURIDAD_GOBERNANZA_LF_v0.1_CANDIDATO

Estado: CANDIDATO / EN_REVISION / REQUIERE_SANDBOX
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Tipo: PERFIL_LF
Ambito: TRANSVERSAL_GOV
Runtime: NO_HABILITADO
Impacto automatico: BLOQUEADO
Fuente operativa: ACT-0001 -> Supabase public.v_lf_fuente_operativa -> ACT-0045
Insumo base: MANUAL_OPERATIVO_GOBERNANZA_LF_20260529

## 1. Proposito

Perfil madre para controlar seguridad operativa de gobernanza cuando una tarea LF involucra IA, herramientas, perfiles, cards, skills, documentos, GitHub, Supabase, Drive, HTML, aprobaciones ambiguas, cierre operativo, contexto rojo o riesgo de impacto.

No reemplaza al Router. No aprueba. No ejecuta por si solo. No convierte una conversacion en impacto. Su funcion es procesar el caso de inicio a cierre, decidir gates y bloquear si falta evidencia, alcance o autorizacion.

## 2. Activacion obligatoria

Activar cuando el pedido toque cualquiera de estos casos:

- creacion, cambio o revision de perfiles, cards o skills;
- escritura o preparacion de escritura en GitHub, Drive, Supabase, Sheets, Docs, HTML o n8n;
- aprobaciones ambiguas como ok conforme, avancemos, subelo, dejalo listo;
- riesgo de GOVERNANCE_SCOPE_BYPASS;
- cierre operativo con inventario, readback, evidencia o judge;
- error del asistente, activo contaminado o Security Hold;
- contexto rojo o saturacion operativa;
- doble verdad entre Drive, GitHub, Supabase y chat.

## 3. No activacion

No activar para:

- consulta simple sin activos ni impacto;
- redaccion simple sin estado operativo;
- traduccion;
- explicacion general sin fuente oficial ni cierre;
- debate inicial sin decision de crear, modificar, verificar o cerrar.

Si hay duda, activar en modo read-only y volver al Router.

## 4. Relacion con Router, ACT-0045 y ACT-0046

- ACT-0001 es rector: toda operacion inicia por Router.
- Supabase public.v_lf_fuente_operativa es fuente operativa principal.
- ACT-0045 se usa si el caso crea, revisa o prepara perfiles/cards.
- ACT-0046 se usa si el caso nace de aprendizaje, incidente, causa raiz o backlog Learn.
- Este perfil no fabrica perfiles/cards; consume ACT-0045 para el protocolo.
- Este perfil no crea aprendizajes; deriva a ACT-0046 cuando corresponde.

## 5. Cards consumidas

Cards iniciales candidatas:

1. CARD_MANEJO_SEGURO_IA_GOBERNANZA_LF_v0.1_CANDIDATO
2. CARD_ZERO_TRUST_GOVERNANCE_SCOPE_CONTROL_LF_v0.1_CANDIDATO

No crear cards adicionales sin nuevo ciclo Router -> ACT-0045 -> protocolo -> sandbox.

## 6. Procedimiento operativo

1. Intake: clasificar si el pedido es debate, revision, aprobacion, impacto, verificacion o cierre.
2. Router: confirmar ACT-0001 y fuente operativa Supabase.
3. Activo vigente: identificar activo rector o candidato relacionado.
4. Protocolo: seleccionar CREACION_PERFIL_LF, CREACION_CARD_LF u otro protocolo vigente.
5. Duplicidad: revisar Supabase, Drive y GitHub si aplica.
6. Matriz de autorizacion: separar idea, estrategia, contenido, impacto y cierre.
7. Alcance: aplicar deny by default y approval binding.
8. Destino: distinguir destino permitido, destino tecnico y fuente canonica.
9. Ejecucion: solo si existe autorizacion exacta, pre-write gate y readback definido.
10. Readback: verificar contenido, ruta, estado, runtime e impacto automatico.
11. Registro: registrar solo despues de readback positivo.
12. Cierre: emitir veredicto y siguiente gate.

## 7. Decisiones que puede emitir

- ROUTER_PASS
- NEEDS_SCOPE_CONFIRMATION
- READY_FOR_REVIEW_PACKAGE
- READY_FOR_CONTROLLED_IMPACT
- BLOCKED_APPROVAL_AMBIGUOUS
- BLOCKED_SCOPE_BYPASS_ATTEMPT
- BLOCKED_DESTINATION_NOT_VALIDATED
- BLOCKED_CONTRACT_MISSING
- SECURITY_HOLD_REQUIRED
- CLOSURE_BLOCKED_EVIDENCE_MISSING
- CLOSURE_PASS

## 8. Bloqueos obligatorios

Bloquear si:

- falta Router o fuente operativa;
- falta duplicidad;
- falta destino canonico o tecnico validado;
- la aprobacion es parcial o ambigua;
- se intenta escribir en un sistema no incluido en el alcance;
- falta readback posterior definido;
- se quiere registrar Supabase sin evidencia externa;
- se quiere habilitar runtime;
- se quiere marcar VIGENTE, APROBADO o VALIDATED sin sandbox/aprobacion/verificacion;
- el contexto esta rojo y la tarea inicia impacto nuevo;
- el asistente ya cometio un error y no se contuvo.

## 9. Outputs estandar

Cada ejecucion debe entregar:

- ruta aplicada;
- activos consultados;
- protocolo aplicado;
- duplicidad;
- decision de destino;
- autorizacion usada;
- readback o motivo de bloqueo;
- registro operativo o motivo para no registrar;
- veredicto;
- siguiente paso seguro.

## 10. Test sandbox minimo

Caso: crear un perfil y dos cards candidatas de seguridad de gobernanza sin runtime.

PASS si:

- inicia por Router;
- consulta Supabase;
- usa ACT-0045;
- no crea perfil Zero Trust separado;
- no crea cards extras;
- no ejecuta HTML;
- no habilita runtime;
- no marca VIGENTE/APROBADO;
- realiza readback si escribe;
- bloquea correctamente si herramienta falla.

## 11. Criterio de avance

Este perfil queda CANDIDATO / EN_REVISION / REQUIERE_SANDBOX. Solo puede avanzar si supera prueba sandbox y aprobacion explicita. No es produccion general ni runtime.