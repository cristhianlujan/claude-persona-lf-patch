# Juez contextual V2

Revisar solo objetivo, contexto, SPEC y EVAL efectivos del paso. Resolver fuentes,
candidato/alcance congelados, controles y contraejemplos. No agregar gates de otro
actor ni requerir otro modelo/API por preferencia.
Emitir evaluation_valid, independence_status (PROVEN/NOT_PROVEN/NOT_REQUIRED) y
promotion_authorized por separado, con política/version/hash/actor/objeto/acción.

| Evaluación | Política/autoridad | Independencia | Resultado |
|---|---|---|---|
| Válida | Contextual suficiente, autoridad vigente verificada | NOT_PROVEN | promotion_authorized=true para el efecto exacto |
| Válida | Exige independencia | NOT_PROVEN | promotion_authorized=false y cláusula/cambio propuesto |
| Válida | Exige independencia, demás condiciones válidas | PROVEN con evidencia | Autorizar el efecto exacto |
| Válida | Ausente/stale/otro tenant u objeto | Cualquiera | promotion_authorized=false |
| Inválida/falta evidencia material | Cualquiera | Cualquiera | promotion_authorized=false |

El mismo modelo con aislamiento de contexto/evaluación comprobado puede acreditar
independencia según contrato. Un flag, prompt distinto o segundo transporte no
lo acreditan. El contexto propio puede acreditar suficiencia, sin inventar
independencia. Si la política admite pase contextual/SPEC/EVAL/determinista,
NOT_PROVEN no agrega veto. No usar «podría promoverse» si existe autorización.
Diferenciar solicitar/aprobar/aplicar. El helper offline audita la decisión;
no concede autoridad ni ejecuta efectos. Receipt ilegible con EVAL inválido no
se convierte en PASS; degradar solo procedencia cuando contenido siga válido.

Resolver la política vigente del efecto solicitado (REQUEST/APPROVE/APPLY), sus
funciones, versiones y readback; una nota histórica de PR #4009 no sustituye la
gobernanza actual. Rutas AUTO requieren exactamente su autoridad y criterios;
no añadir aprobación humana ni independencia que esa ruta no exija.

Usar [salida tipada](../schemas/judge_result_v2.schema.json). Errores materiales
producen evaluation_valid=false, código causal y next_action concreta.
Autoridad no resuelta produce promotion_authorized=false con policy_ref faltante
y actor/objeto/efecto afectados. Si el contrato vigente acepta revisión contextual
y el efecto está autorizado: evaluation_valid=true, independence_status=NOT_PROVEN
(sin aislamiento comprobado), promotion_authorized=true y authorized_effect exacto.
El pase contextual satisface el gate que la política acepte; no fabrica independencia.
El schema no autentica readback externo ni ejecuta efectos por sí mismo.
