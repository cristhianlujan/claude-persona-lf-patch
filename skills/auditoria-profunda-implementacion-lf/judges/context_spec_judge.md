# Juez contextual V1

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

LF al cierre PR #4009: request_v1 admite PASS_REVIEWED_CURRENT_CONTEXT y registra
NOT_PROVEN_OWNER_ACCEPTED. Verificar score, hashes, referencia de regla, autoridad
del perfil y hard_block. No añadir el viejo requisito de independencia a esa
solicitud. decide_v1 conserva aprobación humana; no confundir REQUEST con APPROVE
o APPLY. manifest.no_promotion no es veto vigente de esa ruta. Releer gobernanza
antes de cada auditoría futura.
