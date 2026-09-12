# LF Skill Usage Routing Guardrail

**Codigo propuesto:** DOC-LF-SKILL-USAGE-ROUTING-GUARDRAIL-v0.1-CANDIDATO  
**Proyecto:** 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF  
**Estado:** CANDIDATO / GUARDRAIL OPERATIVO TRANSVERSAL  
**Uso:** Evitar que cualquier chat, proyecto o subproceso use skills, perfiles, cards, adapters, checklists o prompts reutilizables como punto de entrada directo.  
**Restriccion:** Este documento no habilita runtime, produccion general, cambios a ACT-0045, cambios a ACT-0046 ni escrituras Supabase.

---

## 1. Ruta obligatoria para uso de skills

Toda solicitud que pretenda usar una skill LF debe iniciar por la ruta madre:

```text
Router -> Fuente operativa Supabase / public.v_lf_fuente_operativa -> Activo vigente -> Adapter si aplica -> Operacion -> Verificacion -> Cierre
```

La skill no es puerta de entrada. La skill solo puede activarse como destino posterior al Router cuando el activo vigente y sus restricciones lo permitan.

---

## 2. Problema que previene

Este guardrail previene que un chat nuevo:

- entre directo a una skill como si fuera un prompt independiente,
- use perfiles, cards, checklists o adapters sin verificar activo vigente,
- opere con memoria conversacional en vez de fuente operativa,
- cree reglas o documentos duplicados cuando ya existe un activo aplicable,
- habilite runtime, produccion general o impacto automatico sin aprobacion,
- confunda un activo candidato/read-only con un activo operativo libre.

---

## 3. Autoridades verificadas para este guardrail

Consulta operativa realizada sobre `public.v_lf_fuente_operativa` antes de crear este PR:

| Activo | Nombre canonico | Estado documental | Estado operativo | Nivel control | Runtime | Impacto automatico |
|---|---|---|---|---|---|---|
| ACT-0001 | DOC_ROUTER_OPERATIVO_GOBERNANZA_LF | VIGENTE | ACTIVO | RECTOR | NO_APLICA | BLOQUEADO |
| ACT-0045 | SKILL_CREADORA_PERFILES_Y_CARDS_LF_v0.1_CANDIDATO | VIGENTE | READ_ONLY | PRODUCCION_CONTROLADA | PRODUCCION_CONTROLADA_READ_ONLY | BLOQUEADO |
| ACT-0046 | SKILL_MOTOR_APRENDIZAJE_CONTINUO_CAPACIDADES_LF_v0.1_CANDIDATO | CANDIDATO | READ_ONLY | SIN_CONTROL | CANDIDATE_READ_ONLY | BLOQUEADO |

Interpretacion:

- ACT-0001 manda como Router rector.
- ACT-0045 puede orientar Skill Factory / Skill Creator / Profile Creator / Cards, pero no habilita runtime libre.
- ACT-0046 existe para Motor de Aprendizaje, pero sigue candidato/read-only y no debe usarse como entrada directa.

---

## 4. Regla madre de consumo de skills

Antes de usar cualquier skill LF, el chat debe responder internamente estas preguntas:

1. La solicitud es operativa o toca proyecto, estado, documento, decision, impacto, skill, perfil, card, adapter, Supabase, GitHub, PR, CI, sandbox o cierre?
2. Si la respuesta es si, se aplico Router?
3. Se consulto `public.v_lf_fuente_operativa` o se declaro limitacion de acceso?
4. Existe activo vigente aplicable?
5. El activo permite operacion o esta read-only/candidato?
6. Hay adapter aplicable?
7. La operacion requiere PR, Quality Pack Review, Sandbox Test o aprobacion explicita?
8. La respuesta cerrara con verificacion y control de contexto?

Si cualquier respuesta critica falta, la skill no debe ejecutarse como destino operativo.

---

## 5. Criterios de bloqueo

Bloquear o devolver a Router cuando ocurra cualquiera de estos casos:

```text
SKILL_ENTRYPOINT_BYPASS
```

Se intento usar una skill, perfil, card, checklist, prompt reutilizable o adapter sin pasar por Router.

```text
ACTIVE_SOURCE_NOT_VERIFIED
```

No se verifico Supabase / `public.v_lf_fuente_operativa` ni se declaro una limitacion valida.

```text
ASSET_READ_ONLY_RUNTIME_BLOCKED
```

El activo aplicable existe, pero esta en READ_ONLY, CANDIDATE_READ_ONLY o PRODUCCION_CONTROLADA_READ_ONLY, y la solicitud requiere impacto, runtime, produccion general o escritura.

```text
DUPLICATE_RULE_RISK
```

La solicitud intenta crear una regla especifica nueva cuando debe consolidarse en una regla madre reutilizable.

```text
CROSS_CHAT_DRIFT_RISK
```

Otro chat intenta continuar un frente operativo sin heredar ruta, fuente operativa, activo vigente y restricciones.

---

## 6. Aplicacion al Motor de Aprendizaje

Para chats del proyecto MOTOR_APRENDIZAJE_DE_EXPERTOS, la secuencia correcta es:

```text
Router -> Supabase / public.v_lf_fuente_operativa -> ACT-0046 si aplica -> Adapter si aplica -> Operacion controlada -> Verificacion -> Cierre
```

Restricciones especificas:

- No usar `SKILL_MOTOR_APRENDIZAJE_CONTINUO_CAPACIDADES_LF_v0.1_CANDIDATO` como entrada directa.
- No crear documentos, cards, perfiles, reglas o impactos finales solo por estar en el chat del motor.
- No asumir que ACT-0046 esta aprobado para runtime.
- Si se requiere mejora transversal, enviarla a backlog/sandbox/aprobacion/impacto controlado.
- Si el frente toca Skill Factory, Profile Creator o Cards, verificar tambien ACT-0045.

---

## 7. Prompt corto para traspaso entre chats

```text
Antes de usar cualquier skill LF, aplicar:
Router -> Supabase public.v_lf_fuente_operativa -> Activo vigente -> Adapter si aplica -> Operacion -> Verificacion -> Cierre.

No entrar directo a skills, perfiles, cards, adapters, prompts reutilizables ni checklists.

Verificar activo aplicable en Supabase:
- ACT-0001 Router es rector.
- ACT-0045 aplica a Skill Factory / Skill Creator / Profile Creator / Cards y esta READ_ONLY.
- ACT-0046 aplica a Motor de Aprendizaje y esta CANDIDATO / READ_ONLY.

No escribir Supabase ni habilitar runtime/produccion general sin aprobacion explicita.
Cerrar con verificacion y control de contexto.
```

---

## 8. Verificacion de cumplimiento

Un chat cumple este guardrail si su respuesta operativa muestra:

- ruta Router-first aplicada,
- fuente operativa usada o limitacion declarada,
- activo vigente identificado,
- restricciones respetadas,
- operacion delimitada,
- verificacion posterior,
- cierre con control de contexto.

No cumple si responde usando directamente una skill, perfil, card, adapter o checklist como primer paso.

---

## 9. Estado de este documento

Este documento es candidato tecnico en GitHub. No modifica ACT-0045 ni ACT-0046. No escribe Supabase. No habilita runtime. No habilita produccion general. No crea perfiles, cards ni skills finales.
