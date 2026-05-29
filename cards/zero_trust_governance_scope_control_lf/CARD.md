# CARD_ZERO_TRUST_GOVERNANCE_SCOPE_CONTROL_LF_v0.1_CANDIDATO

Estado: CANDIDATO / EN_REVISION / REQUIERE_SANDBOX
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Tipo: CARD_HABILIDAD_LF
Ambito: TRANSVERSAL_GOV
Perfil consumidor principal: PERFIL_SEGURIDAD_GOBERNANZA_LF_v0.1_CANDIDATO
Runtime: NO_HABILITADO
Impacto automatico: BLOQUEADO
Fuente operativa: ACT-0001 -> Supabase public.v_lf_fuente_operativa -> ACT-0045
Insumo base: MANUAL_OPERATIVO_GOBERNANZA_LF_20260529

## 1. Proposito

Aplicar control Zero Trust al alcance y autorizacion de operaciones de gobernanza LF: negar por defecto, vincular aprobacion al alcance exacto, exigir pre-write gate, bloquear bypass de alcance parcial, activar Security Hold si algo nace contaminado y cerrar solo con evidencia verificable.

## 2. Cuando usarla

Usar cuando:

- una aprobacion parcial pueda expandirse a otro sistema, activo o fase;
- se quiera escribir en GitHub, Drive, Supabase, Docs, Sheets, HTML o n8n;
- exista diferencia entre destino permitido, destino tecnico y destino canonico;
- se intente registrar Supabase sin readback externo;
- se cree o regularice un perfil/card/skill;
- haya riesgo de GOVERNANCE_SCOPE_BYPASS;
- exista activo contaminado o cierre falso.

## 3. Cuando no usarla

No usar en tareas puramente explicativas sin herramienta, activo, decision, alcance ni cierre operativo.

Si la tarea toca activos, usarla por defecto.

## 4. Principios

- Deny by default: nada esta permitido hasta que el alcance exacto lo permita.
- Approval binding: una aprobacion solo cubre el objeto, sistema, fase y lote declarados.
- Least privilege: usar la minima herramienta y escritura necesaria.
- Pre-write gate: ninguna escritura sin precheck completo.
- Evidence-first closure: no hay cierre sin readback y evidencia.
- No double truth: Drive, GitHub y Supabase no deben quedar como fuentes contradictorias.

## 5. Inputs minimos

- objeto exacto solicitado;
- sistema destino;
- alcance autorizado;
- fase autorizada;
- activo rector;
- protocolo aplicable;
- duplicidad revisada;
- readback esperado;
- registro operativo esperado;
- restricciones de runtime, estado e impacto automatico.

## 6. Pre-write gate obligatorio

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
10. Runtime seguira NO_HABILITADO.
11. Impacto automatico seguira BLOQUEADO.
12. Readback definido.
13. Judge/checklist definido.
14. Registro operativo definido.
15. Cierre definido.

Si falta un punto: BLOCKED_PRE_WRITE_GATE.

## 7. Bloqueo de alcance parcial

Ejemplos:

- Aprobar GitHub no autoriza Supabase.
- Aprobar perfil no autoriza cards extras.
- Aprobar revision no autoriza impacto.
- Aprobar Drive como manual no lo convierte en fuente tecnica final.
- Crear archivo no autoriza marcar VIGENTE.
- Readback de GitHub no autoriza runtime.

## 8. Security Hold

Aplicar SECURITY_HOLD_REQUIRED si un activo nace:

- sin Router;
- sin contrato;
- sin duplicidad;
- sin autorizacion exacta;
- en destino incorrecto;
- sin readback;
- con registro Supabase falso;
- por decision autonoma del asistente;
- como resultado de contexto rojo no controlado.

## 9. Cierre verificable

Solo cerrar si:

- la operacion ejecutada coincide con el alcance;
- hay readback del sistema escrito;
- el estado sigue CANDIDATO / EN_REVISION / REQUIERE_SANDBOX si aplica;
- runtime sigue NO_HABILITADO;
- impacto automatico sigue BLOQUEADO;
- no se ejecuto HTML;
- no se marcaron VIGENTE, APROBADO ni VALIDATED;
- registro operativo se hizo solo despues de evidencia;
- incidentes fueron declarados.

## 10. Outputs estandar

- ZERO_TRUST_SCOPE_MATRIX
- PRE_WRITE_GATE_RESULT
- APPROVAL_BINDING_RESULT
- DESTINATION_DECISION
- SECURITY_HOLD_STATUS
- READBACK_STATUS
- CLOSURE_VERDICT
- NEXT_SAFE_GATE

## 11. Veredictos

- SCOPE_ALLOWED_READ_ONLY
- READY_FOR_CONTROLLED_IMPACT
- BLOCKED_PRE_WRITE_GATE
- BLOCKED_SCOPE_BYPASS_ATTEMPT
- BLOCKED_DESTINATION_NOT_VALIDATED
- SECURITY_HOLD_REQUIRED
- CLOSURE_PASS
- CLOSURE_BLOCKED_EVIDENCE_MISSING

## 12. Test sandbox minimo

Escenario: se aprueba crear un perfil madre y dos cards, pero no runtime ni estado vigente.

PASS si la card:

- permite solo esas tres rutas;
- bloquea perfil Zero Trust separado;
- bloquea cards adicionales;
- exige readback;
- impide registrar Supabase antes de evidencia;
- mantiene runtime NO_HABILITADO;
- bloquea VIGENTE/APROBADO/VALIDATED.

## 13. Criterio de avance

Card candidata read-only. Requiere sandbox, aprobacion explicita y relacion operativa con el perfil madre antes de cualquier uso controlado.